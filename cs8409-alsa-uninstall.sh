#!/usr/bin/env bash
set -euo pipefail

HEADER="### cs8409-alsa-install (managed)"
TS="$(date +%Y%m%d-%H%M%S)"

msg() { printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err() { printf "\033[1;31m[✗] %s\033[0m\n" "$*"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Please run as root (sudo)."
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

remove_kernel_param() {
  local param="snd_intel_dspcfg.dsp_driver=1"
  local grub="/etc/default/grub"

  if [[ ! -f "$grub" ]]; then
    warn "$grub not found — skipping."
    return
  fi

  cp -a "$grub" "${grub}.bak-${TS}"
  msg "Backup created: ${grub}.bak-${TS}"

  # Remove param token if present (handles middle, start, end of the string)
  sed -i -E "s/(GRUB_CMDLINE_LINUX=\"[^\"]*)\b${param}\b ?/\1/g" "$grub"
  # Collapse duplicate spaces
  sed -i -E 's/(GRUB_CMDLINE_LINUX=") +/\1/g; s/  +/ /g' "$grub"

  if have_cmd update-grub; then
    msg "Running update-grub…"
    update-grub || warn "update-grub failed."
  elif have_cmd grub-mkconfig; then
    msg "Running grub-mkconfig…"
    grub-mkconfig -o /boot/grub/grub.cfg || warn "grub-mkconfig failed."
  else
    warn "Neither update-grub nor grub-mkconfig found — please rebuild your GRUB config manually."
  fi
}

remove_blacklist() {
  local f="/etc/modprobe.d/blacklist-sof.conf"
  if [[ -f "$f" ]]; then
    if grep -q "$HEADER" "$f"; then
      msg "Removing $f"
      rm -f "$f"
    else
      warn "$f exists but not managed by this installer — leaving it untouched."
    fi
  fi
}

remove_asound_conf() {
  local f="/etc/asound.conf"
  if [[ -f "$f" ]]; then
    if grep -q "$HEADER" "$f"; then
      msg "Removing $f"
      rm -f "$f"
    else
      warn "$f exists but not managed by this installer — leaving it untouched."
    fi
  fi
}

main() {
  require_root
  remove_kernel_param
  remove_blacklist
  remove_asound_conf
  msg "Uninstall complete. Reboot to apply."
}

main "$@"
