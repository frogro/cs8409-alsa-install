#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# cs8409-alsa-install.sh (rev5c, headless, without machinectl)
# - Installs PulseAudio + tools (+ libasound2-plugins / ALSA→Pulse bridge)
# - Blocks PipeWire audio layers via APT pin and removes any installed pipewire-{audio,alsa,pulse}
# - Writes CS8409/HDA options, ALSA defaults, blacklists
# - Adds GRUB param snd_intel_dspcfg.dsp_driver=1 (if not already present)
# - Reloads kernel driver, initializes/saves ALSA state
# - Starts headless user@UID.service, enables & starts PulseAudio (socket-activated)
# - Clears /dev/snd/* blockers, resets user Pulse state, loads module-udev-detect (tsched=0)
# - Clean-up: disables PipeWire/WirePlumber, removes mask symlinks, verifies under target user

msg(){ printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m[✗] %s\033[0m\n" "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
is_installed(){ dpkg -s "$1" >/dev/null 2>&1; }

require_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "Please run as root (sudo)."
    exit 1
  fi
}

start_user_manager(){
  local user="$1" uid
  uid=$(id -u "$user")
  loginctl enable-linger "$user" >/dev/null 2>&1 || true
  systemctl start "user@${uid}.service" || true
  sleep 0.5
}

userctl(){
  # Safely run systemd user commands in the target user’s context
  local user="$1"; shift
  systemctl --user --machine="${user}@" "$@"
}

pactl_user(){
  # Run pactl in the target user’s context with correct XDG_RUNTIME_DIR
  local user="$1"; shift
  local uid xdg pulse
  uid=$(id -u "$user")
  xdg="/run/user/${uid}"
  pulse="${xdg}/pulse"
  sudo -u "$user" XDG_RUNTIME_DIR="$xdg" PULSE_RUNTIME_PATH="$pulse" "$@"
}

require_root

U=${SUDO_USER:-$(logname 2>/dev/null || echo root)}
GRUB=/etc/default/grub
PARAM=snd_intel_dspcfg.dsp_driver=1
PIN=/etc/apt/preferences.d/no-pipewire-audio.pref

# 0) APT pinning against PipeWire audio layers (defensive)
if [[ ! -f "$PIN" ]]; then
  msg "Write APT pin to block pipewire-audio/pipewire-alsa/pipewire-pulse"
  tee "$PIN" >/dev/null <<'EOF'
Package: pipewire-audio
Pin: release *
Pin-Priority: -1

Package: pipewire-alsa
Pin: release *
Pin-Priority: -1

Package: pipewire-pulse
Pin: release *
Pin-Priority: -1
EOF
fi

# Update package lists
if have apt-get; then
  apt-get update -y || true
else
  apt update -y || true
fi

# 1) Install PulseAudio + tools + bridge
msg "Install PulseAudio + tools (+ libasound2-plugins)"
if have apt-get; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    pulseaudio pulseaudio-utils pavucontrol alsa-utils libasound2-plugins
else
  apt install -y pulseaudio pulseaudio-utils pavucontrol alsa-utils libasound2-plugins
fi

# 2) Remove PipeWire audio conflicts (idempotent)
to_remove=()
is_installed pipewire-audio && to_remove+=(pipewire-audio)
is_installed pipewire-alsa  && to_remove+=(pipewire-alsa)
is_installed pipewire-pulse && to_remove+=(pipewire-pulse)
if ((${#to_remove[@]})); then
  msg "Remove conflicting: ${to_remove[*]}"
  if have apt-get; then
    DEBIAN_FRONTEND=noninteractive apt-get remove -y "${to_remove[@]}" || true
  else
    apt remove -y "${to_remove[@]}" || true
  fi
fi

# 3) CS8409 options
msg "Write /etc/modprobe.d/cs8409.conf"
tee /etc/modprobe.d/cs8409.conf >/dev/null <<'EOF'
options snd_hda_intel index=0,1
options snd_hda_intel model=imac
EOF

# 4) ALSA defaults
msg "Write /etc/asound.conf"
tee /etc/asound.conf >/dev/null <<'EOF'
pcm.!default {
  type plug
  slave.pcm "hw:0,0"
}
ctl.!default {
  type hw
  card 0
}
EOF

# 5) Blacklists
msg "Blacklist snd_hda_codec_generic"
echo "blacklist snd_hda_codec_generic" > /etc/modprobe.d/blacklist-generic.conf

msg "Blacklist SOF/SoundWire (recommended on some Macs)"
tee /etc/modprobe.d/blacklist-sof.conf >/dev/null <<'EOF'
blacklist snd_sof_pci_intel_cnl
blacklist snd_sof_pci_intel_tgl
blacklist snd_sof_pci_intel_icl
blacklist snd_sof_pci_intel_apl
blacklist snd_sof_pci
blacklist snd_sof_intel_hda_common
blacklist snd_sof_intel_hda
blacklist snd_sof
blacklist soundwire_intel
blacklist soundwire_bus
blacklist snd_soc_skl
EOF

# 6) GRUB parameter (defensive append)
if [[ -f "$GRUB" ]] && ! grep -q '\bsnd_intel_dspcfg\.dsp_driver=1\b' "$GRUB"; then
  msg "Add $PARAM to GRUB_CMDLINE_LINUX_DEFAULT"
  if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB"; then
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$PARAM\"" >> "$GRUB" || true
  else
    # Extend existing entry
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 '"$PARAM"'"/' "$GRUB" || true
  fi
  if have update-grub; then update-grub || true; fi
fi

# 7) Reload kernel driver + ALSA state
msg "Reload snd_hda_intel and store ALSA state"
modprobe -r snd_hda_intel 2>/dev/null || true
modprobe    snd_hda_intel 2>/dev/null || true
alsactl init  2>/dev/null || true
alsactl store 2>/dev/null || true

# 8) Start user@UID.service & configure services
msg "Start user manager and configure PulseAudio"
start_user_manager "$U"

# Disable/stop PipeWire & WirePlumber (no masking needed)
userctl "$U" disable --now \
  pipewire.service pipewire.socket \
  pipewire-pulse.service pipewire-pulse.socket \
  wireplumber.service 2>/dev/null || true

# Allow & start PulseAudio (socket-activated)
userctl "$U" unmask pulseaudio.service pulseaudio.socket 2>/dev/null || true
userctl "$U" enable pulseaudio.socket pulseaudio.service || true
userctl "$U" start  pulseaudio.socket || true

# 9) Clear blockers, re-init Pulse, load module-udev-detect
msg "Clear /dev/snd blockers, reinit Pulse, load udev-detect"
fuser -k /dev/snd/* 2>/dev/null || true
userctl "$U" stop pulseaudio.service pulseaudio.socket || true
rm -rf "/home/${U}/.config/pulse" "/home/${U}/.pulse" 2>/dev/null || true
userctl "$U" start pulseaudio.socket
sleep 1
pactl_user "$U" pactl unload-module module-udev-detect 2>/dev/null || true
pactl_user "$U" pactl load-module module-udev-detect tsched=0 || true

# 10) Status & quick test (in target user context)
pactl_user "$U" sh -lc 'echo "--- pactl info ---"; pactl info | grep -E "Server Name|Default Sink" || true'
pactl_user "$U" sh -lc 'echo "--- sinks ---"; pactl list short sinks || true'
pactl_user "$U" speaker-test -D pulse -c 2 -t sine -f 440 -l 1 >/dev/null 2>&1 || true &

# --- Clean-up: ensure PulseAudio is the only active stack ---
msg "Clean-up: ensure only PulseAudio stack is active"

# Disable/stop PipeWire & WirePlumber again (race safety)
userctl "$U" disable --now \
  pipewire.service pipewire.socket \
  pipewire-pulse.service pipewire-pulse.socket \
  wireplumber.service 2>/dev/null || true

# Clean up user mask symlinks to /dev/null (from previous experiments)
USER_UNIT_DIR="$(eval echo ~"$U")/.config/systemd/user"
if [[ -d "$USER_UNIT_DIR" ]]; then
  find "$USER_UNIT_DIR" -maxdepth 1 -xtype l -lname /dev/null -print -delete || true
fi

# Ensure PulseAudio is active
userctl "$U" unmask pulseaudio.service pulseaudio.socket 2>/dev/null || true
userctl "$U" enable pulseaudio.socket pulseaudio.service || true
userctl "$U" start  pulseaudio.socket || true
sleep 1

# Quick verify (in target user context)
pactl_user "$U" pactl info | grep -E 'Server Name|Default Sink' || true
pactl_user "$U" pactl list short sinks || true

msg "All done. If GRUB was changed, a reboot is recommended."
exit 0
