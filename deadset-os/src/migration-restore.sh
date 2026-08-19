#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

readonly STATE=/var/lib/deadset-ubuntu-bootstrap
readonly ENVFILE=/etc/ubuntu-workstation-bootstrap/migration.env
readonly RESTORE_ROOT="$STATE/migration-restore"
readonly REPOSITORY_MOUNT="$STATE/migration-repository"
readonly RESTIC_BIN=/usr/bin/restic

say() { printf '\n[migration] %s\n' "$*"; }
die() { printf '\n[migration] ERROR: %s\n' "$*" >&2; exit 1; }
decode() { printf '%s' "$1" | base64 -d; }

[[ -r "$ENVFILE" ]] || exit 0
# shellcheck disable=SC1090
source "$ENVFILE"
[[ "${MIGRATION_ENABLED:-0}" == "1" ]] || exit 0

: "${MIGRATION_SOURCE_OS:?missing migration source OS}"
: "${MIGRATION_REPO_RELATIVE_B64:?missing repository path}"
: "${MIGRATION_REPO_CONFIG_SHA256:?missing repository identity}"
: "${MIGRATION_SNAPSHOT_ID:?missing migration snapshot ID}"
: "${MIGRATION_PASSWORD_B64:?missing repository password}"
: "${MIGRATION_SOURCE_USER_B64:?missing source user}"
: "${MIGRATION_SOURCE_HOME_B64:?missing source home}"

repo_relative="$(decode "$MIGRATION_REPO_RELATIVE_B64")"
source_user="$(decode "$MIGRATION_SOURCE_USER_B64")"
source_home="$(decode "$MIGRATION_SOURCE_HOME_B64")"
partition_id="$(decode "${MIGRATION_PARTUUID_B64:-}")"
filesystem_root="$(decode "${MIGRATION_FSROOT_B64:-}")"

