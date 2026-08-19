#!/usr/bin/env bash
set -u

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$STATE_HOME/deadset-account-setup"
MARKER="$STATE_DIR/complete"
RUN_AGAIN=0
[[ "${1:-}" == "--again" ]] && RUN_AGAIN=1
mkdir -p "$STATE_DIR"

if [[ -f "$MARKER" && "$RUN_AGAIN" == "0" ]]; then
  exit 0
fi

launch_desktop() {
  local desktop_id="$1" fallback="$2"
  if command -v gtk-launch >/dev/null 2>&1 && gtk-launch "$desktop_id" >/dev/null 2>&1; then
    return 0
  fi
  if command -v "$fallback" >/dev/null 2>&1; then
    "$fallback" >/dev/null 2>&1 &
    disown || true
    return 0
  fi
  return 1
}

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "Deadset account setup" "$1" || true
}

if ! command -v 1password >/dev/null 2>&1; then
  notify "1Password is not installed yet. Provisioning may still be running; account setup will retry next login."
  exit 0
fi

launch_desktop 1password 1password || true

if ! command -v zenity >/dev/null 2>&1; then
  notify "1Password is open. Connect it with your phone before signing in to the other apps."
  exit 0
fi

zenity --info \
  --title="1Password first" \
  --width=560 \
  --text="1Password has been opened before your other sign-in apps.\n\nIn 1Password, choose its QR-code sign-in option and scan the code with the 1Password app on your phone. Unlock the desktop vault, then return here.\n\nNo password, token, SSH key, or account data is sent to deadset.sh by this setup." || exit 0

if ! zenity --question \
    --title="Is 1Password connected?" \
    --width=520 \
    --ok-label="Connected and unlocked" \
    --cancel-label="Not yet — retry next login" \
    --text="Continue only after your 1Password account is connected and the desktop vault is unlocked."; then
  exit 0
fi

zenity --info \
  --title="Finish 1Password integration" \
  --width=600 \
  --text="In 1Password Settings:\n\n• Security: enable system-authentication unlock if offered.\n• Developer: enable integration with the 1Password CLI.\n• Developer: enable the SSH Agent for keys stored in 1Password.\n\nVS Code already has the 1Password, Codex, and Claude Code extensions. SSH is configured to use ~/.1password/agent.sock." || true

xdg-open https://1password.com/downloads/browser-extension/ >/dev/null 2>&1 &
disown || true

selection="$(zenity --list --checklist \
  --title="Open account sign-ins" \
  --width=600 --height=360 \
  --separator='|' \
  --column="Open" --column="Application" --column="Authentication" \
  TRUE "ChatGPT + Codex" "OpenAI browser sign-in; 1Password can fill it" \
  TRUE "Claude + Claude Code" "Anthropic browser sign-in; 1Password can fill it" \
  TRUE "Visual Studio Code" "Extensions are installed; connect accounts as needed" 2>/dev/null || true)"

IFS='|' read -r -a selected_apps <<< "$selection"
for app in "${selected_apps[@]}"; do
  case "$app" in
    "ChatGPT + Codex")
      launch_desktop chatgpt chatgpt || notify "ChatGPT could not be launched. Open it from the app grid."
      ;;
    "Claude + Claude Code")
      launch_desktop claude-desktop claude-desktop || notify "Claude could not be launched. Open it from the app grid."
      ;;
    "Visual Studio Code")
      launch_desktop code code || notify "VS Code could not be launched. Open it from the app grid."
      ;;
  esac
done

if command -v op >/dev/null 2>&1 && op account list >/dev/null 2>&1; then
  cli_status="The 1Password CLI integration is responding."
else
  cli_status="The CLI is installed. If it does not unlock through the desktop app, enable Settings → Developer → Integrate with 1Password CLI."
fi

zenity --info \
  --title="Account setup ready" \
  --width=580 \
  --text="Your selected apps are opening now. Complete each vendor's own sign-in window and use 1Password to fill credentials.\n\n$cli_status\n\nYou can rerun this flow any time from the app grid: Deadset Account Setup." || true

date -Is > "$MARKER"
