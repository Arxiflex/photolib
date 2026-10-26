#!/usr/bin/env bash
# Threat model v1 (docs/dev/threat-model.md): STRIDE for every component and trust boundary, including a malicious
# server for private mode, every adversary of design 06 §2 mapped to threats, each threat mapped to a control and to a
# test that exists or a roadmap item that adds it, every crypto v1 vector file cited; its security-review checklist
# covers the areas pull requests must review; every Rust file outside kernel/ffi that allows unsafe code is named in
# the control that forbids it.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

MODEL=docs/dev/threat-model.md
assert_file "$MODEL"
assert_matches docs/dev/README.md '\]\(threat-model\.md\)' "the developer guide links the threat model"

# check_model <file>: one "FAIL: ..." line per problem
check_model() {
  python3 - "$1" <<'PY'
import re, subprocess, sys
from pathlib import Path
sys.path.insert(0, "tools/tests")
from check_outbound import tables

text = Path(sys.argv[1]).read_text()
sections = tables(text)
components = {row["id"] for row in sections.get("Components", [])}
boundaries = {row["id"]: row.get("boundary", "") for row in sections.get("Trust boundaries", [])}
threats = sections.get("Threats", [])
problems = [] if components and boundaries and threats else ["no Components, Trust boundaries or Threats table"]
seen, cited, names = {}, set(), set()
for row in threats:
    name = row.get("id", "?")
    if name in names:
        problems.append(f"{name} names two threats")
    names.add(name)
    letters = set(re.findall(r"[STRIDE]", row.get("stride", "")))
    if not letters or row.get("component") not in components or row.get("boundary") not in boundaries:
        problems.append(f"{name}: needs STRIDE letters, a known component and a known boundary")
    for key in (row.get("component"), row.get("boundary")):
        seen.setdefault(key, set()).update(letters)
    if not row.get("threat") or not row.get("control"):
        problems.append(f"{name}: needs a threat and a control")
    evidence = row.get("verified by", "")
    paths = re.findall(r"`([^`]+)`", evidence)
    cited.update(paths)
    if not paths and not re.search(r"planned in M\d+-\d+", evidence):
        problems.append(f"{name}: verified by neither a test of this repository nor 'planned in <roadmap key>'")
    problems += [f"{name}: {path} does not exist" for path in paths if not Path(path).exists()]
problems += [f"{v} is cited by no threat" for v in sorted(map(str, Path("kernel/testvectors/crypto").glob("*.json"))) if v not in cited]
for component in sorted(components):
    missing = set("STRIDE") - seen.get(component, set())
    if missing:
        problems.append(f"component {component} has no threat for {''.join(sorted(missing))}")
for boundary in sorted(boundaries):
    if not seen.get(boundary):
        problems.append(f"trust boundary {boundary} has no threat")
private = [key for key, text in boundaries.items() if "malicious server" in text.lower()]
if not private or set("STRI") - seen.get(private[0], set()):
    problems.append("no trust boundary for a malicious server in private mode with S, T, R and I threats")
adversaries = {row.get("#"): re.findall(r"T\d+", row.get("threats", "")) for row in sections.get("Adversaries", [])}
ids = {row.get("id") for row in threats}
for number in [str(n) for n in range(1, 8)] + ["8/9"] + [str(n) for n in range(10, 19)]:
    if not adversaries.get(number) or not set(adversaries[number]) <= ids:
        problems.append(f"adversary {number} of design 06 §2 is not mapped to threats of this model")
no_unsafe = next((row for row in threats if "No `unsafe`" in row.get("control", "")), {})
allowing = subprocess.run(["git", "grep", "-lE", r"^\s*#!?\[(allow|expect)\(.*\bunsafe_code\b", "--", "*.rs", ":!kernel/ffi"],
                          capture_output=True, text=True).stdout.split()
problems += [f"{path} allows unsafe code, but no threat's 'No `unsafe`' control names it"
             for path in allowing if f"`{path}`" not in no_unsafe.get("control", "")]
checklist = text.partition("## Security review checklist")[2].lower()
for area in ("auth", "crypto", "pars", "file", "shar", "outbound"):
    if area not in checklist:
        problems.append(f"the security review checklist does not cover '{area}'")
print("\n".join(f"FAIL: {p}" for p in problems))
PY
}

problems=$(check_model "$MODEL")
[[ -z $problems ]] && ok "every component and boundary has its STRIDE threats, controls and tests" || fail "$problems"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
broken() {
  sed "$1" "$MODEL" >"$TMP/model.md"
  [[ $(check_model "$TMP/model.md") == *"$2"* ]] && ok "the check reports $3" || fail "the check misses $3"
}
broken '/^| T[0-9]* | [^|]* | C1 | [^|]*D/d' "component C1 has no threat for D" "a component without a denial-of-service threat"
broken '0,/`app\/packages\/photolib_api\/test\/network_test.dart`/s//`app\/gone_test.dart`/' "app/gone_test.dart does not exist" \
  "a test that does not exist"
broken '0,/| planned in M[0-9]*-[0-9]* |$/s//| later |/' "verified by neither" "a threat without a test or a roadmap item"
broken '/^| 12 |/d' "adversary 12 of design 06 §2 is not mapped" "an adversary of design 06 §2 without threats"
broken '/^| T55 |/p' "T55 names two threats" "an id given to two threats"
broken 's/`kernel\/testvectors\/crypto\/pls.json` *//g' "kernel/testvectors/crypto/pls.json is cited by no threat" \
  "crypto v1 vectors that no threat cites"
broken '/^| T13 |/s/.kernel\/tests\/fuzz.rs./the fuzz test/' "kernel/tests/fuzz.rs allows unsafe code" \
  "unsafe code outside kernel/ffi that the threat model does not name"

finish
