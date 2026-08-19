#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

readonly LOG=/var/log/deadset-ubuntu-bootstrap.log
readonly STATE=/var/lib/deadset-ubuntu-bootstrap
readonly ENVFILE=/etc/ubuntu-workstation-bootstrap/bootstrap.env
readonly ONEPASSWORD_FINGERPRINT=3FEF9748469ADBE15DA7CA80AC2D62742012EA22
readonly ANTHROPIC_FINGERPRINT=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
readonly MICROSOFT_FINGERPRINT=BC528686B50D79E339D3721CEB3E94ADBE1229CF
readonly CHATGPT_FINGERPRINT=3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4
readonly CHATGPT_KEY_B64='mQINBGpypFUBEACi1Vvzq9pIpA6lj7chbqELuxJtVuzUzxrasa6ZU0yF4yhq7jf83YkJRHwbezBKeQyzJ5lkX0EhXS8aXxUhMAm3PFpAlwcInfKzmV7atJwvaxIw6RmdGYe9fBWKjTN/SmPIjtyxrTznZY97+TfD1AeGZpLaJ8fsnhrC+HkiN2TACiTocgpehFiP0OWK7mWZeTWnY2scpIYXP1Ro7nQv4KacmY4JacTQ7m/HM0Qej/3olhuEv2CwlMVWw57/oHhmTllfLDQOogFQyIVqaaR98y/Eu6cAabSfcsqAAZ2A8vfHYD27z28JvLO2PZEJd5ThlnX4Zqv0eIpZdBj//8Sl/MSqTshFZ1NDsRoqwdqw284X5MpnOJ4k4Sc2Se8tJxt/nCeibH3dJ504Fb1X/mnOqhCAQ6pVJz4RB5HRlFPSkxVPyag1v1m/7T4vie+OR4eqFQNz6mudrOoMmeVIfyL5fbe4cOr4fk/FyvEE2xMgkFatPqXn7vM9og+zremPCfwRAFpBPyX74VowFY7llcdaj/w8K5T8PzM14Hb3E4ZKizMluKmTvTq9WE1/eSQJLLQqXD5VmtmdUaC/VyE/1ZlIxcA1LWqvEQ327UXREvX/nHsrkKrl956WjzkiHFUTsD1NJ0dMfs+csOt8Furb5jZj+HsMmCm9jLdfz5b/4WKLPbvxIwARAQABtBZDb2RleCBMaW51eCBSZXBvc2l0b3J5iQJRBBMBCgA7FiEEO/oOSui4zBai2bpoSjtKVmxGYOQFAmpypFUCGwMFCwkIBwICIgIGFQoJCAsCBBYCAwECHgcCF4AACgkQSjtKVmxGYORlCQ/9FyikZo8HQcJBP9E/oXVPds/fQnIFB2qJR2z3DrfYEonNt/evSAySkPPq4/mEOjaI0pFlDDGSaps+FTcJFgoVRTasBIF7JJivvjW9ap8iWEbhhVLeIrFLbMLpUcTRntUx7R4fVMJ/1/cGn+NWZmNwS9ORorzSyCH0IAgCw1Xc3ZrjuMbFVjdToMC1TiXXCEmlYpQakmQ3Ay1cH0FHC2BBNn1MNVkJdPhpZIZCdhaMPHfYFpyopg8wFvZ5iIcvlbMgyuy8CPJVRWUcYy2dOhEOGnYJnXRPkE3E1hf8YOHNzRlduH896lT9qcEK2+fpLfrVGoc4zscLZ+Ey+Ko6iQRdVE1j67+wNR3hX8ukue574v1N/xxui575jumSE19lEj1sH4+P4gFHOtTbF0JhKKzLctbga0IAwTPKhnt3qzj1U5Yj/MZSuEVjrLhdRauOuFBXUclgyVf2w/lE85UUOdlcollsYA6Huq7xDamqf8SslZQGre3EI+lhpqJR1cOwDMUzzcl40uTyhrxXXd/bk4QSlhZbwHR25Pnt+ZMtWavlQWS0eDEV8djuXAURCmx5WOqAFB/TJe1mn5EvyWg4VFzrY/NVNOpzgY5+Xp7J28z7f637r712Eu9j4imVcdPigwS+jf/0f81i2o9b82Y26TN8+EtDLCY841MJ1lrjDrX/dno='

