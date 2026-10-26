#!/usr/bin/env python3
"""Tests for the media corpus tooling: the JSON Schema subset validator and the corpus validator.

Each test builds a tiny corpus in a temporary directory, so none of them depends on the real corpus.
"""
import hashlib
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "corpus"))
import jsonschema_lite  # noqa: E402
import filename_rules  # noqa: E402
import validate  # noqa: E402

REAL_ROOT = os.path.join(REPO, "testdata", "corpus")
JPEG = b"\xff\xd8\xff\xd9"
PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 8


def sha(data):
    return hashlib.sha256(data).hexdigest()


def golden(path, data, **over):
    return {
        "schema_version": 1, "path": path, "size": len(data), "sha256": sha(data), "origin": "synthetic",
        "format": "jpeg", "quirks": [],
        "media": {"container": "jpeg", "mime": "image/jpeg", "kind": "image", "support": "supported"},
        "metadata": {"width": 1, "height": 1},
        "filename": {"matches": []},
        "capture_time": {"claims": [], "resolved": None},
        **over,
    }


def resolved(**over):
    return {"local": "2019-05-09T15:47:33", "utc": "2019-05-09T13:47:33Z", "offset": "+02:00",
            "tz_source": "explicit_offset", "precision": "s", "bound": "exact",
            "source": "exif_dto_with_offset", "confidence_band": "high", "flags": [], **over}


def claim(**over):
    return {"source": "exif_dto_with_offset", "kind": "local", "value": "2019-05-09T15:47:33",
            "offset": "+02:00", "precision": "s", "event": "capture", **over}


