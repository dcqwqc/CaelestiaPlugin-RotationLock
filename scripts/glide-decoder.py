#!/usr/bin/env python3
"""Decode TabletMode wvkbd glide paths and inject one predicted word.

The process only receives key labels from an inherited pipe.  It never reads,
logs, evaluates, or stores clipboard/focused-client content.  Keeping decoding
out of the keyboard process makes input rendering independent from dictionary
size and lets wvkbd stay responsive during a large dictionary load.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEXICON = ROOT / "data" / "glide-lexicon.txt"
WORD = re.compile(r"^[a-zäöüß]{2,32}$", re.IGNORECASE)
QWERTY = {
    char: (x, y)
    for y, row in enumerate(("qwertyuiop", "asdfghjkl", "zxcvbnm"))
    for x, char in enumerate(row)
}


def compress(path: str) -> str:
    out: list[str] = []
    for char in path.lower():
        if char.isalpha() and (not out or char != out[-1]):
            out.append(char)
    return "".join(out)


def dictionary_files(language: str) -> list[Path]:
    names = {
        "de": ("de_DE.dic", "de_DE_frami.dic", "de_CH.dic"),
        "en": ("en_US.dic", "en_GB.dic", "en.dic"),
    }[language]
    roots = (Path("/usr/share/hunspell"), Path("/usr/share/myspell/dicts"), Path("/usr/share/myspell"))
    return [root / name for root in roots for name in names if (root / name).is_file()]


@lru_cache(maxsize=2)
def load_words(language: str) -> tuple[str, ...]:
    words: set[str] = set()
    # Hunspell's first line is a count; affix flags are separated by '/'.
    # Bounded loading avoids a very large local dictionary degrading a swipe.
    for filename in dictionary_files(language):
        try:
            for raw in filename.open(encoding="utf-8", errors="ignore"):
                word = raw.strip().split("/", 1)[0].lower()
                if WORD.fullmatch(word):
                    words.add(word)
                if len(words) >= 70000:
                    break
        except OSError:
            continue
        if len(words) >= 70000:
            break
    if not words:
        try:
            for raw in LEXICON.open(encoding="utf-8"):
                tag, _, word = raw.partition("\t")
                if tag in (language, "both") and WORD.fullmatch(word.strip()):
                    words.add(word.strip().lower())
        except OSError:
            pass
    return tuple(sorted(words))


def lcs(left: str, right: str) -> int:
    row = [0] * (len(right) + 1)
    for a in left:
        previous = 0
        for index, b in enumerate(right, 1):
            old = row[index]
            if a == b:
                row[index] = previous + 1
            else:
                row[index] = max(row[index], row[index - 1])
            previous = old
    return row[-1]


def edit_distance(left: str, right: str) -> int:
    row = list(range(len(right) + 1))
    for i, a in enumerate(left, 1):
        next_row = [i]
        for j, b in enumerate(right, 1):
            next_row.append(min(next_row[-1] + 1, row[j] + 1, row[j - 1] + (a != b)))
        row = next_row
    return row[-1]


def shape_distance(path: str, word: str) -> float:
    """Compare resampled QWERTY key-centre traces, preserving direction."""
    a = [QWERTY.get(char) for char in path]
    b = [QWERTY.get(char) for char in word]
    if not a or not b or None in a or None in b:
        return 1.0
    steps = max(len(a), len(b), 2)
    total = 0.0
    for i in range(steps):
        pa = a[round(i * (len(a) - 1) / (steps - 1))]
        pb = b[round(i * (len(b) - 1) / (steps - 1))]
        assert pa is not None and pb is not None
        total += ((pa[0] - pb[0]) ** 2 + (pa[1] - pb[1]) ** 2) ** 0.5
    return total / steps


def languages(choice: str) -> tuple[str, ...]:
    return ("de", "en") if choice == "auto" else (choice,)


def predict(path: str, language: str) -> str | None:
    path = compress(path)
    if len(path) < 2:
        return None
    candidates: list[str] = []
    for lang in languages(language):
        candidates.extend(load_words(lang))
    # First and final letters are hard constraints.  The middle uses ordered
    # coverage, edit distance, and the physical keyboard shape for ranking.
    possible = [word for word in candidates if word[0] == path[0] and word[-1] == path[-1]]
    if not possible:
        return None

    def score(word: str) -> tuple[float, str]:
        coverage = lcs(path, word) / max(len(path), 1)
        edit = edit_distance(path, word) / max(len(path), len(word))
        shape = shape_distance(path, word) / 10.0
        length = abs(len(path) - len(word)) / max(len(path), len(word))
        return (edit * 1.25 + shape * 0.75 + length * 0.30 - coverage * 0.90, word)

    winner = min(possible, key=score)
    # Reject weak matches rather than inserting an unrelated word.
    return winner if score(winner)[0] < 1.05 else None


def insert(word: str) -> None:
    # argv, never a shell: dictionary text cannot become a command.
    try:
        subprocess.run(["wtype", word], check=False, timeout=2,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        pass


def main() -> int:
    parser = argparse.ArgumentParser(description="TabletMode glide decoder")
    parser.add_argument("--language", choices=("auto", "de", "en"), default="auto")
    parser.add_argument("--validate", action="store_true")
    args = parser.parse_args()
    if args.validate:
        return 0 if shutil.which("wtype") and LEXICON.is_file() else 1
    for raw in sys.stdin:
        # wvkbd emits ASCII a-z path labels only.  Limit work per gesture.
        path = raw.strip().lower()[:96]
        if re.fullmatch(r"[a-z]+", path):
            word = predict(path, args.language)
            if word:
                insert(word)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
