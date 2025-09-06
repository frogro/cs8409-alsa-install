#!/usr/bin/env bash
set -euo pipefail

# cs8409-alsa-uninstall.sh — Rollback zu PipeWire + WirePlumber, PulseAudio aus
# Default:
#   - entfernt Pinning
#   - installiert pipewire-audio/pipewire-alsa
#   - deaktiviert PulseAudio (service/socket)
#   - unmask + enable PipeWire/WirePlumber (ohne --now; aktiv beim nächsten Login)
#   - setzt /etc/asound.conf auf PipeWire-Defaults
#   - entfernt cs8409.conf + Blacklists
#   - entfernt GRUB-Param snd_intel_dspcfg.dsp_driver=1
# Flags:
#   --keep-blacklists        -> Blacklists nicht löschen
#   --keep-grub              -> GRUB-Param nicht entfernen
#   --no-reinstall-pipewire  -> pipewire-audio/-alsa nicht installieren (nur Dienste)

KEEP_BLACKLISTS=0
KEEP_GRUB=0
NO_REINSTALL_PW=0

for a in "$@"; do
  case "$a" in
    --keep-blacklists)       KEEP_BLACKLISTS=1 ;;
    --keep-grub)             KEEP_GRUB=1 ;;
    --no-reinstall-pipewire) NO_REINSTALL_PW=1 ;;
    --help|-h)
      echo "Usage: $0 [--keep-blacklists] [--keep-grub] [--no-reinstall-pipewire]"
      exit 0 ;;
    *) echo "Unknown arg: $a" >&2; exit 2 ;;
  esac
done

msg(){ printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "run as root"; exit 1; }; }
have(){ command -v "$1" >/dev/null 2>&1; }
is_installed(){ dpkg -s "$1" >/dev/null 2>&1; }

require_root
U=${SUDO_USER:-$(logname 2>/dev/null || echo root)}

# 0) APT-Pinning entfernen (damit pipewire-audio/-alsa installierbar sind)
PIN=/etc/apt/preferences.d/no-pipewire-audio.pref
if [[ -f "$PIN" ]]; then
  msg "Remove APT pin that blocked pipewire-audio/pipewire-alsa"
  rm -f "$PIN"
fi

apt update -y

# 1) (optional) PipeWire-Audio-Pakete installieren
if (( NO_REINSTALL_PW == 0 )); then
  msg "Install pipewire-audio and pipewire-alsa (with recommends)"
  apt install -y --install-recommends pipewire-audio pipewire-alsa
else
  warn "Skipping pipewire-audio/pipewire-alsa installation (--no-reinstall-pipewire)"
fi

# 2) PulseAudio deaktivieren (Service + Socket), ohne Deinstallation
msg "Disable PulseAudio (user units) for next login"
su -l "$U" -s /bin/bash -c '
  { systemctl --user disable pulseaudio.service pulseaudio.socket || true; } >/dev/null 2>&1
' || true

# 3) PipeWire/WirePlumber aktivieren: Unmask + Enable (ohne --now)
msg "Enable PipeWire + WirePlumber (user units) for next login"
su -l "$U" -s /bin/bash -c '
  {
    systemctl --user unmask pipewire.service pipewire.socket || true
    systemctl --user unmask pipewire-pulse.service pipewire-pulse.socket || true
    systemctl --user unmask wireplumber.service || true

    systemctl --user enable pipewire.socket pipewire-pulse.socket || true
    systemctl --user enable pipewire.service pipewire-pulse.service wireplumber.service || true
  } >/dev/null 2>&1
' || true

# 4) /etc/asound.conf auf PipeWire-Default umstellen (statt hw:0,0)
msg "Write PipeWire defaults to /etc/asound.conf"
tee /etc/asound.conf >/dev/null <<'EOF'
pcm.!default { type pipewire }
ctl.!default { type pipewire }
EOF

# 5) CS8409- und Blacklist-Konfig entfernen (falls nicht gewünscht)
if (( KEEP_BLACKLISTS == 0 )); then
  msg "Remove cs8409.conf and blacklists created by installer"
  rm -f /etc/modprobe.d/cs8409.conf \
        /etc/modprobe.d/blacklist-generic.conf \
        /etc/modprobe.d/blacklist-sof.conf
else
  warn "Keeping blacklist files (--keep-blacklists)"
fi

# 6) GRUB-Param zurücknehmen (falls vorhanden)
if (( KEEP_GRUB == 0 )); then
  GRUB=/etc/default/grub
  PARAM=snd_intel_dspcfg.dsp_driver=1
  if [[ -f "$GRUB" ]] && grep -q '\bsnd_intel_dspcfg.dsp_driver=1\b' "$GRUB"; then
    msg "Remove $PARAM from GRUB_CMDLINE_LINUX_DEFAULT"
    # sichere Variante: nur den Param entfernen, Rest der Zeile behalten
    sed -i 's/\<snd_intel_dspcfg\.dsp_driver=1\>//g; s/  \+/ /g; s/ "\+"/ "/' "$GRUB" || true
    if have update-grub; then update-grub || true; fi
  fi
else
  warn "Keeping GRUB parameter (--keep-grub)"
fi

# 7) Kernel-Treiber reload & ALSA-State sichern (schadet auch für PipeWire nicht)
msg "Reload snd_hda_intel and store ALSA state"
modprobe -r snd_hda_intel 2>/dev/null || true
modprobe snd_hda_intel  || true
alsactl store          || true

msg "Rollback complete. PipeWire/WirePlumber will be active after next login."

# 8) Reboot-Prompt
read -rp "Do you want to reboot now? (y/n) " ans || true
case "${ans:-n}" in
  [Yy]* ) reboot ;;
  * ) echo "Reboot skipped. Please reboot or log out/in to apply user services.";;
esac
