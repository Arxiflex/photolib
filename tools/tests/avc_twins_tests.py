#!/usr/bin/env python3
"""The AVC twins of the HEIC corpus files (tools/corpus/avc_twins.py): the I_PCM encoder's streams decode in FFmpeg
to the colours the generator says, whatever the matrix FFmpeg picks (within 8/255), and twins.json is consistent."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/corpus"))
import avc_twins


def ffmpeg():
    """The pinned LGPL FFmpeg; on a machine it is not pinned for, the one on PATH (it only decodes AVC here)."""
    pinned = subprocess.run(["bash", ROOT / "tools/video/ffmpeg.sh"], check=False, capture_output=True, text=True)
    return Path(pinned.stdout.strip()) / "ffmpeg" if pinned.returncode == 0 else "ffmpeg"


class Twins(unittest.TestCase):
    def test_a_stream_decodes_to_the_blocks_it_was_written_from(self):
        width, height = 64, 48
        colour = avc_twins.block_colour(width // 16, height // 16)
        sps, pps = avc_twins.parameter_sets(width, height)
        stream = b"\0\0\0\1" + sps + b"\0\0\0\1" + pps + b"\0\0\0\1" + avc_twins.idr(width, height, colour)[4:]
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "t.h264"
            path.write_bytes(stream)
            run = subprocess.run([ffmpeg(), "-v", "error", "-i", path, "-frames:v", "1", "-f", "rawvideo",
                                  "-pix_fmt", "rgb24", "-"], capture_output=True, check=False)
        self.assertEqual(run.stderr, b"")
        self.assertEqual(len(run.stdout), width * height * 3)
        for by in range(height // 16):
            for bx in range(width // 16):
                at = ((by * 16 + 8) * width + bx * 16 + 8) * 3
                for got, want in zip(run.stdout[at:at + 3], colour(bx, by)):
                    self.assertLessEqual(abs(got - want), 8, (bx, by))

    def test_the_listing_agrees_with_the_files(self):
        out = avc_twins.render()
        listing = json.loads(out["twins/heif-avc/twins.json"])
        self.assertEqual(sorted(listing), sorted(Path(p).name for p in out if p.endswith(".heic")))
        for name, twin in listing.items():
            self.assertEqual(twin["bytes"], len(out[f"twins/heif-avc/{name}"]))
            self.assertGreaterEqual(len(twin["probes"]), 8, name)
            self.assertGreaterEqual(len(twin["thumb"]["probes"]), 4, name)
        # A rotation by a quarter turn swaps the shown size; a clap shows less of the canvas.
        self.assertEqual(listing["single.heic"]["shown"], [192, 256])
        self.assertEqual(listing["clap.heic"]["shown"], [224, 160])
        self.assertEqual(listing["all.heic"]["shown"], [160, 224])

    def test_probes_see_the_transforms(self):
        # The pixel at the top left of a picture turned by half a turn is the canvas' bottom right.
        self.assertEqual(avc_twins.source((256, 192), None, 2, None, 0, 0), (255, 191))
        self.assertEqual(avc_twins.source((256, 192), None, None, 0, 0, 0), (0, 191))
        self.assertEqual(avc_twins.source((256, 192), None, None, 1, 0, 0), (255, 0))
        self.assertEqual(avc_twins.source((256, 192), (224, 160, -8, 8), None, None, 0, 0), (8, 24))


if __name__ == "__main__":
    unittest.main()
