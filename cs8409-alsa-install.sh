#!/usr/bin/env bash
set -euo pipefail

# cs8409-alsa-install.sh (rev5b, headless, ohne machinectl)
# - PulseAudio + libasound2-plugins installieren
# - pipewire-audio/alsa/pulse wegpinnen/entfernen, WirePlumber/PipeWire maskieren
# - HDA/CS8409-Optionen, Blacklists, GRUB-Param setzen
# - user@UID.service starten, Pulse (socket) aktivieren/starten
# - Blockierer (/dev/snd/*) beenden, Pulse neu initialisieren
# - module-udev-detect laden (tsched=0 Fallback), Sinks prüfen, Testton anstoßen

msg(){ printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m[✗] %s\033[0m\n" "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
is_installed(){ dpkg -s "$1" >/dev/null 2>&1; }

require_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "Bitte mit Root-Rechten (sudo) ausführen."
    exit 1
  fi
}

start_user_manager(){
  local user="$1"; local uid
  uid=$(id -u "$user")
  loginctl enable-linger "$user" >/dev/null 2>&1 || true
  systemctl start "user@${uid}.service"
  sleep 0.5
}

userctl(){
  local user="$1"; shift
  systemctl --user --machine="${user}@" "$@"
}

pactl_user(){
  # pactl im Kontext des Users mit korrekt gesetztem Runtime-Dir
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

# 0) APT-Pinning gegen PipeWire-Audio-Schichten
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

# Paketlisten aktualisieren
if have apt-get; then apt-get update -y || true; else apt update -y || true; fi

# 1) PulseAudio + Tools + Bridge
msg "Install PulseAudio + tools (+ libasound2-plugins)"
if have apt-get; then
  apt-get install -y pulseaudio pulseaudio-utils pavucontrol alsa-utils libasound2-plugins
else
  apt install -y pulseaudio pulseaudio-utils pavucontrol alsa-utils libasound2-plugins
fi

# 2) PipeWire-Audio-Konflikte entfernen (idempotent)
to_remove=()
is_installed pipewire-audio && to_remove+=(pipewire-audio)
is_installed pipewire-alsa  && to_remove+=(pipewire-alsa)
is_installed pipewire-pulse && to_remove+=(pipewire-pulse)
if ((${#to_remove[@]})); then
  msg "Remove conflicting: ${to_remove[*]}"
  if have apt-get; then apt-get remove -y "${to_remove[@]}" || true; else apt remove -y "${to_remove[@]}" || true; fi
fi

# 3) CS8409-Optionen
msg "Write /etc/modprobe.d/cs8409.conf"
tee /etc/modprobe.d/cs8409.conf >/dev/null <<'EOF'
options snd_hda_intel index=0,1
options snd_hda_intel model=imac
EOF

# 4) ALSA-Defaults
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

# 6) GRUB-Parameter (defensiv)
if [[ -f "$GRUB" ]] && ! grep -q '\bsnd_intel_dspcfg\.dsp_driver=1\b' "$GRUB"; then
  msg "Add $PARAM to GRUB_CMDLINE_LINUX_DEFAULT"
  if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB"; then
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$PARAM\"" >> "$GRUB" || true
  else
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 '"$PARAM"'"/' "$GRUB" || true
  fi
  have update-grub && update-grub || true
fi

# 7) Kernel-Treiber neu laden + ALSA-State
msg "Reload snd_hda_intel and store ALSA state"
modprobe -r snd_hda_intel 2>/dev/null || true
modprobe snd_hda_intel    2>/dev/null || true
alsactl init              2>/dev/null || true
alsactl store             2>/dev/null || true

# 8) user@UID.service starten & Services konfigurieren
msg "Start user manager and configure services"
start_user_manager "$U"
userctl "$U" mask pipewire.service pipewire.socket pipewire-pulse.service pipewire-pulse.socket wireplumber.service || true
userctl "$U" unmask pulseaudio.service pulseaudio.socket || true
userctl "$U" enable pulseaudio.socket pulseaudio.service
userctl "$U" start  pulseaudio.socket

# 9) Blockierer lösen, Pulse frisch, udev-detect laden
msg "Clear /dev/snd blockers, reinit Pulse, load udev-detect"
fuser -k /dev/snd/* 2>/dev/null || true
userctl "$U" stop pulseaudio.service pulseaudio.socket || true
rm -rf "/home/${U}/.config/pulse" "/home/${U}/.pulse" 2>/dev/null || true
userctl "$U" start pulseaudio.socket
sleep 1
pactl_user "$U" pactl unload-module module-udev-detect 2>/dev/null || true
pactl_user "$U" pactl load-module module-udev-detect tsched=0 || true

# 10) Status & Testton
pactl_user "$U" sh -lc 'echo "--- pactl info ---"; pactl info | egrep "Name des Servers|Standard-Ziel" || true'
pactl_user "$U" sh -lc 'echo "--- sinks ---"; pactl list short sinks || true'
pactl_user "$U" speaker-test -D pulse -c 2 -t sine -f 440 -l 1 >/dev/null 2>&1 || true &

# --- Clean-up: ensure PulseAudio is the only active stack ---
msg "Clean-up: disable PipeWire/WirePlumber, enable PulseAudio"

# Stop + disable PipeWire & WirePlumber
systemctl --user disable --now \
  pipewire.service pipewire.socket \
  pipewire-pulse.service pipewire-pulse.socket \
  wireplumber.service 2>/dev/null || true

# Remove user mask symlinks to /dev/null (if they exist from experiments)
find "/home/$U/.config/systemd/user" -maxdepth 1 -xtype l -lname /dev/null -print -delete || true

# Enable + start PulseAudio (socket-activated)
systemctl --user unmask pulseaudio.service pulseaudio.socket 2>/dev/null || true
systemctl --user enable pulseaudio.socket pulseaudio.service || true
systemctl --user start pulseaudio.socket || true
sleep 1

# Quick verify
pactl info | egrep 'Name des Servers|Standard-Ziel' || true
pactl list short sinks || true

msg "All done. If GRUB was changed, a reboot is recommended."
exit 0
