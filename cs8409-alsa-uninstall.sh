#!/usr/bin/env bash
set -euo pipefail

# cs8409-alsa-uninstall.sh — revert classic PulseAudio profile (incl. GRUB revert)
# - Removes /etc/modprobe.d/cs8409.conf and /etc/asound.conf
# - Removes blacklist-{generic,sof}.conf
# - Removes APT pin /etc/apt/preferences.d/no-pipewire-audio.pref
# - Reverts GRUB param snd_intel_dspcfg.dsp_driver=1 and runs update-grub
# - Unmasks PipeWire units, disables/stops PulseAudio user units
# - Optional: --purge removes pulseaudio*, pavucontrol, libasound2-plugins
#
# Usage: sudo ./cs8409-alsa-uninstall.sh [--purge]

msg(){ printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m[✗] %s\033[0m\n" "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

U=${SUDO_USER:-$(logname 2>/dev/null || echo ${USER})}
uid=$(id -u "$U")

start_user_manager(){
  loginctl enable-linger "$U" >/dev/null 2>&1 || true
  systemctl start "user@${uid}.service" || true
  sleep 0.4
}
userctl(){ systemctl --user --machine="${U}@" "$@"; }

# 1) Config cleanup
msg "Removing CS8409/ALSA configs & blacklists"
rm -f /etc/modprobe.d/cs8409.conf /etc/asound.conf \
      /etc/modprobe.d/blacklist-generic.conf /etc/modprobe.d/blacklist-sof.conf

# 2) Remove APT pin (restore neutrality)
if [[ -f /etc/apt/preferences.d/no-pipewire-audio.pref ]]; then
  msg "Removing APT pin blocking PipeWire"
  rm -f /etc/apt/preferences.d/no-pipewire-audio.pref
  have apt-get && apt-get update -y || true
fi

# 3) Revert GRUB param
if [[ -f /etc/default/grub ]] && grep -q '\bsnd_intel_dspcfg\.dsp_driver=1\b' /etc/default/grub; then
  msg "Reverting GRUB parameter snd_intel_dspcfg.dsp_driver=1"
  sed -i 's/\bsnd_intel_dspcfg\.dsp_driver=1\b//g; s/  \+/ /g; s/=" "/=""/' /etc/default/grub
  have update-grub && update-grub || true
fi

# 4) User services: unmask PipeWire, disable PulseAudio
start_user_manager
msg "Resetting user services (unmask PipeWire, disable PulseAudio)"
userctl unmask pipewire.service pipewire.socket pipewire-pulse.service pipewire-pulse.socket wireplumber.service || true
userctl disable --now pulseaudio.service pulseaudio.socket || true

# 5) Optional package purge
if [[ $PURGE -eq 1 ]]; then
  msg "Purging PulseAudio packages"
  DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y \
    pulseaudio pulseaudio-utils pavucontrol libasound2-plugins || true
fi

msg "Done. Reboot recommended (GRUB may have changed)."
