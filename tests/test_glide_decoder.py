"""Synthetic geometry checks for the local TabletMode glide matcher."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


DECODER = Path(__file__).resolve().parents[1] / "scripts" / "glide-decoder.py"
SPEC = importlib.util.spec_from_file_location("tabletmode_glide", DECODER)
assert SPEC and SPEC.loader
glide = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(glide)


class GeometricGlideTests(unittest.TestCase):
    words = ("hello", "keyboard", "hallo", "tastatur", "help", "held")

    def decode(self, word: str) -> str | None:
        return glide.decode_gesture(glide.qwerty_payload(word), wordlist=self.words)

    def test_ideal_english_paths(self) -> None:
        self.assertEqual(self.decode("hello"), "hello")
        self.assertEqual(self.decode("keyboard"), "keyboard")

    def test_ideal_german_paths(self) -> None:
        self.assertEqual(self.decode("hallo"), "hallo")
        self.assertEqual(self.decode("tastatur"), "tastatur")

    def test_noisy_path_and_rejection(self) -> None:
        noisy = glide.qwerty_payload("keyboard", [(0.006, -0.008)] * len("keyboard"))
        self.assertEqual(glide.decode_gesture(noisy, wordlist=self.words), "keyboard")
        payload = glide.qwerty_payload("hello")
        payload["p"] = [[80, 80, 0], [81, 80, 15], [82, 80, 30]]
        self.assertIsNone(glide.decode_gesture(payload, wordlist=self.words))


if __name__ == "__main__":
    unittest.main()