[[ -n "$repo_relative" && "$repo_relative" != /* && "$repo_relative" != *'..'* ]] || \
  die "The repository-relative path is unsafe."
[[ "$source_user" =~ ^[A-Za-z0-9._-]+$ ]] || die "The source username is unsafe."
[[ "$source_home" == /* && "$source_home" != *'..'* ]] || die "The source home path is unsafe."
[[ "$MIGRATION_REPO_CONFIG_SHA256" =~ ^[a-f0-9]{64}$ ]] || die "The repository identity is invalid."
[[ "$MIGRATION_SNAPSHOT_ID" =~ ^[a-f0-9]{64}$ ]] || die "The migration snapshot ID is invalid."
[[ -x "$RESTIC_BIN" && "$(stat -c %u "$RESTIC_BIN")" == "0" ]] || die "The distribution restic executable is unavailable or untrusted."
restic_mode="$(stat -c %a "$RESTIC_BIN")"
[[ "$restic_mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$restic_mode & 8#022) == 0 )) || \
  die "The distribution restic executable is group/other-writable."

mkdir -p "$STATE" "$REPOSITORY_MOUNT"
password_file="$STATE/migration-password"
decode "$MIGRATION_PASSWORD_B64" > "$password_file"
chmod 0600 "$password_file"

root_source="$(findmnt -rn -o SOURCE / | sed 's/\[.*\]$//' || true)"
root_disk=""
if [[ -b "$root_source" ]]; then
  root_disk="$(lsblk -srnpo PATH,TYPE "$root_source" 2>/dev/null | awk '$2=="disk" {print $1; exit}')"
fi

is_on_root_disk() {
  local device="$1" ancestor
  [[ -n "$root_disk" ]] || return 1
  while read -r ancestor; do
    [[ "$ancestor" == "$root_disk" ]] && return 0
  done < <(lsblk -srnpo PATH "$device" 2>/dev/null || true)
  return 1
}

repo_matches() {
  local mountpoint="$1" candidate actual
  candidate="$mountpoint/$repo_relative"
  [[ -f "$candidate/config" ]] || return 1
  actual="$(sha256sum "$candidate/config" | awk '{print $1}')"
  [[ "$actual" == "$MIGRATION_REPO_CONFIG_SHA256" ]] || return 1
  printf '%s' "$candidate"
}

mounted_by_us=0
repository=""
candidate_device=""

try_partition() {
  local device="$1" options="ro,nosuid,nodev,noexec" found
  [[ -b "$device" ]] || return 1
  is_on_root_disk "$device" && return 1
  if findmnt -rn -S "$device" -o TARGET | head -1 | grep -q .; then
    while IFS= read -r existing_mount; do
      [[ -n "$existing_mount" ]] || continue
      umount "$REPOSITORY_MOUNT" 2>/dev/null || true
      mount --bind "$existing_mount" "$REPOSITORY_MOUNT" 2>/dev/null || continue
      if ! mount -o remount,bind,ro,nosuid,nodev,noexec "$REPOSITORY_MOUNT" 2>/dev/null; then
        umount "$REPOSITORY_MOUNT" 2>/dev/null || true
        continue
      fi
      found="$(repo_matches "$REPOSITORY_MOUNT" || true)"
      if [[ -n "$found" ]]; then
        repository="$found"
        candidate_device="$device"
        mounted_by_us=1
        return 0
      fi
      umount "$REPOSITORY_MOUNT" 2>/dev/null || true
    done < <(findmnt -rn -S "$device" -o TARGET 2>/dev/null || true)
    return 1
  fi

  umount "$REPOSITORY_MOUNT" 2>/dev/null || true
  if [[ -n "$filesystem_root" && "$filesystem_root" != "/" ]]; then
    options+=",subvol=$filesystem_root"
  fi
  mount -o "$options" "$device" "$REPOSITORY_MOUNT" 2>/dev/null || return 1
  found="$(repo_matches "$REPOSITORY_MOUNT" || true)"
  if [[ -n "$found" ]]; then
    repository="$found"
    candidate_device="$device"
    mounted_by_us=1
    return 0
  fi
  umount "$REPOSITORY_MOUNT" 2>/dev/null || true
  return 1
}

if [[ -n "$partition_id" ]]; then
  preferred="$(blkid -t "PARTUUID=$partition_id" -o device 2>/dev/null | head -1 || true)"
  [[ -z "$preferred" ]] || try_partition "$preferred" || true
fi

if [[ -z "$repository" ]]; then
  while read -r device kind filesystem; do
    [[ "$kind" == "part" ]] || continue
    case "$filesystem" in
      ext2|ext3|ext4|xfs|btrfs|vfat|fat|fat32|exfat|ntfs|ntfs3) ;;
      *) continue ;;
    esac
    try_partition "$device" && break
  done < <(lsblk -lnpo PATH,TYPE,FSTYPE 2>/dev/null)
fi

[[ -n "$repository" ]] || die "The verified migration vault was not found on any non-system partition. Attach the backup disk and reboot to retry."
say "Verified migration vault found on $candidate_device"

export RESTIC_REPOSITORY="$repository"
export RESTIC_PASSWORD_FILE="$password_file"
export RESTIC_CACHE_DIR="$STATE/restic-cache"
mkdir -p "$RESTIC_CACHE_DIR"

"$RESTIC_BIN" snapshots --no-lock "$MIGRATION_SNAPSHOT_ID" >/dev/null
"$RESTIC_BIN" check --no-lock >/dev/null

rm -rf -- "$RESTORE_ROOT"
mkdir -p "$RESTORE_ROOT"
say "Restoring the verified snapshot into temporary storage"
"$RESTIC_BIN" restore "$MIGRATION_SNAPSHOT_ID" --no-lock --target "$RESTORE_ROOT"

primary_user="${PRIMARY_USER:?PRIMARY_USER missing}"
primary_home="$(getent passwd "$primary_user" | cut -d: -f6)"
primary_group="$(id -gn "$primary_user")"
[[ -d "$primary_home" ]] || die "The new Ubuntu user's home directory does not exist."

copy_tree() {
  local source="$1" destination="$2"
  [[ -d "$source" ]] || return 0
  mkdir -p "$destination"
  rsync -aH --no-owner --no-group "$source/" "$destination/"
}

if [[ "$MIGRATION_SOURCE_OS" == "linux" ]]; then
  restored_home="$RESTORE_ROOT$source_home"
  [[ -d "$restored_home" ]] || die "The Linux home directory was not present in the restored snapshot."
  say "Restoring Linux user files and application settings"
  copy_tree "$restored_home" "$primary_home"
elif [[ "$MIGRATION_SOURCE_OS" == "windows" ]]; then
  restored_home=""
  for candidate in \
    "$RESTORE_ROOT/C/Users/$source_user" \
    "$RESTORE_ROOT/c/Users/$source_user"; do
    [[ -d "$candidate" ]] && restored_home="$candidate" && break
  done
  if [[ -z "$restored_home" ]]; then
    restored_home="$(find "$RESTORE_ROOT" -maxdepth 5 -type d -path "*/Users/$source_user" -print -quit 2>/dev/null || true)"
  fi
  [[ -d "$restored_home" ]] || die "The Windows profile was not present in the restored snapshot."

  say "Restoring portable Windows user data and mapping supported app settings"
  for name in Desktop Documents Downloads Music Pictures Videos; do
    copy_tree "$restored_home/$name" "$primary_home/$name"
  done
  for name in .gitconfig .gitignore_global .wslconfig; do
    [[ -f "$restored_home/$name" ]] && install -m 0600 "$restored_home/$name" "$primary_home/$name"
  done
  copy_tree "$restored_home/.vscode" "$primary_home/.vscode"
  copy_tree "$restored_home/AppData/Roaming/Code/User" "$primary_home/.config/Code/User"
  copy_tree "$restored_home/AppData/Roaming/Mozilla/Firefox" "$primary_home/.mozilla/firefox"
  copy_tree "$restored_home/AppData/Roaming/Thunderbird" "$primary_home/.thunderbird"
  copy_tree "$restored_home/AppData/Roaming" "$primary_home/Deadset Migration/Windows AppData/Roaming"
else
  die "Unsupported migration source OS: $MIGRATION_SOURCE_OS"
fi

report_dir="$primary_home/Deadset Migration"
mkdir -p "$report_dir"
metadata_dir="$(find "$RESTORE_ROOT" -maxdepth 7 -type d -name deadset-migration-metadata -print -quit 2>/dev/null || true)"
if [[ -n "$metadata_dir" ]]; then
  copy_tree "$metadata_dir" "$report_dir/Source inventory"
fi
cat > "$report_dir/README.txt" <<'EOF'
Deadset OS migration restore completed.

The encrypted migration vault was intentionally left on the external/secondary
disk. Keep it until you have checked your files and application settings. The
vault password is the recovery password you were required to save before WIPE.

1Password, browser login databases/cookies, operating-system credential stores,
executable startup hooks, third-party extensions, and other machine-bound state
were excluded intentionally. Unsupported application settings are retained only
under "Deadset Migration" and are not executed automatically. Use the first-login
1Password flow to reconnect accounts cleanly.
EOF

chown -R "$primary_user:$primary_group" "$primary_home"
chmod -R u+rwX "$primary_home"
touch "$STATE/migration-restored"

rm -rf -- "$RESTORE_ROOT" "$RESTIC_CACHE_DIR"
if command -v shred >/dev/null 2>&1; then
  shred -u "$password_file" 2>/dev/null || rm -f "$password_file"
else
  rm -f "$password_file"
fi
rm -f "$ENVFILE"
if ((mounted_by_us == 1)); then
  umount "$REPOSITORY_MOUNT" 2>/dev/null || true
fi

say "Restore complete. The encrypted source vault was retained for manual verification."
