#!/usr/bin/env bash
set -Eeuo pipefail

OUT=deadset-ubuntu-26.04-amd64.iso
PART0="$OUT.part00"
PART1="$OUT.part01"

test -r "$PART0"
test -r "$PART1"
: > "$OUT"
dd if="$PART0" of="$OUT" bs=8M oflag=append conv=notrunc status=none
dd if="$PART1" of="$OUT" bs=8M oflag=append conv=notrunc status=none
sha256sum -c SHA256SUMS.txt --ignore-missing
printf 'Ready: %s\n' "$OUT"
