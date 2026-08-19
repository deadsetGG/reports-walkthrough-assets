#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iso"
BASE="$BUILD/ubuntu-26.04-live-server-amd64.iso"
OUT="$BUILD/deadset-ubuntu-26.04-amd64.iso"
BASE_URL="https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso"
BASE_SHA256="dec49008a71f6098d0bcfc822021f4d042d5f2db279e4d75bdd981304f1ca5d9"
XORRISO="${XORRISO:-xorriso}"

mkdir -p "$BUILD"

if [[ ! -f "$BASE" ]]; then
  curl -fL --retry 4 --retry-all-errors -o "$BASE.part" "$BASE_URL"
  mv "$BASE.part" "$BASE"
fi

printf '%s  %s\n' "$BASE_SHA256" "$BASE" | sha256sum -c -
command -v "$XORRISO" >/dev/null 2>&1 || [[ -x "$XORRISO" ]] || {
  echo "xorriso is required" >&2
  exit 1
}

for file in \
  iso-autoinstall.yaml iso-grub.cfg iso-loopback.cfg \
  firstboot.sh firstboot.service first-login.sh first-login.desktop \
  migration-restore.sh jellyfin.compose.yml; do
  test -r "$ROOT/src/$file"
done

STAGE="$(mktemp -d "$BUILD/.stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/deadset" "$STAGE/.disk"

install -m 0644 "$ROOT/src/iso-autoinstall.yaml" "$STAGE/autoinstall.yaml"
install -m 0644 "$ROOT/src/iso-grub.cfg" "$STAGE/grub.cfg"
install -m 0644 "$ROOT/src/iso-loopback.cfg" "$STAGE/loopback.cfg"
install -m 0755 "$ROOT/src/firstboot.sh" "$STAGE/deadset/firstboot.sh"
install -m 0644 "$ROOT/src/firstboot.service" "$STAGE/deadset/firstboot.service"
install -m 0755 "$ROOT/src/first-login.sh" "$STAGE/deadset/first-login.sh"
install -m 0644 "$ROOT/src/first-login.desktop" "$STAGE/deadset/first-login.desktop"
install -m 0755 "$ROOT/src/migration-restore.sh" "$STAGE/deadset/migration-restore.sh"
install -m 0644 "$ROOT/src/jellyfin.compose.yml" "$STAGE/deadset/jellyfin.compose.yml"

printf '%s\n' \
  'Deadset Ubuntu 26.04 LTS amd64' \
  'Interactive Ubuntu installation with embedded Deadset first-boot provisioning.' \
  'The installer asks you to select storage and create the user locally.' \
  'After installation, provisioning installs the desktop/developer/server stack and opens 1Password first.' \
  > "$STAGE/deadset/README.txt"
printf '%s\n' 'Deadset Ubuntu 26.04 LTS amd64' > "$STAGE/.disk/info"

"$XORRISO" -osirrox on -indev "$BASE" -extract /md5sum.txt "$STAGE/md5sum.original" >/dev/null 2>&1
awk '!/^([0-9a-f]{32})  \.\/(autoinstall\.yaml|boot\/grub\/grub\.cfg|boot\/grub\/loopback\.cfg|\.disk\/info|deadset\/)/' \
  "$STAGE/md5sum.original" > "$STAGE/md5sum.txt"

add_md5() {
  local source="$1" target="$2"
  printf '%s  ./%s\n' "$(md5sum "$source" | awk '{print $1}')" "$target" >> "$STAGE/md5sum.txt"
}
add_md5 "$STAGE/autoinstall.yaml" autoinstall.yaml
add_md5 "$STAGE/grub.cfg" boot/grub/grub.cfg
add_md5 "$STAGE/loopback.cfg" boot/grub/loopback.cfg
add_md5 "$STAGE/.disk/info" .disk/info
while IFS= read -r -d '' file; do
  add_md5 "$file" "deadset/${file##*/}"
done < <(find "$STAGE/deadset" -maxdepth 1 -type f -print0 | sort -z)

rm -f "$OUT" "$OUT.sha256"
"$XORRISO" \
  -indev "$BASE" \
  -outdev "$OUT" \
  -boot_image any replay \
  -volid DEADSET_UBUNTU_2604 \
  -map "$STAGE/autoinstall.yaml" /autoinstall.yaml \
  -map "$STAGE/grub.cfg" /boot/grub/grub.cfg \
  -map "$STAGE/loopback.cfg" /boot/grub/loopback.cfg \
  -map "$STAGE/.disk/info" /.disk/info \
  -map "$STAGE/deadset" /deadset \
  -map "$STAGE/md5sum.txt" /md5sum.txt \
  -commit

(cd "$BUILD" && sha256sum "${OUT##*/}" > "${OUT##*/}.sha256")
printf 'Built %s\n' "$OUT"
cat "$OUT.sha256"
