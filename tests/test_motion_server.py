from __future__ import annotations

import importlib.util
import importlib.machinery
import os
import socket
import tempfile
import time
import unittest
from pathlib import Path


RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "yoga-tablet"
LOADER = importlib.machinery.SourceFileLoader("tabletmode_runtime", str(RUNTIME))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
runtime = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(runtime)


class FakeOsk:
    def __init__(self) -> None:
        self.frames: list[int] = []
        self.cancelled = 0

    def cancel_surface_animation(self) -> None:
        self.cancelled += 1

    def apply_external_vertical_frame(self, y: int) -> bool:
        self.frames.append(y)
        return True


class MotionServerTests(unittest.TestCase):
    def test_persistent_frame_channel_and_stale_sequence_rejection(self) -> None:
        fake = FakeOsk()
        with tempfile.TemporaryDirectory() as td:
            old_path = runtime.MOTION_SOCKET_PATH
            runtime.MOTION_SOCKET_PATH = Path(td) / "motion.sock"
            try:
                server = runtime.MotionServer(fake)
                server.start()
                self.assertEqual(os.stat(runtime.MOTION_SOCKET_PATH).st_mode & 0o777, 0o600)

                seq = server.begin()
                self.assertEqual(fake.cancelled, 1)
                client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                client.connect(str(runtime.MOTION_SOCKET_PATH))
                client.sendall(
                    (
                        f"y {seq} -410\n"
                        f"y {seq - 1} -999\n"
                        f"y {seq} -205\n"
                        f"y {seq} 0\n"
                        f"done {seq} 1\n"
                    ).encode()
                )
                self.assertTrue(server.wait(seq, 0.5))
                deadline = time.monotonic() + 0.3
                while len(fake.frames) < 3 and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertEqual(fake.frames, [-410, -205, 0])
                client.close()
                server.stop()
                self.assertFalse(runtime.MOTION_SOCKET_PATH.exists())
            finally:
                runtime.MOTION_SOCKET_PATH = old_path


if __name__ == "__main__":
    unittest.main()