class Corpus:
    """A throwaway corpus root: add files with their golden records, then inspect validate's complaints."""

    def __init__(self):
        self.root = tempfile.mkdtemp()
        shutil.copy(os.path.join(REAL_ROOT, "golden.schema.json"), self.root)

    def close(self):
        shutil.rmtree(self.root)

    def write(self, kind, path, content):
        full = os.path.join(self.root, kind, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as handle:
            handle.write(content if isinstance(content, bytes) else content.encode())

    def add(self, path, data=JPEG, **over):
        record = golden(path, data, **over)
        self.write("files", path, data)
        self.write("golden", path + ".json", json.dumps(record))
        return record

    def errors(self):
        return validate.check_tree(self.root)

    def coverage(self, min_entries=0):
        return validate.check_coverage(self.root, min_entries)


class CorpusCase(unittest.TestCase):
    def setUp(self):
        self.corpus = Corpus()
        self.addCleanup(self.corpus.close)

    def assertComplaint(self, word, errors=None):
        errors = self.corpus.errors() if errors is None else errors
        self.assertTrue(any(word in error for error in errors), f"no error mentions {word!r}: {errors}")


class SchemaSubset(unittest.TestCase):
    def check(self, schema, value):
        return jsonschema_lite.validate(value, schema)

    def test_schema_keywords(self):
        for schema, accepted, rejected in [
            ({"type": "integer"}, [3], [3.5, True]),
            ({"type": ["string", "null"]}, [None], []),
            ({"type": "number"}, [], ["1"]),
            ({"enum": ["a", "b"]}, [], ["c"]),
            ({"const": 1}, [], [2]),
            ({"type": "string", "pattern": "^a+$"}, ["aa"], ["ab"]),
            ({"type": "integer", "minimum": 1}, [], [0]),
            ({"type": "integer", "maximum": 8}, [], [9]),
            ({"type": "array", "minItems": 1}, [], [[]]),
            ({"type": "object", "required": ["a"], "additionalProperties": False,
              "properties": {"a": {"type": "integer"}}}, [{"a": 1}], [{}, {"a": 1, "b": 2}, {"a": "x"}]),
            ({"$defs": {"n": {"type": "integer"}}, "type": "array", "items": {"$ref": "#/$defs/n"},
              "uniqueItems": True}, [[1, 2]], [[1, "x"], [1, 1]]),
        ]:
            for value in accepted:
                with self.subTest(schema=schema, accepted=value):
                    self.assertEqual(self.check(schema, value), [])
            for value in rejected:
                with self.subTest(schema=schema, rejected=value):
                    self.assertTrue(self.check(schema, value))

    def test_errors_name_the_path(self):
        schema = {"type": "object", "properties": {"a": {"type": "array", "items": {"type": "integer"}}}}
        self.assertIn("a[1]", self.check(schema, {"a": [1, "x"]})[0])

    def test_unsupported_keyword_is_an_error_not_a_pass(self):
        with self.assertRaises(ValueError):
            self.check({"anyOf": [{"type": "string"}]}, 1)


class TreeChecks(CorpusCase):
    def test_a_valid_entry_passes(self):
        self.corpus.add("a/photo.jpg")
        self.assertEqual(self.corpus.errors(), [])

    def test_schema_violations_name_the_file(self):
        record = golden("p.jpg", JPEG)
        del record["sha256"]
        self.corpus.write("files", "p.jpg", JPEG)
        self.corpus.write("golden", "p.jpg.json", json.dumps(record))
        self.assertComplaint("sha256")
        self.assertComplaint("p.jpg.json")

    def test_unknown_property_and_bad_enum_are_rejected(self):
        self.corpus.add("p.jpg", format="jpg", colour="red")
        errors = self.corpus.errors()
        self.assertComplaint("colour", errors)
        self.assertComplaint("format", errors)

    def test_size_and_hash_must_match_the_file(self):
        self.corpus.add("p.jpg", size=99)
        self.assertComplaint("size")
        self.corpus.add("q.jpg", sha256="0" * 64)
        self.assertComplaint("sha256")

    def test_every_file_needs_a_golden_and_every_golden_a_file(self):
        self.corpus.write("files", "orphan.jpg", JPEG)
        self.assertComplaint("orphan.jpg")
        self.corpus.write("golden", "ghost.jpg.json", json.dumps(golden("ghost.jpg", JPEG)))
        self.assertComplaint("ghost.jpg")

    def test_golden_path_must_mirror_its_location(self):
        self.corpus.write("files", "p.jpg", JPEG)
        self.corpus.write("golden", "p.jpg.json", json.dumps(golden("other.jpg", JPEG)))
        self.assertComplaint("path")

    def test_sidecars_are_checked_and_not_orphans(self):
        side = b'{"title": "p.jpg"}\n'
        self.corpus.add("p.jpg", sidecars=[{"path": "p.jpg.json", "kind": "takeout_json", "sha256": sha(side)}])
        self.corpus.write("files", "p.jpg.json", side)
        self.assertEqual(self.corpus.errors(), [])
        self.corpus.write("files", "p.jpg.json", b"changed\n")
        self.assertComplaint("p.jpg.json")

    def test_names_must_be_portable(self):
        self.corpus.add("a/2018-04-12 19:24:49.jpg")
        self.assertComplaint("portable")

    def test_names_must_not_collide_on_case_insensitive_disks(self):
        self.corpus.add("IMG_1.JPG")
        self.corpus.add("img_1.jpg")
        self.assertComplaint("case")

    def test_container_must_match_the_magic_bytes(self):
        self.corpus.add("p.jpg", PNG)
        self.assertComplaint("container")

    def test_isobmff_brand_must_match_ftyp(self):
        heic = b"\0\0\0\x18ftypheic\0\0\0\0mif1heic"
        media = {"container": "isobmff", "brand": "avif", "mime": "image/heic", "kind": "image",
                 "support": "supported"}
        self.corpus.add("p.heic", heic, format="heic", media=media)
        self.assertComplaint("brand")


class CaptureTimeChecks(CorpusCase):
    def time(self, claims, resolved_record):
        self.corpus.add("p.jpg", capture_time={"claims": claims, "resolved": resolved_record})
        return self.corpus.errors()

    def test_consistent_resolution_passes(self):
        self.assertEqual(self.time([claim()], resolved()), [])

    def test_inconsistent_resolutions_are_rejected(self):
        for word, fields in [
            ("utc", {"utc": "2019-05-09T14:47:33Z"}),
            ("precision", {"precision": "day"}),
            ("source", {"source": "exif_dto_no_offset"}),
            ("local", {"local": None, "utc": None}),
        ]:
            with self.subTest(fields=fields):
                self.assertComplaint(word, self.time([claim()], resolved(**fields)))

    def test_utc_claims_end_in_z_and_local_claims_do_not(self):
        self.assertComplaint("kind", self.time([claim(kind="utc")], resolved()))
        self.assertComplaint("kind", self.time([claim(value="2019-05-09T13:47:33Z")], resolved()))


class FilenameChecks(CorpusCase):
    def matches(self, name, rules, **over):
        self.corpus.add(name, filename={"matches": rules}, **over)
        return self.corpus.errors()

    def test_matches_must_list_every_registry_rule_that_matches(self):
        self.assertEqual(self.matches("PXL_20231026_210642603.jpg", ["F03"]), [])
        self.assertComplaint("F03", self.matches("PXL_20231026_210642604.jpg", []))

    def test_matches_must_not_list_a_rule_that_does_not_match(self):
        self.assertComplaint("F03", self.matches("IMG_1234.jpg", ["F03"]))

    def test_original_name_is_what_the_rules_see(self):
        errors = self.matches("takeout/IMG_trunc.jpg", ["F01"], original_name="IMG_20190509_154733.jpg")
        self.assertNotIn("F01", " ".join(errors))


class CoverageChecks(CorpusCase):
    def test_unused_vocabulary_is_reported(self):
        self.corpus.add("p.jpg")
        errors = self.corpus.coverage()
        self.assertComplaint("format:png", errors)
        self.assertComplaint("quirk:live_photo", errors)
        self.assertComplaint("vendor:apple", errors)
        self.assertComplaint("rule:F01", errors)

    def test_used_vocabulary_is_not_reported(self):
        self.corpus.add("p.jpg", quirks=["progressive"], vendor="apple")
        errors = self.corpus.coverage()
        self.assertFalse(any("format:jpeg" in e or "quirk:progressive" in e or "vendor:apple" in e for e in errors))

    def test_minimum_number_of_entries(self):
        self.corpus.add("p.jpg")
        self.assertComplaint("entries", self.corpus.coverage(min_entries=2))

    def test_vocabulary_comes_from_the_schema(self):
        path = os.path.join(self.corpus.root, "golden.schema.json")
        with open(path) as handle:
            schema = json.load(handle)
        schema["$defs"]["quirk"]["enum"].append("brand_new_quirk")
        with open(path, "w") as handle:
            json.dump(schema, handle)
        self.assertComplaint("quirk:brand_new_quirk", self.corpus.coverage())


class RegistryExamples(unittest.TestCase):
    """Names printed in the research registry must hit the rule they illustrate."""

    EXAMPLES = {
        "F01": ["IMG_20190509_154733.jpg", "VID_20220107_113306.mp4", "IMG_20190509_154733-edited.jpg"],
        "F02": ["MVIMG_20190215_193501.jpg", "PANO_20190101_120000.jpg"],
        "F03": ["PXL_20231026_210642603.jpg", "PXL_20230330_184138390.MOTION-01.COVER.jpg"],
        "F04": ["00015IMG_00015_BURST20171111030039_COVER.jpg", "00001IMG_00001_BURST1723801037429_COVER.jpg"],
        "F05": ["20231207_101605.jpg", "20231207_101605_001.jpg", "20231207_101605(0).jpg"],
        "F06": ["IMG_20231014_183246_BURST001_COVER.jpg"],
        "F07": ["IMG20231231123456.jpg", "VID20231231123456.mp4"],
        "F08": ["IMG_20231231_123456789.jpg"],
        "F09": ["DSC_0002_BURST20230115120000123_COVER.JPG"],
        "F10": ["IMG_1234.HEIC", "IMG_E1234.JPG", "IMG_O1234.AAE"],
        "F11": ["WIN_20231231_12_34_56_Pro.jpg"],
        "F12": ["Screenshot_20201215-090626.png"],
        "F13": ["Screenshot_20231027_123303_Facebook.jpg", "Screenshot_20190919-053857_Camera-edited.jpg"],
        "F14": ["Screenshot_2019-04-16-11-19-37-232_com.google.android.youtube.jpg"],
        "F15": ["screen-20240131-142530.mp4"],
        "F16": ["Screen_Recording_20231231-123456_Chrome.mp4"],
        "F17": ["Screenrecorder-2023-12-31-12-34-56-789.mp4"],
        "F18": ["RPReplay_Final1612345678.MP4"],
        "F19": ["Screenshot 2019-05-21 at 10.45.52.png", "Screen Shot 2017-05-21 at 10.45.52 AM.png"],
        "F20": ["Screen Recording 2023-12-31 at 12.34.56.mov"],
        "F21": ["Screenshot 2023-12-31 123456.png"],
        "F22": ["Screenshot From 2023-12-31 12-34-56.png", "Screencast From 2023-12-31 12-34-56.webm"],
        "F23": ["Screenshot_20231231_123456.png"],
        "F24": ["2023-12-31_12-34.png", "2023-12-31_12-34_1.png"],
        "F25": ["IMG-20191120-WA0001.jpg", "VID-20191120-WA0003.mp4"],
        "F26": ["WhatsApp Image 2023-05-14 at 10.22.31 AM.jpeg"],
        "F27": ["IMG_20231231_123456_789.jpg"],
        "F28": ["photo_2023-12-31_12-34-56.jpg", "video_2023-12-31_12-34-56 (2).mp4"],
        "F29": ["photo_1@31-12-2023_12-34-56.jpg"],
        "F30": ["signal-2026-01-30-09-57-18-123.jpg", "signal-2020-10-26-163832.jpg"],
        "F31": ["IMG-0a1b2c3d4e5f60718293-V.jpg"],
        "F32": ["mmexport1703999999999.jpg", "wx_camera_1703999999999.mp4"],
        "F33": ["KakaoTalk_20231231_123456789.jpg", "KakaoTalk_Photo_2023-12-31-12-34-56.jpeg"],
        "F35": ["FB_IMG_1703999999999.jpg"],
        "F38": ["DJI_20240225080944_0032_D.JPG"],
        "F39": ["DJI_0005.JPG"],
        "F40": ["dji_fly_20240225_080944_0032_1708850908777_photo.jpg"],
        "F41": ["GOPR0001.JPG", "GH010001.MP4", "GX010001.MP4"],
        "F42": ["VID_20201031_094049_00_188.insv", "LRV_20240415_213145_01_035.lrv"],
        "F43": ["IMG_0001.JPG", "_MG_0001.CR2", "DSC_0001.NEF", "DSCN0001.JPG", "DSCF0001.RAF", "IMGP0001.JPG"],
        "F44": ["PC310001.JPG"],
        "F47": ["2023-12-31 12.34.56.jpg", "2023-12-31 12.34.56-1.jpg"],
        "F48": ["20231231_123456000_iOS.jpg"],
        "F49": ["Photo 22-04-06 15-21-03 2160.jpg"],
        "F51": ["Photo on 31-12-2023 at 12.34.jpg", "Photo on 12-31-23 at 12.34 PM.jpg"],
        "F52": ["2023-12-31_12-34-56.jpg", "2016_01_30_11_49_15.mp4", "20231231T123456.jpg"],
        "F53": ["201801261147521000.jpg"],
        "F54": ["2019-07-23.jpg", "IMG-2019-07-23.jpg"],
        "F55": ["1703999999.jpg", "image_1703999999999.png"],
    }

    def test_every_example_matches_its_rule(self):
        for rule, names in self.EXAMPLES.items():
            for name in names:
                self.assertIn(rule, filename_rules.matching(name, name), f"{rule} should match {name}")

    def test_path_rule_sees_the_folder(self):
        path = "media/posts/202312/17912345678901234.jpg"
        self.assertIn("F36", filename_rules.matching(path.rsplit("/", 1)[1], path))

    def test_dateless_or_ambiguous_names_match_no_date_rule(self):
        for name in ("IMG_1234.jpg", "31.12.2023.jpg", "12-31-2023.jpg", "DJI_0005.JPG"):
            self.assertFalse({"F01", "F52", "F54", "F55"} & set(filename_rules.matching(name, name)), name)

    def test_the_registry_lists_rules_f01_to_f56(self):
        self.assertEqual(list(filename_rules.RULES), [f"F{n:02d}" for n in range(1, 57)])


if __name__ == "__main__":
    unittest.main()
