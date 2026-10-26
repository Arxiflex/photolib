#!/usr/bin/env python3
"""The app stores' files: the listing of Google Play and F-Droid (Triple-T layout in the app's Android module) in every
launched language, within the stores' limits, the same words in the Linux packages' AppStream metadata, and F-Droid's
recipe, all of the release that app/pubspec.yaml names."""
import json
import os
import re
import xml.etree.ElementTree as ET

import miniyaml
from checklib import ROOT, check, finish, read

LISTINGS = "app/android/app/src/main/play/listings"
# The app's locales as Google Play names them.
PLAY = {"en": "en-US", "es": "es-ES", "fr": "fr-FR", "de": "de-DE", "it": "it-IT", "pt": "pt-BR", "ru": "ru-RU",
        "uk": "uk", "pl": "pl-PL", "nl": "nl-NL", "tr": "tr-TR", "ar": "ar", "he": "iw-IL", "hi": "hi-IN",
        "ja": "ja-JP", "ko": "ko-KR", "zh": "zh-CN", "zh_Hant": "zh-TW", "id": "id", "vi": "vi", "sv": "sv-SE"}
LIMITS = {"title.txt": 30, "short-description.txt": 80, "full-description.txt": 4000}

app = read("app/lib/l10n/locales.dart")
launched = re.findall(r"Locale\('(\w+)'\)", app.split("const launchLocales")[1].split("];")[0])
launched += [f"{lang}_{script}" for lang, script in re.findall(r"languageCode: '(\w+)', scriptCode: '(\w+)'", app)]
check(sorted(launched) == sorted(PLAY), f"every launched locale has a Play locale ({sorted(launched)})")
check(sorted(os.listdir(os.path.join(ROOT, LISTINGS))) == sorted(PLAY.values()),
      "a listing per launched locale, and no other")
metainfo = ET.parse(os.path.join(ROOT, "app/linux/packaging/org.photolib.photolib.metainfo.xml")).getroot()
LANG = "{http://www.w3.org/XML/1998/namespace}lang"
summaries = {e.get(LANG, "en"): e.text for e in metainfo.findall("summary")}
descriptions = {e.get(LANG, "en"): e.text for e in metainfo.findall("description/p")}
for locale, play in PLAY.items():
    texts = {name: read(f"{LISTINGS}/{play}/{name}").strip() if os.path.exists(f"{ROOT}/{LISTINGS}/{play}/{name}")
             else "" for name in LIMITS}
    check(all(0 < len(text) <= LIMITS[name] for name, text in texts.items()),
          f"{play}: a title, short and full description within Google Play's limits")
    lang = {"pt": "pt_BR", "zh": "zh_CN", "zh_Hant": "zh_TW"}.get(locale, locale)
    check(summaries.get(lang) == texts["short-description.txt"] and
          descriptions.get(lang) == texts["full-description.txt"],
          f"{play}: the Linux packages' AppStream metadata says the same in {lang}")

version, code = re.search(r"^version: *([0-9.]+)\+(\d+)", read("app/pubspec.yaml"), re.MULTILINE).groups()
check([r.get("version") for r in metainfo.iter("release")][:1] == [version], f"AppStream's newest release is {version}")
recipe = miniyaml.load(read("app/android/fdroid/org.photolib.photolib.yml"))
abis = {"armeabi-v7a": ("android-arm", 1000), "arm64-v8a": ("android-arm64", 2000), "x86_64": ("android-x64", 4000)}
flutter = json.loads(read("app/.fvmrc"))["flutter"]
builds = {b["output"].split("app-")[-1].removesuffix("-libre-release.apk"): b for b in recipe.get("Builds", [])}
check(set(builds) == set(abis), f"F-Droid builds one APK per ABI ({sorted(builds)})")
for abi, (target, offset) in abis.items():
    build = builds.get(abi, {})
    commands = " ".join(build.get("build", []))
    check(build.get("versionName") == version and build.get("commit") == f"v{version}" and
          build.get("versionCode") == offset + int(code) and f"flutter@{flutter}" in build.get("srclibs", []),
          f"F-Droid: {abi} of the release's tag and version code, with the app's Flutter")
    check(f"build.py --out build/kernel {target}" in commands and
          f"--flavor libre --split-per-abi --target-platform {target}" in commands,
          f"F-Droid: {abi}'s kernel built from source, then the libre flavour")
check(recipe.get("CurrentVersion") == version and recipe.get("License") == "AGPL-3.0-only",
      "F-Droid: the release, under the AGPL")
finish()
