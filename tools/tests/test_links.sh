#!/usr/bin/env bash
# Link check: every relative link in a Markdown file points at a file or directory that exists (code is not checked).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool git
cd "$REPO_ROOT" || exit 1

checked=0
while IFS= read -r -d '' file; do
  [[ -f $file ]] || continue
  dir=$(dirname "$file")
  while IFS= read -r target; do
    target=${target%%#*}
    target=${target%%\?*}
    [[ -z $target ]] && continue
    case "$target" in
      http://* | https://* | mailto:* | /*) continue ;;
    esac
    checked=$((checked + 1))
    [[ -e "$dir/$target" ]] || fail "$file: broken link '$target'"
  done < <(awk '/^[ \t]*```/ { fenced = !fenced; next } !fenced' "$file" | sed -E 's/`[^`]*`//g' |
    grep -oE '\]\([^) ]+\)' | sed -E 's/^\]\((.*)\)$/\1/')
done < <(git ls-files -z --cached --others --exclude-standard -- '*.md')
ok "checked $checked relative links"

finish
