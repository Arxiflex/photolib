#!/usr/bin/env bash
# The lint ratchet (docs/dev/lint.md); its usage is in ratchet.py.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/ratchet.py" "$@"
