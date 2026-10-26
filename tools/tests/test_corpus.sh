#!/usr/bin/env bash
# Media corpus (M0-28): the tooling's own tests, then the corpus itself.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3

corpus=$REPO_ROOT/testdata/corpus

for suite in corpus_tests corpus_format_tests avc_twins_tests; do
  if python3 "$REPO_ROOT/tools/tests/$suite.py"; then ok "$suite passes"; else fail "$suite fails"; fi
done

# The committed corpus is the generator's output, and it satisfies the schema, the file checks and the coverage rules.
if python3 "$REPO_ROOT/tools/corpus/build.py" --check; then ok "corpus matches its generator"; else
  fail "corpus drifted from tools/corpus/build.py; regenerate with python3 tools/corpus/build.py"
fi
if python3 "$REPO_ROOT/tools/corpus/validate.py"; then ok "corpus validates"; else fail "corpus does not validate"; fi

# Every file meant to be decodable decodes with the Pillow pinned in decode-requirements.txt, installed once (network
# on the first run) into a private cache outside the checkout, which may sit on a noexec mount where Pillow cannot load.
requirements=$REPO_ROOT/tools/corpus/decode-requirements.txt
cache=${PHOTOLIB_CACHE:-${TMPDIR:-/var/tmp}/photolib-$(id -u)}
venv=$cache/corpus-venv
mkdir -p -m 700 "$cache"
# Never run code from a cache another user could have written: it must be ours, a real directory, and private.
if [[ -L $cache || ! -O $cache ]] || ! chmod 700 "$cache"; then
  fail "$cache is not a private directory of this user; set PHOTOLIB_CACHE"
else
  if [[ -L $venv || ! -O $venv ]] || ! cmp -s "$requirements" "$venv/requirements.txt"; then
    rm -rf "$venv"
    python3 -m venv "$venv" && "$venv/bin/python" -m pip install --quiet --disable-pip-version-check -r "$requirements" &&
      cp "$requirements" "$venv/requirements.txt"
  fi
  if "$venv/bin/python" "$REPO_ROOT/tools/tests/corpus_decode.py"; then ok "corpus files decode"; else
    fail "corpus files that should decode do not (tools/tests/corpus_decode.py)"
  fi
fi

# Every field of the golden record is documented in the corpus README.
fields=$(python3 - "$corpus/golden.schema.json" <<'PY'
import json, sys

def walk(node):
    for name, sub in node.get("properties", {}).items():
        yield name
        yield from walk(sub)
        yield from walk(sub.get("items", {}))

print("\n".join(sorted(set(walk(json.load(open(sys.argv[1])))))))
PY
)
for field in $fields; do
  if grep -Eq "\`([a-z_]+\.)*$field([^a-z_]|$)" "$corpus/README.md"; then ok "README documents $field"; else fail "README does not document $field"; fi
done

# Fixtures are bytes, not text: git must neither convert line endings nor diff them.
if git -C "$REPO_ROOT" check-attr text -- testdata/corpus/files/names/IMG_20190509_154733.jpg | grep -q "text: unset"; then
  ok "corpus files are marked binary"; else fail "corpus files are not marked binary in .gitattributes"
fi

finish
