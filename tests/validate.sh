#!/usr/bin/env bash
#
# Lightweight validation for a static HTML/CSS site.
# No dependencies — just bash, grep, and find.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

red()   { printf '\033[0;31mFAIL\033[0m %s\n' "$1"; }
green() { printf '\033[0;32mPASS\033[0m %s\n' "$1"; }

fail() { red "$1"; ERRORS=$((ERRORS + 1)); }
pass() { green "$1"; }

# ─── 1. HTML structure checks ────────────────────────────────────────────────

echo ""
echo "=== HTML Structure ==="

html_files=$(find "$ROOT" -name '*.html' -not -path '*/.git/*' -not -path '*/node_modules/*')

for f in $html_files; do
  rel="${f#$ROOT/}"

  # DOCTYPE
  if head -1 "$f" | grep -qi '<!doctype html>'; then
    pass "$rel has DOCTYPE"
  else
    fail "$rel missing DOCTYPE"
  fi

  # <html lang="">
  if grep -q '<html lang=' "$f"; then
    pass "$rel has <html lang>"
  else
    fail "$rel missing <html lang> attribute"
  fi

  # <meta charset>
  if grep -q '<meta charset=' "$f"; then
    pass "$rel has <meta charset>"
  else
    fail "$rel missing <meta charset>"
  fi

  # <meta viewport>
  if grep -q 'name="viewport"' "$f"; then
    pass "$rel has <meta viewport>"
  else
    fail "$rel missing <meta viewport>"
  fi

  # <title>
  if grep -q '<title>' "$f"; then
    pass "$rel has <title>"
  else
    fail "$rel missing <title>"
  fi
done

# ─── 2. Internal link integrity ──────────────────────────────────────────────

echo ""
echo "=== Internal Link Integrity ==="

for f in $html_files; do
  rel="${f#$ROOT/}"
  dir="$(dirname "$f")"

  # Extract href and src values that are local (not http, mailto, tel, #, or javascript)
  targets=$(grep -oP '(?:href|src)="([^"#][^"]*)"' "$f" \
    | sed 's/.*="\(.*\)"/\1/' \
    | grep -v '^https\?://' \
    | grep -v '^mailto:' \
    | grep -v '^tel:' \
    | grep -v '^javascript:' \
    | grep -v '^data:' \
    || true)

  for target in $targets; do
    resolved="$dir/$target"
    if [ -f "$resolved" ]; then
      pass "$rel -> $target exists"
    else
      fail "$rel -> $target NOT FOUND"
    fi
  done
done

# ─── 3. Image alt attributes ─────────────────────────────────────────────────

echo ""
echo "=== Image Accessibility ==="

for f in $html_files; do
  rel="${f#$ROOT/}"

  # Find <img> tags without alt attribute
  # Uses perl-style regex to match <img ... > blocks missing alt=
  imgs_without_alt=$(grep -Pon '<img\b[^>]*>' "$f" \
    | grep -v 'alt=' \
    || true)

  if [ -z "$imgs_without_alt" ]; then
    pass "$rel — all <img> tags have alt attributes"
  else
    while IFS= read -r line; do
      lineno=$(echo "$line" | cut -d: -f1)
      fail "$rel line $lineno — <img> missing alt attribute"
    done <<< "$imgs_without_alt"
  fi
done

# ─── 4. External links have rel="noopener" ───────────────────────────────────

echo ""
echo "=== External Link Safety ==="

for f in $html_files; do
  rel="${f#$ROOT/}"

  # Find target="_blank" links missing rel="noopener"
  unsafe=$(grep -Pn 'target="_blank"' "$f" \
    | grep -v 'rel="noopener"' \
    | grep -v 'rel="noopener noreferrer"' \
    || true)

  if [ -z "$unsafe" ]; then
    pass "$rel — all target=\"_blank\" links have rel=\"noopener\""
  else
    while IFS= read -r line; do
      lineno=$(echo "$line" | cut -d: -f1)
      fail "$rel line $lineno — target=\"_blank\" without rel=\"noopener\""
    done <<< "$unsafe"
  fi
done

# ─── 5. No duplicate IDs per page ────────────────────────────────────────────

echo ""
echo "=== Duplicate IDs ==="

for f in $html_files; do
  rel="${f#$ROOT/}"

  dupes=$(grep -oP 'id="[^"]*"' "$f" | sort | uniq -d || true)

  if [ -z "$dupes" ]; then
    pass "$rel — no duplicate IDs"
  else
    for dup in $dupes; do
      fail "$rel has duplicate $dup"
    done
  fi
done

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "==============================="
if [ "$ERRORS" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "$ERRORS error(s) found."
  exit 1
fi