mkdir -p "$STATE"
touch "$LOG"
chmod 0600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
exec 9>"$STATE/lock"
flock -n 9 || { echo "Another bootstrap instance is running."; exit 0; }

if [[ -f "$STATE/complete" ]]; then
  echo "Bootstrap already complete."
  exit 0
fi

# shellcheck disable=SC1090
source "$ENVFILE"
: "${PRIMARY_USER:?PRIMARY_USER missing}"
INSTALL_RESTRICTED_EXTRAS="${INSTALL_RESTRICTED_EXTRAS:-1}"
INSTALL_GAMING="${INSTALL_GAMING:-0}"
AUTO_REBOOT_AFTER_BOOTSTRAP="${AUTO_REBOOT_AFTER_BOOTSTRAP:-1}"
[[ "$INSTALL_RESTRICTED_EXTRAS" == "0" || "$INSTALL_RESTRICTED_EXTRAS" == "1" ]] || { echo "INSTALL_RESTRICTED_EXTRAS must be 0 or 1"; exit 1; }
[[ "$INSTALL_GAMING" == "0" || "$INSTALL_GAMING" == "1" ]] || { echo "INSTALL_GAMING must be 0 or 1"; exit 1; }
[[ "$AUTO_REBOOT_AFTER_BOOTSTRAP" == "0" || "$AUTO_REBOOT_AFTER_BOOTSTRAP" == "1" ]] || { echo "AUTO_REBOOT_AFTER_BOOTSTRAP must be 0 or 1"; exit 1; }
PRIMARY_HOME="$(getent passwd "$PRIMARY_USER" | cut -d: -f6)"
[[ -n "$PRIMARY_HOME" && -d "$PRIMARY_HOME" ]] || { echo "Primary user/home does not exist: $PRIMARY_USER"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
CURRENT_STAGE=startup

on_error() {
  local status=$? line=${BASH_LINENO[0]:-unknown}
  printf '\nBOOTSTRAP FAILED in stage %s at line %s (status %s).\n' "$CURRENT_STAGE" "$line" "$status"
  printf 'The stage is safe to retry on the next boot. Log: %s\n' "$LOG"
  exit "$status"
}
trap on_error ERR

retry() {
  local tries=0 max=5
  until "$@"; do
    tries=$((tries + 1))
    if ((tries >= max)); then
      echo "Command failed after $max attempts: $*"
      return 1
    fi
    sleep $((tries * 5))
  done
}

curl_vendor() {
  curl -q --proto '=https' --tlsv1.2 --fail --show-error --location \
    --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 20 "$@"
}

stage() {
  local name="$1"
  shift
  if [[ -f "$STATE/stage-$name" ]]; then
    echo "[done] $name"
    return 0
  fi
  CURRENT_STAGE="$name"
  printf '\n=== Stage: %s (%s) ===\n' "$name" "$(date -Is)"
  "$@"
  touch "$STATE/stage-$name"
}

install_available() {
  local -a available=()
  local package
  for package in "$@"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
      available+=("$package")
    else
      echo "[skip] not available in enabled repositories: $package"
    fi
  done
  if ((${#available[@]})); then
    retry apt-get install -y "${available[@]}"
  fi
}

install_required() {
  local package
  for package in "$@"; do
    apt-cache show "$package" >/dev/null 2>&1 || { echo "Required package is unavailable: $package"; return 1; }
  done
  retry apt-get install -y "$@"
}

install_first_available() {
  local package
  for package in "$@"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
      retry apt-get install -y "$package"
      return 0
    fi
  done
  echo "[skip] no supported package variant available: $*"
}

verify_key_fingerprint() {
  local key_file="$1" expected="$2"
  local -a primary_fingerprints=()
  mapfile -t primary_fingerprints < <(
    gpg --batch --show-keys --with-colons "$key_file" 2>/dev/null | \
      awk -F: '$1=="pub" {want=1; next} want && $1=="fpr" {print $10; want=0}'
  )
  ((${#primary_fingerprints[@]} == 1)) && [[ "${primary_fingerprints[0]}" == "$expected" ]]
}

install_armored_key() {
  local url="$1" expected="$2" output="$3" temporary
  temporary="$(mktemp "$STATE/vendor-key.XXXXXX")"
  curl_vendor --output "$temporary" "$url"
  verify_key_fingerprint "$temporary" "$expected" || {
    echo "Signing key fingerprint mismatch for $url (expected $expected)"
    return 1
  }
  gpg --batch --yes --dearmor --output "$output" "$temporary"
  chmod 0644 "$output"
  verify_key_fingerprint "$output" "$expected" || {
    echo "Dearmored signing key fingerprint mismatch for $url"
    rm -f "$output" "$temporary"
    return 1
  }
  rm -f "$temporary"
}

stage_base() {
  dpkg --configure -a || true
  retry apt-get update
  retry apt-get -y full-upgrade
  install_required ca-certificates curl gnupg software-properties-common restic rsync util-linux
  install_available ntfs-3g exfatprogs
  add-apt-repository -y universe
  add-apt-repository -y multiverse
  retry apt-get update
  install_required debsig-verify
}

stage_migration_restore() {
  if [[ -x /usr/local/sbin/deadset-migration-restore ]]; then
    PRIMARY_USER="$PRIMARY_USER" /usr/local/sbin/deadset-migration-restore
  fi
}

setup_1password_repo() {
  install -d -m 0755 /usr/share/keyrings
  install_armored_key \
    https://downloads.1password.com/linux/keys/1password.asc \
    "$ONEPASSWORD_FINGERPRINT" \
    /usr/share/keyrings/1password-archive-keyring.gpg
  cat > /etc/apt/sources.list.d/1password.list <<'EOF'
deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main
EOF

  install -d -m 0755 /etc/debsig/policies/AC2D62742012EA22 /usr/share/debsig/keyrings/AC2D62742012EA22
  curl_vendor --output "$STATE/1password.pol" https://downloads.1password.com/linux/debian/debsig/1password.pol
  install -m 0644 "$STATE/1password.pol" /etc/debsig/policies/AC2D62742012EA22/1password.pol
  install_armored_key \
    https://downloads.1password.com/linux/debian/debsig/1password.asc \
    "$ONEPASSWORD_FINGERPRINT" \
    /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
}

setup_vscode_repo() {
  install_armored_key \
    https://packages.microsoft.com/keys/microsoft.asc \
    "$MICROSOFT_FINGERPRINT" \
    /usr/share/keyrings/microsoft.gpg
  cat > /etc/apt/sources.list.d/vscode.sources <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
}

setup_anthropic_repos() {
  install_armored_key \
    https://downloads.claude.ai/keys/claude-code.asc \
    "$ANTHROPIC_FINGERPRINT" \
    /usr/share/keyrings/anthropic-archive-keyring.gpg
  cat > /etc/apt/sources.list.d/anthropic.list <<'EOF'
deb [arch=amd64 signed-by=/usr/share/keyrings/anthropic-archive-keyring.gpg] https://downloads.claude.ai/claude-code/apt/stable stable main
deb [arch=amd64 signed-by=/usr/share/keyrings/anthropic-archive-keyring.gpg] https://downloads.claude.ai/claude-desktop/apt/stable stable main
EOF
}

setup_chatgpt_repo() {
  printf '%s' "$CHATGPT_KEY_B64" | base64 -d > /usr/share/keyrings/chatgpt-archive-keyring.gpg
  chmod 0644 /usr/share/keyrings/chatgpt-archive-keyring.gpg
  verify_key_fingerprint /usr/share/keyrings/chatgpt-archive-keyring.gpg "$CHATGPT_FINGERPRINT" || {
    echo "Bundled official ChatGPT repository key has the wrong fingerprint"
    return 1
  }
  cat > /etc/apt/sources.list.d/chatgpt.sources <<'EOF'
X-Repolib-Name: ChatGPT
Types: deb
URIs: https://persistent.oaistatic.com/codex-app-prod/linux/deb
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/chatgpt-archive-keyring.gpg
EOF
}

stage_identity_apps() {
  echo "Installing 1Password and its CLI before applications that require account sign-in."
  setup_1password_repo
  retry apt-get update
  install_required 1password 1password-cli
  command -v 1password >/dev/null
  command -v op >/dev/null

  setup_vscode_repo
  setup_anthropic_repos
  setup_chatgpt_repo
  retry apt-get update
  install_required code claude-code claude-desktop chatgpt
}

stage_desktop() {
  install_available \
    ubuntu-desktop network-manager firefox libreoffice thunderbird remmina gparted \
    zenity xdg-utils seahorse gnome-tweaks \
    vlc mpv ffmpeg \
    gstreamer1.0-libav gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
    fonts-firacode fonts-jetbrains-mono

  if [[ "$INSTALL_RESTRICTED_EXTRAS" == "1" ]]; then
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections || true
    install_available ubuntu-restricted-extras
  fi
}

stage_cli_and_development() {
  install_available \
    git git-lfs gh jq yq zip unzip 7zip rsync rclone tree tmux zsh bash-completion \
    htop btop ncdu ripgrep fd-find fzf bat vim neovim shellcheck strace lsof \
    pciutils usbutils smartmontools nvme-cli lm-sensors ethtool iperf3 nmap bind9-dnsutils \
    traceroute whois socat net-tools parted hdparm powertop irqbalance fwupd \
    build-essential clang clang-format lldb lld cmake ninja-build pkg-config autoconf \
    automake libtool gdb valgrind python3-dev python3-venv python3-pip pipx \
    nodejs npm golang-go rustc cargo default-jdk ansible sqlite3 postgresql-client \
    mariadb-client direnv
  install_first_available dotnet-sdk-10.0
}

stage_virtualization_and_containers() {
  install_available \
    qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-daemon-config-network \
    libvirt-clients virt-manager virtinst ovmf swtpm bridge-utils virt-viewer \
    spice-client-gtk libguestfs-tools \
    docker.io docker-buildx docker-compose-v2 podman podman-compose \
    buildah skopeo distrobox uidmap slirp4netns fuse-overlayfs
}

stage_server_storage_media() {
  install_available \
    samba smbclient nfs-kernel-server zfsutils-linux mdadm lvm2 btrfs-progs xfsprogs \
    cockpit cockpit-machines cockpit-podman cockpit-storaged ufw apparmor-utils \
    restic borgbackup syncthing

  # AX8 Pro / Radeon 780M open graphics, firmware, compute diagnostics and media acceleration.
  install_available \
    linux-firmware amd64-microcode mesa-utils libgl1-mesa-dri mesa-vulkan-drivers \
    libva2 libva-drm2 libvdpau-va-gl1 vainfo vdpauinfo vulkan-tools \
    radeontop linux-tools-common linux-tools-generic

  if [[ "$INSTALL_GAMING" == "1" ]]; then
    install_available steam-installer gamemode mangohud gamescope
  fi
}

install_code_extensions() {
  local extension
  for extension in \
    1Password.op-vscode \
    openai.chatgpt \
    anthropic.claude-code \
    ms-vscode-remote.remote-ssh \
    ms-azuretools.vscode-docker; do
    if ! retry runuser -u "$PRIMARY_USER" -- env HOME="$PRIMARY_HOME" \
        code --install-extension "$extension" --force; then
      echo "[warning] VS Code extension could not be installed now: $extension"
    fi
  done
}

configure_1password_ssh() {
  local ssh_dir="$PRIMARY_HOME/.ssh" config="$PRIMARY_HOME/.ssh/config"
  install -d -m 0700 -o "$PRIMARY_USER" -g "$PRIMARY_USER" "$ssh_dir"
  touch "$config"
  chown "$PRIMARY_USER:$PRIMARY_USER" "$config"
  chmod 0600 "$config"
  if ! grep -Fq '# deadset: 1Password SSH agent' "$config"; then
    cat >> "$config" <<'EOF'

# deadset: 1Password SSH agent
Host *
    IdentityAgent ~/.1password/agent.sock
EOF
  fi
}

stage_configuration() {
  mkdir -p /etc/cloud/cloud.cfg.d
  printf '%s\n' 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
  rm -f /etc/netplan/50-cloud-init.yaml /etc/netplan/00-installer-config*.yaml
  cat > /etc/netplan/01-network-manager-all.yaml <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
  chmod 0600 /etc/netplan/01-network-manager-all.yaml
  netplan generate

  cat > /etc/sysctl.d/90-developer-workstation.conf <<'EOF'
fs.inotify.max_user_watches=1048576
fs.inotify.max_user_instances=1024
vm.max_map_count=1048576
EOF
  sysctl --system || true

  cat > /etc/modprobe.d/kvm-amd-nested.conf <<'EOF'
# Enable nested virtualization for the AMD VM-host profile.
options kvm_amd nested=1
EOF

  if command -v dockerd >/dev/null 2>&1; then
    mkdir -p /etc/docker
    if [[ ! -e /etc/docker/daemon.json ]]; then
      cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "local"
}
EOF
    fi
  fi

  groupadd -f media
  local directory group
  for directory in /srv/media /srv/share /srv/backups /srv/appdata /srv/cache; do
    mkdir -p "$directory"
    chown root:media "$directory"
    chmod 2775 "$directory"
  done
  for group in sudo adm libvirt kvm docker media; do
    getent group "$group" >/dev/null 2>&1 && usermod -aG "$group" "$PRIMARY_USER" || true
  done

  [[ -x /usr/bin/batcat && ! -e /usr/local/bin/bat ]] && ln -s /usr/bin/batcat /usr/local/bin/bat || true
  [[ -x /usr/bin/fdfind && ! -e /usr/local/bin/fd ]] && ln -s /usr/bin/fdfind /usr/local/bin/fd || true

  configure_1password_ssh
  install_code_extensions

  cat > /usr/share/applications/deadset-account-setup.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Deadset Account Setup
Comment=Connect 1Password, then open ChatGPT, Claude, and VS Code sign-ins
Exec=/usr/local/bin/deadset-first-login --again
Icon=dialog-password
Terminal=false
Categories=Utility;Security;
EOF

  mkdir -p /opt/homelab/jellyfin
  if [[ -f /etc/ubuntu-workstation-bootstrap/jellyfin.compose.yml ]]; then
    install -m 0644 /etc/ubuntu-workstation-bootstrap/jellyfin.compose.yml /opt/homelab/jellyfin/compose.yml
  fi

  cat > /usr/local/bin/homelab-status <<'EOF'
#!/usr/bin/env bash
set -u
printf '\n== Host ==\n'; hostnamectl || true
printf '\n== CPU/GPU ==\n'; lscpu | grep -E 'Model name|CPU\(s\)|Virtualization' || true; lspci | grep -Ei 'VGA|Display|Ethernet|Network' || true
printf '\n== Storage ==\n'; lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS,MODEL || true
printf '\n== ZFS ==\n'; zpool status 2>/dev/null || echo 'No ZFS pool imported.'
printf '\n== Libvirt ==\n'; virsh list --all 2>/dev/null || true
printf '\n== Containers ==\n'; docker ps 2>/dev/null || podman ps 2>/dev/null || true
printf '\n== Services ==\n'; systemctl --no-pager --type=service --state=running | grep -E 'ssh|docker|libvirt|cockpit' || true
printf '\nCockpit: https://<this-host>:9090 (when reachable on your LAN)\n'
EOF
  chmod 0755 /usr/local/bin/homelab-status
}

stage_services() {
  systemctl set-default graphical.target
  systemctl enable ssh.service 2>/dev/null || true
  systemctl enable docker.service 2>/dev/null || true
  systemctl enable libvirtd.service 2>/dev/null || true
  systemctl enable virtqemud.socket 2>/dev/null || true
  systemctl enable cockpit.socket 2>/dev/null || true
  systemctl enable fstrim.timer 2>/dev/null || true
  systemctl enable irqbalance.service 2>/dev/null || true

  systemctl restart docker.service 2>/dev/null || true
  systemctl start libvirtd.service 2>/dev/null || systemctl start virtqemud.socket 2>/dev/null || true
  systemctl start cockpit.socket 2>/dev/null || true
  systemctl start fstrim.timer 2>/dev/null || true

  if command -v virsh >/dev/null 2>&1 && virsh net-info default >/dev/null 2>&1; then
    virsh net-autostart default || true
    virsh net-start default || true
  fi
}

stage_inventory() {
  dpkg-query -W -f='${binary:Package}\t${Version}\n' | sort > "$STATE/packages.tsv"
  snap list > "$STATE/snaps.txt" 2>/dev/null || true
  dpkg-query -W -f='${Version}\n' code > "$STATE/vscode-version.txt" 2>/dev/null || true
  dpkg-query -W -f='${Version}\n' chatgpt > "$STATE/chatgpt-version.txt" 2>/dev/null || true
  dpkg-query -W -f='${Version}\n' claude-desktop > "$STATE/claude-desktop-version.txt" 2>/dev/null || true
  dpkg-query -W -f='${Version}\n' 1password > "$STATE/1password-version.txt" 2>/dev/null || true
  op --version > "$STATE/1password-cli-version.txt" 2>/dev/null || true
  claude --version > "$STATE/claude-code-version.txt" 2>/dev/null || true
  netplan apply || true
}

stage_secure_cleanup() {
  local sensitive
  for sensitive in \
    /var/lib/cloud/instances/*/user-data.txt \
    /var/lib/cloud/instances/*/user-data.txt.i \
    /var/log/installer/autoinstall-user-data; do
    [[ -f "$sensitive" ]] || continue
    if command -v shred >/dev/null 2>&1; then
      shred -u "$sensitive" 2>/dev/null || rm -f "$sensitive"
    else
      rm -f "$sensitive"
    fi
  done
}

echo "=== Deadset Ubuntu workstation bootstrap: $(date -Is) ==="
stage base stage_base
stage migration-restore stage_migration_restore
stage identity-apps stage_identity_apps
stage desktop stage_desktop
stage cli-development stage_cli_and_development
stage virtualization-containers stage_virtualization_and_containers
stage server-storage-media stage_server_storage_media
stage configuration stage_configuration
stage services stage_services
stage inventory stage_inventory
stage secure-cleanup stage_secure_cleanup

touch "$STATE/complete"
systemctl disable ubuntu-workstation-bootstrap.service || true
echo "=== Bootstrap complete: $(date -Is) ==="
echo "1Password will open before other account sign-ins on the first GNOME login."
echo "Run 'homelab-status' after login. Log: $LOG"

if [[ "$AUTO_REBOOT_AFTER_BOOTSTRAP" == "1" ]]; then
  systemctl reboot
fi
