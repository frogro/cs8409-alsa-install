#!/usr/bin/env bash
set -euo pipefail

# cs8409-alsa-install.sh — ALSA + PulseAudio (GUI), Desktop-agnostisch & robust
# - Frühes APT-Pinning: blockt pipewire-audio/-alsa
# - Installiert PulseAudio + Tools
# - Entfernt pipewire-audio/-alsa, falls vorhanden (idempotent)
# - Schreibt cs8409.conf, asound.conf, Blacklists
# - Fügt GRUB-Param snd_intel_dspcfg.dsp_driver=1 nur bei Bedarf hinzu (defensiv)
# - systemd (User): PipeWire/WirePlumber maskieren, PulseAudio enable (OHNE --now)
#   -> Ausgabe der user-Befehle wird komplett unterdrückt, damit keine Bus-Fehler erscheinen
# - Lädt Treiber neu, speichert ALSA-State
# - Fragt am Ende interaktiv nach Reboot
# Reboot/Neuanmeldung startet PulseAudio automatisch.

msg(){ printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "run as root"; exit 1; }; }
have(){ command -v "$1" >/dev/null 2>&1; }
is_installed(){ dpkg -s "$1" >/dev/null 2>&1; }

require_root
U=${SUDO_USER:-$(logname 2>/dev/null || echo root)}

# 0) APT-Pinning früh setzen
PIN=/etc/apt/preferences.d/no-pipewire-audio.pref
if [[ ! -f "$PIN" ]]; then
  msg "Write APT pin to block pipewire-audio/pipewire-alsa"
  tee "$PIN" >/dev/null <<'EOF'
Package: pipewire-audio
Pin: release *
Pin-Priority: -1

Package: pipewire-alsa
Pin: release *
Pin-Priority: -1
EOF
fi

apt update -y

# 1) Pulse + Tools
msg "Install PulseAudio + tools"
apt install -y pulseaudio pulseaudio-utils pavucontrol alsa-utils

# 2) PipeWire-Audio-Konflikte entfernen (idempotent)
if is_installed pipewire-audio || is_installed pipewire-alsa; then
  msg "Remove conflicting: pipewire-audio pipewire-alsa"
  apt remove -y pipewire-audio pipewire-alsa || true
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
pcm.!default { type plug; slave.pcm "hw:0,0"; }
ctl.!default  { type hw;  card 0; }
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

# 6) GRUB-Parameter nur bei Bedarf (defensiv, bricht nie)
GRUB=/etc/default/grub
PARAM=snd_intel_dspcfg.dsp_driver=1
if [[ -f "$GRUB" ]]; then
  if ! grep -q '\bsnd_intel_dspcfg.dsp_driver=1\b' "$GRUB"; then
    msg "Add $PARAM to GRUB_CMDLINE_LINUX_DEFAULT"
    if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB"; then
      echo 'GRUB_CMDLINE_LINUX_DEFAULT="'"$PARAM"'"' >> "$GRUB" || true
    else
      sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 '"$PARAM"'"/' "$GRUB" || true
    fi
    if have update-grub; then update-grub || true; fi
  fi
fi

# 7) systemd (User): PipeWire/WirePlumber maskieren, Pulse enable — OHNE --now
#    Unterdrücke alle Ausgaben, um "Failed to connect to bus" unsichtbar zu halten, falls keine Session aktiv ist.
msg "Configure user services for next login (no --now)"
su -l "$U" -s /bin/bash -c '
  {
    systemctl --user disable pipewire.socket pipewire-pulse.socket || true
    systemctl --user mask    pipewire.service pipewire.socket     || true
    systemctl --user mask    pipewire-pulse.service pipewire-pulse.socket || true
    systemctl --user mask    wireplumber.service                  || true

    systemctl --user unmask  pulseaudio.service pulseaudio.socket || true
    systemctl --user enable  pulseaudio.socket pulseaudio.service || true
  } >/dev/null 2>&1
' || true

# 8) Treiber neu laden + ALSA-State speichern (bricht nie)
msg "Reload snd_hda_intel and store ALSA state"
modprobe -r snd_hda_intel 2>/dev/null || true
modprobe snd_hda_intel  || true
alsactl store          || true

msg "Done. Reboot recommended (then login to start Pulse automatically)."

# 9) Optionaler Reboot-Prompt (englisch)
read -rp "Do you want to reboot now? (y/n) " ans || true
case "${ans:-n}" in
  [Yy]* ) reboot ;;
  * ) echo "Reboot skipped. Please reboot manually later." ;;
esac
