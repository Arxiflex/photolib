"""The filename date-pattern registry (research/tech/import-and-metadata.md, section 5.4), as Python regexes.

RULES maps a rule id to its RE2-compatible regex, or to None when the rule has no pattern of its own (F34, F37,
F45, F46, F50, F56). Rules in PATH_RULES match the whole relative path; the rest match the file name.
"""
import re

RULES = {
    "F01": r"^(?:IMG|VID)_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(?:[_.~(-]|$)",
    "F02": r"^(?:MVIMG|PANO|IMG)_(\d{8})_(\d{6})(\d{3})?(?:_BURST(\d{3}))?",
    "F03": r"^PXL_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(\d{3})",
    "F04": r"^\d+[A-Za-z]+_\d+_BURST(\d{13,17})(?:_COVER)?",
    "F05": r"^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(?:_(\d{3}))?(?:\(\d+\))?\.",
    "F06": r"^IMG_(\d{8})_(\d{6})_BURST(\d{3})(?:_COVER)?",
    "F07": r"^(?:IMG|VID)(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:_\d+)?\.",
    "F08": r"^(?:IMG|VID)_(\d{8})_(\d{6})(\d{3})(?:[_.]|$)",
    "F09": r"^DSC_(\d+)_BURST(\d{14})(\d{3})(?:_COVER)?",
    "F10": r"^IMG_([EO]?)(\d{4})\.",
    "F11": r"^WIN_(\d{8})_(\d{2})_(\d{2})_(\d{2})_Pro",
    "F12": r"^Screenshot_(\d{8})-(\d{6})(?:-display-\d+)?\.",
    "F13": r"^Screenshot_(\d{8})[-_](\d{6})(?:_([^.]+?))?(?:-edited)?\.",
    "F14": r"^Screenshot_(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})(?:-(\d{2,3}))?_([A-Za-z0-9_.]+)\.",
    "F15": r"^screen-(\d{8})-(\d{6})\.mp4$",
    "F16": r"^Screen_Recording_(\d{8})[-_](\d{6})(?:_([^.]+))?\.",
    "F17": r"^Screenrecorder-(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})(?:-(\d{3}))?",
    "F18": r"^RPReplay_Final(\d{10})\.",
    "F19": r"^(?:Screenshot|Screen Shot) (\d{4})-(\d{2})-(\d{2}) at (\d{1,2})\.(\d{2})\.(\d{2})(?: ?([AP]M))?(?: \(\d+\))?\.",
    "F20": r"^Screen Recording (\d{4})-(\d{2})-(\d{2}) at (\d{1,2})\.(\d{2})\.(\d{2})(?: ?([AP]M))?",
    "F21": r"^Screenshot (\d{4})-(\d{2})-(\d{2}) (\d{2})(\d{2})(\d{2})\.",
    "F22": r"^Screen(?:shot|cast) [Ff]rom (\d{4})-(\d{2})-(\d{2}) (\d{2})-(\d{2})-(\d{2})(?:-\d+)?\.",
    "F23": r"^Screenshot_(\d{8})_(\d{6})\.png$",
    "F24": r"^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})(?:_\d+)?\.png$",
    "F25": r"^(IMG|VID|AUD|PTT|STK|DOC)-(\d{4})(\d{2})(\d{2})-WA(\d+)",
    "F26": r"^WhatsApp (?:Image|Video|Audio) (\d{4})-(\d{2})-(\d{2}) at (\d{1,2})\.(\d{2})\.(\d{2})(?: ?([AP]M))?",
    "F27": r"^(?:IMG|VID)_(\d{8})_(\d{6})_(\d{3})\.(?i:jpg|jpeg|mp4)$",
    "F28": r"^([a-z]+)_(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})(?: \(\d+\))?\.",
    "F29": r"^(?:photo|video|file)_\d+@(\d{2})-(\d{2})-(\d{4})_(\d{2})-(\d{2})-(\d{2})",
    "F30": r"^signal-(\d{4})-(\d{2})-(\d{2})-(\d{2})-?(\d{2})-?(\d{2})(?:-(\d{3}))?",
    "F31": r"^(?:IMG|VID)-[0-9a-f]{16,}-V\.",
    "F32": r"^(?:mmexport|wx_camera_)(\d{13})\.",
    "F33": r"^KakaoTalk_(?:Photo_)?(\d{4})-?(\d{2})-?(\d{2})[-_](\d{2})-?(\d{2})-?(\d{2})(\d{3})?",
    "F34": None,
    "F35": r"^FB_IMG_(\d{13})\.",
    "F36": r"/(\d{4})(\d{2})/\d{8,}\.(?:jpg|mp4|webp)$",
    "F37": None,
    "F38": r"^DJI_(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})_(\d{4})_([A-Z])\.",
    "F39": r"^DJI_\d{4}\.",
    "F40": r"^dji_fly_(\d{8})_(\d{6})_(\d{4})_(\d{13})_(?:photo|video)\.",
    "F41": r"^(?:GOPR|GP\d{2}|G[HXS]\d{2})\d{4}\.",
    "F42": r"^(?:IMG|VID|LRV)_(\d{8})_(\d{6})_(\d{2})_(\d{3})\.(?i:insp|insv|lrv|mp4|jpg|dng)$",
    "F43": r"^(?:IMG_|_MG_|MVI_|DSC_|_DSC|DSCN|DSC|DSCF|IMGP)\d{4,5}\.",
    "F44": r"^P([1-9ABC])([0-3]\d)\d{4}\.(?i:jpg|orf|mov)$",
    "F45": None,
    "F46": None,
    "F47": r"^(\d{4})-(\d{2})-(\d{2}) (\d{2})\.(\d{2})\.(\d{2})(?:-\d+)?\.",
    "F48": r"^(\d{8})_(\d{6})(\d{3})_iOS\.",
    "F49": r"^(?:\S+ )?(\d{2})-(\d{2})-(\d{2}) (\d{2})-(\d{2})-(\d{2}) (\d+)\.",
    "F50": None,
    "F51": r"^(?:Photo|Movie) on (\d{1,2})-(\d{1,2})-(\d{2,4}) at (\d{1,2})\.(\d{2})",
    "F52": r"(?:^|\D)((?:19|20)\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])[ T_-]?([01]\d|2[0-3])[-_.:]?([0-5]\d)[-_.:]?([0-5]\d)(?:\D|$)",
    "F53": r"(?:^|\D)((?:19|20)\d{2})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])([01]\d|2[0-3])([0-5]\d)([0-5]\d)\d*(?:\D|$)",
    "F54": r"(?:^|\D)((?:19|20)\d{2})[-_.](0[1-9]|1[0-2])[-_.](0[1-9]|[12]\d|3[01])(?:\D|$)",
    "F55": r"(?:^|\D)(1\d{9}|1\d{12})(?:\D|$)",
    "F56": None,
}
PATH_RULES = {"F36"}
COMPILED = {rule: re.compile(pattern, re.ASCII) for rule, pattern in RULES.items() if pattern}


def matching(name, path):
    """Rules with a pattern that match: name is the (restored original) file name, path its relative path."""
    return [rule for rule, regex in COMPILED.items() if regex.search(path if rule in PATH_RULES else name)]
