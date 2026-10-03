#!/usr/bin/env python3
"""Geometry-based, local glide decoder for TabletMode's vendored wvkbd.

wvkbd sends a bounded JSON line containing sampled touch coordinates and the
letter centres of the *currently rendered* layout. This process never sees
focused-app, clipboard, dictation, or search text. It works asynchronously so
dictionary scoring cannot affect pointer rendering or key delivery.

The compact matcher follows the SHARK2-style template family: it normalizes and
arc-length-resamples a real trajectory, makes word templates from supplied key
centres, strongly prunes endpoint anchors, then combines shape, location,
length, corner/order, and repeated-letter loop evidence. The implementation is
our own small Python version; see README for the architectural reference.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import subprocess
import sys
from functools import lru_cache
from pathlib import Path
from typing import Iterable, Sequence

ROOT = Path(__file__).resolve().parent.parent
LEXICON = ROOT / "data" / "glide-lexicon.txt"
WORD = re.compile(r"^[a-zäöüß]{2,32}$", re.IGNORECASE)
MAX_MESSAGE = 4095  # strictly below Linux PIPE_BUF
SAMPLES = 28
MAX_WORDS = 70000
ACCENT_HOST = str.maketrans({"ä": "a", "ö": "o", "ü": "u", "ß": "s"})

Point = tuple[float, float]
Geometry = dict[str, Point]


def dictionary_files(language: str) -> list[Path]:
    names = {
        "de": ("de_DE.dic", "de_DE_frami.dic", "de_CH.dic"),
        "en": ("en_US.dic", "en_GB.dic", "en.dic"),
    }[language]
    roots = (Path("/usr/share/hunspell"), Path("/usr/share/myspell/dicts"), Path("/usr/share/myspell"))
    return [root / name for root in roots for name in names if (root / name).is_file()]


@lru_cache(maxsize=2)
def load_words(language: str) -> tuple[str, ...]:
    """Use locally installed hunspell data, preserving stable source order.

    Hunspell affix flags are removed. If no dictionary exists, the tracked
    compact lexicon keeps glide useful offline with no runtime download.
    """
    words: list[str] = []
    seen: set[str] = set()
    for filename in dictionary_files(language):
        try:
            for raw in filename.open(encoding="utf-8", errors="ignore"):
                word = raw.strip().split("/", 1)[0].lower()
                if WORD.fullmatch(word) and word not in seen:
                    seen.add(word)
                    words.append(word)
                if len(words) >= MAX_WORDS:
                    break
        except OSError:
            continue
        if len(words) >= MAX_WORDS:
            break
    if words:
        return tuple(words)
    try:
        for raw in LEXICON.open(encoding="utf-8"):
            tag, _, word = raw.partition("\t")
            word = word.strip().lower()
            if tag in (language, "both") and WORD.fullmatch(word) and word not in seen:
                seen.add(word)
                words.append(word)
    except OSError:
        pass
    return tuple(words)


def languages(choice: str) -> tuple[str, ...]:
    return ("de", "en") if choice == "auto" else (choice,)


def metric(a: Point, b: Point, aspect: float) -> float:
    """Physical distance after coordinates have been normalized to [0, 1]."""
    return math.hypot(a[0] - b[0], (a[1] - b[1]) / aspect)


def polyline_length(points: Sequence[Point], aspect: float) -> float:
    return sum(metric(a, b, aspect) for a, b in zip(points, points[1:]))


def resample(points: Sequence[Point], count: int, aspect: float) -> list[Point]:
    """Uniform arc-length resampling, never index-based sampling."""
    if not points:
        return []
    compact = [points[0]]
    for point in points[1:]:
        if metric(point, compact[-1], aspect) > 0.00001:
            compact.append(point)
    if len(compact) == 1:
        return [compact[0]] * count
    total = polyline_length(compact, aspect)
    if total <= 0.00001:
        return [compact[0]] * count
    targets = [total * index / (count - 1) for index in range(count)]
    out: list[Point] = []
    segment = 0
    walked = 0.0
    for target in targets:
        while segment + 1 < len(compact):
            length = metric(compact[segment], compact[segment + 1], aspect)
            if walked + length >= target or length <= 0.00001:
                break
            walked += length
            segment += 1
        start, end = compact[segment], compact[min(segment + 1, len(compact) - 1)]
        length = metric(start, end, aspect)
        ratio = 0.0 if length <= 0.00001 else (target - walked) / length
        out.append((start[0] + (end[0] - start[0]) * ratio,
                    start[1] + (end[1] - start[1]) * ratio))
    out[0], out[-1] = compact[0], compact[-1]
    return out


def normalize_shape(points: Sequence[Point], aspect: float) -> list[Point]:
    """Translate and scale a trace for the SHARK2-style shape channel."""
    center_x = sum(point[0] for point in points) / len(points)
    center_y = sum(point[1] for point in points) / len(points)
    span_x = max(point[0] for point in points) - min(point[0] for point in points)
    span_y = (max(point[1] for point in points) - min(point[1] for point in points)) / aspect
    scale = max(span_x, span_y, 0.035)
    return [((point[0] - center_x) / scale, ((point[1] - center_y) / aspect) / scale)
            for point in points]


def mean_key_span(geometry: Geometry, aspect: float) -> float:
    """Live key-size estimate for anchor and path-length tolerances."""
    distances: list[float] = []
    keys = list(geometry.values())
    for point in keys:
        nearest = min((metric(point, other, aspect) for other in keys if other != point), default=0.0)
        if nearest:
            distances.append(nearest)
    return sum(distances) / len(distances) if distances else 0.08


def project(word: str, geometry: Geometry) -> list[str] | None:
    """Map dictionary text to available key centres without guessing layout."""
    labels: list[str] = []
    for char in word.lower().translate(ACCENT_HOST):
        if char not in geometry:
            return None
        labels.append(char)
    return labels if len(labels) >= 2 else None


def collapsed(labels: Sequence[str]) -> list[str]:
    out: list[str] = []
    for label in labels:
        if not out or label != out[-1]:
            out.append(label)
    return out


def looped_template(labels: Sequence[str], geometry: Geometry, span: float) -> list[Point]:
    """Model repeated letters as a small loop; plain and looped variants compete."""
    radius = max(span * 0.18, 0.012)
    points: list[Point] = []
    index = 0
    while index < len(labels):
        label = labels[index]
        point = geometry[label]
        run = 1
        while index + run < len(labels) and labels[index + run] == label:
            run += 1
        points.append(point)
        if run > 1:
            x, y = point
            points.extend([(x - radius, y - radius), (x + radius, y - radius),
                           (x + radius, y + radius), (x - radius, y + radius), point])
        index += run
    if len(points) == 1:  # defensive: a one-key layout still has finite geometry
        x, y = points[0]
        points.extend([(x - radius, y - radius), (x + radius, y - radius),
                       (x + radius, y + radius), (x, y)])
    return points


def ideal_variants(labels: Sequence[str], geometry: Geometry, span: float,
                   aspect: float) -> list[list[Point]]:
    plain_labels = collapsed(labels)
    plain = [geometry[label] for label in plain_labels]
    variants = [resample(plain, SAMPLES, aspect)]
    if len(plain_labels) != len(labels):
        variants.append(resample(looped_template(labels, geometry, span), SAMPLES, aspect))
    return variants


def corner_count(points: Sequence[Point], aspect: float) -> int:
    count = 0
    for previous, current, following in zip(points, points[1:], points[2:]):
        ax, ay = current[0] - previous[0], (current[1] - previous[1]) / aspect
        bx, by = following[0] - current[0], (following[1] - current[1]) / aspect
        norm = math.hypot(ax, ay) * math.hypot(bx, by)
        if norm and (ax * bx + ay * by) / norm < 0.55:
            count += 1
    return count


def nearest_labels(points: Sequence[Point], geometry: Geometry, aspect: float) -> list[str]:
    sequence: list[str] = []
    for point in points:
        label = min(geometry, key=lambda item: metric(point, geometry[item], aspect))
        if not sequence or sequence[-1] != label:
            sequence.append(label)
    return sequence


def lcs(left: Sequence[str], right: Sequence[str]) -> int:
    row = [0] * (len(right) + 1)
    for a in left:
        previous = 0
        for index, b in enumerate(right, 1):
            old = row[index]
            row[index] = previous + 1 if a == b else max(row[index], row[index - 1])
            previous = old
    return row[-1]


def parse_gesture(payload: object) -> tuple[list[Point], Geometry, float] | None:
    """Validate the non-executable, bounded geometry message from wvkbd."""
    if not isinstance(payload, dict) or payload.get("v") != 1:
        return None
    width, height = payload.get("w"), payload.get("h")
    raw_points, raw_keys = payload.get("p"), payload.get("k")
    if (not isinstance(width, int) or not isinstance(height, int) or
            not 1 <= width <= 32767 or not 1 <= height <= 32767 or
            not isinstance(raw_points, list) or not 3 <= len(raw_points) <= 40 or
            not isinstance(raw_keys, list) or not 2 <= len(raw_keys) <= 32):
        return None
    points: list[Point] = []
    last_time = -1
    for item in raw_points:
        if (not isinstance(item, list) or len(item) != 3 or
                not all(isinstance(value, int) for value in item)):
            return None
        x, y, time = item
        if not 0 <= x <= 1000 or not 0 <= y <= 1000 or not 0 <= time <= 30000 or time < last_time:
            return None
        points.append((x / 1000.0, y / 1000.0))
        last_time = time
    geometry: Geometry = {}
    for item in raw_keys:
        if (not isinstance(item, list) or len(item) != 3 or not isinstance(item[0], str) or
                len(item[0]) != 1 or item[0] not in "abcdefghijklmnopqrstuvwxyz" or
                not isinstance(item[1], int) or not isinstance(item[2], int) or
                not 0 <= item[1] <= 1000 or not 0 <= item[2] <= 1000):
            return None
        geometry[item[0]] = (item[1] / 1000.0, item[2] / 1000.0)
    if len(geometry) < 2:
        return None
    return points, geometry, width / height


def score_word(trace: Sequence[Point], observed: Sequence[str], labels: Sequence[str],
               geometry: Geometry, aspect: float, span: float) -> float:
    """Lower is better. Shape/location preserve the real point order."""
    trace_resampled = resample(trace, SAMPLES, aspect)
    trace_shape = normalize_shape(trace_resampled, aspect)
    trace_length = polyline_length(trace_resampled, aspect)
    trace_corners = corner_count(trace_resampled, aspect)
    best = float("inf")
    for template in ideal_variants(labels, geometry, span, aspect):
        template_shape = normalize_shape(template, aspect)
        shape = sum(metric(a, b, 1.0) for a, b in zip(trace_shape, template_shape)) / SAMPLES
        # Endpoints carry more weight: users normally land there much more
        # accurately than in the middle of a fast gesture.
        weight_total = 0.0
        location = 0.0
        for index, (a, b) in enumerate(zip(trace_resampled, template)):
            weight = 1.0 + abs(index - (SAMPLES - 1) / 2) / ((SAMPLES - 1) / 2)
            location += weight * metric(a, b, aspect)
            weight_total += weight
        location = location / weight_total / max(span, 0.001)
        template_length = polyline_length(template, aspect)
        length_penalty = abs(math.log(max(trace_length, 0.001) / max(template_length, 0.001)))
        template_corners = corner_count(template, aspect)
        corners = min(abs(trace_corners - template_corners), 8) * 0.025
        coverage = lcs(observed, collapsed(labels)) / max(len(observed), len(collapsed(labels)), 1)
        order = (1.0 - coverage) * 0.20
        best = min(best, shape * 1.05 + location * 0.80 + length_penalty * 0.30 + corners + order)
    return best


def decode_gesture(payload: object, language: str = "auto",
                   wordlist: Iterable[str] | None = None) -> str | None:
    parsed = parse_gesture(payload)
    if parsed is None:
        return None
    trace, geometry, aspect = parsed
    if polyline_length(trace, aspect) < 0.75 * mean_key_span(geometry, aspect):
        return None
    span = mean_key_span(geometry, aspect)
    start, end = trace[0], trace[-1]
    # Strong endpoint pruning: only dictionary words whose first and last
    # centres are in the two-nearest endpoint neighbourhoods are scored.
    ordered_start = sorted(geometry, key=lambda label: metric(start, geometry[label], aspect))[:2]
    ordered_end = sorted(geometry, key=lambda label: metric(end, geometry[label], aspect))[:2]
    observed = nearest_labels(trace, geometry, aspect)
    if wordlist is None:
        words = tuple(word for lang in languages(language) for word in load_words(lang))
    else:
        words = tuple(wordlist)

    best_word: str | None = None
    best_score = float("inf")
    # Hard caps keep even an unusually broad local hunspell list bounded. The
    # endpoint filter normally leaves hundreds, not tens of thousands.
    considered = 0
    for word in words:
        labels = project(word, geometry)
        if not labels or labels[0] not in ordered_start or labels[-1] not in ordered_end:
            continue
        considered += 1
        if considered > 3500:
            break
        score = score_word(trace, observed, labels, geometry, aspect, span)
        if score < best_score - 0.000001 or (abs(score - best_score) <= 0.000001 and (best_word is None or word < best_word)):
            best_word, best_score = word, score
    # Reject a poor geometry match rather than inserting a plausible-but-wrong
    # word. The threshold is intentionally loose enough for ordinary jitter.
    return best_word if best_word is not None and best_score <= 1.15 else None


def qwerty_payload(word: str, jitter: Sequence[Point] | None = None) -> dict:
    """Small deterministic debug/test generator using a staggered QWERTY grid."""
    rows = (("qwertyuiop", 0.0), ("asdfghjkl", 0.5), ("zxcvbnm", 1.0))
    geometry = {
        char: [char, int((offset + column + 0.5) / 10.0 * 1000), int((row + 0.5) / 3.0 * 1000)]
        for row, (letters, offset) in enumerate(rows)
        for column, char in enumerate(letters)
    }
    keys = {item[0]: (item[1] / 1000.0, item[2] / 1000.0) for item in geometry.values()}
    labels = project(word, keys)
    if not labels:
        raise ValueError("word is not qwerty-projectable")
    path = [keys[label] for label in labels]
    if jitter:
        path = [(x + dx, y + dy) for (x, y), (dx, dy) in zip(path, jitter)]
    samples = resample(path, 16, 1000 / 360)
    return {
        "v": 1, "w": 1000, "h": 360,
        "p": [[round(x * 1000), round(y * 1000), index * 18] for index, (x, y) in enumerate(samples)],
        "k": list(geometry.values()),
    }


def insert(word: str) -> None:
    """Use argv only; dictionary text is never interpreted by a shell."""
    try:
        subprocess.run(["wtype", "--", word], check=False, timeout=2,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        pass


def self_test() -> bool:
    words = ("hello", "keyboard", "hallo", "tastatur", "help", "held")
    cases = (("hello", "hello"), ("keyboard", "keyboard"),
             ("hallo", "hallo"), ("tastatur", "tastatur"))
    for source, expected in cases:
        if decode_gesture(qwerty_payload(source), wordlist=words) != expected:
            return False
    noisy = qwerty_payload("keyboard", [(0.006, -0.008)] * len("keyboard"))
    return decode_gesture(noisy, wordlist=words) == "keyboard"


def main() -> int:
    parser = argparse.ArgumentParser(description="TabletMode geometry glide decoder")
    parser.add_argument("--language", choices=("auto", "de", "en"), default="auto")
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--debug", metavar="GESTURE_JSON", type=Path,
                        help="decode one saved bounded gesture and print it; never types")
    args = parser.parse_args()
    if args.validate:
        return 0 if shutil.which("wtype") and LEXICON.is_file() else 1
    if args.self_test:
        return 0 if self_test() else 1
    if args.debug is not None:
        try:
            raw = args.debug.read_text(encoding="utf-8")
            payload = json.loads(raw) if len(raw) <= MAX_MESSAGE else None
        except (OSError, ValueError):
            payload = None
        result = decode_gesture(payload, args.language)
        print(result or "")
        return 0 if result else 1
    for raw in sys.stdin:
        if len(raw) > MAX_MESSAGE:
            continue
        try:
            payload = json.loads(raw)
        except ValueError:
            continue
        word = decode_gesture(payload, args.language)
        if word:
            insert(word)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
