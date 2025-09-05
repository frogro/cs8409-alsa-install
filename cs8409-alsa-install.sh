#!/usr/bin/env bash
set -euo pipefail

# cs8409-alsa-install.sh — PURE ALSA (ohne PulseAudio), mit Verifikation
# Ziel: Debian/Ubuntu/Mint (APT-basiert). Root benötigt.
# Was das Skript macht:
#  - Installiert alsa-utils (alsamixer, speaker-test, alsactl …)
#  - Erzwingt Kartenreihenfolge & iMac-Quirk (CS8409 = card0, HDMI = card1; model=imac)
#  - Setzt systemweite ALSA-Defaults (hw:0,0)
#  - Blacklistet snd_hda_codec_generic sowie optional SOF/SoundWire-Module
#  - Setzt Kernel-Parameter snd_intel_dspcfg.dsp_driver=1 in GRUB (+ update-grub)
#  - Aktualisiert initramfs
#  - Deaktiviert & MASKIERT PipeWire, WirePlumber **und PulseAudio** (USER-Services)
#  - Lädt HDA-Treiber neu
#  - Speichert ALSA-States (alsactl store)
#  - Gibt am Ende Verifikations-Hinweise aus (inkl. pactl-Check, falls vorhanden)

msg()  { printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m[✗] %s\033[0m\n" "$*"; }

require_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "Bitte mit Root-Rechten (sudo) ausführen."; exit 1
  fi
}

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

user_name(){
  # Bestmögliche Ermittlung des Ziel-Users für --user systemd
  local u
  u=${SUDO_USER:-}
  if [[ -z "$u" || "$u" == "root" ]]; then
    u=$(logname 2>/dev/null || true)
  fi
  [[ -n "$u" ]] && printf '%s' "$u" || printf 'root'
}

# --- Start ---
require_root
U=$(user_name)
msg "Ziel-User für --user systemd: $U"

# 1) Pakete
msg "Installiere alsa-utils …"
if have_cmd apt; then
  DEBIAN_FRONTEND=noninteractive apt update -y
  DEBIAN_FRONTEND=noninteractive apt install -y alsa-utils
else
  warn "APT nicht gefunden. Bitte alsa-utils manuell installieren."
fi

# 2) Kartenreihenfolge & Modell setzen
msg "Schreibe /etc/modprobe.d/cs8409.conf …"
cat > /etc/modprobe.d/cs8409.conf <<'EOF'
# cs8409-alsa-install (managed)
# Erzwinge Kartenreihenfolge und iMac-Quirk
options snd_hda_intel index=0,1
options snd_hda_intel model=imac
EOF

# 3) ALSA-Defaults systemweit
msg "Schreibe /etc/asound.conf (Defaults auf hw:0,0) …"
cat > /etc/asound.conf <<'EOF'
### cs8409-alsa-install (managed)
# Neutrale Defaults: plug konvertiert bei Bedarf auf das, was das HW-PCM akzeptiert
pcm.!default {
  type plug
  slave.pcm "hw:0,0"
}
ctl.!default {
  type hw
  card 0
}
EOF

# 4) Generic-Codec blacklist
msg "Blackliste snd_hda_codec_generic …"
cat > /etc/modprobe.d/blacklist-generic.conf <<'EOF'
# cs8409-alsa-install (managed)
blacklist snd_hda_codec_generic
EOF

# 5) Optional: SOF/SoundWire-Stacks blockieren (manche Macs)
msg "Schreibe /etc/modprobe.d/blacklist-sof.conf (optional) …"
cat > /etc/modprobe.d/blacklist-sof.conf <<'EOF'
# cs8409-alsa-install (managed)
# Verhindere Konflikte zwischen SOF/SoundWire und HDA/CS8409
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

# 6) GRUB-Parameter setzen (HDA statt SOF)
GRUB_CFG=/etc/default/grub
PARAM=snd_intel_dspcfg.dsp_driver=1
if [[ -f "$GRUB_CFG" ]]; then
  if grep -q "$PARAM" "$GRUB_CFG"; then
    msg "GRUB enthält bereits $PARAM"
  else
    msg "Füge $PARAM zu GRUB_CMDLINE_LINUX_DEFAULT hinzu …"
    sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT=\)"/\1"'"$PARAM "'/' "$GRUB_CFG" || true
  fi
  if have_cmd update-grub; then
    msg "Führe update-grub aus …"
    update-grub
  else
    warn "update-grub nicht gefunden; Bootloader manuell aktualisieren."
  fi
else
  warn "$GRUB_CFG nicht gefunden; GRUB-Änderung übersprungen."
fi

# 7) initramfs aktualisieren
if have_cmd update-initramfs; then
  msg "Aktualisiere initramfs …"
  update-initramfs -u
else
  warn "update-initramfs nicht gefunden; überspringe."
fi

# 8) PipeWire, WirePlumber **und PulseAudio** für den User stoppen/disable/mask
msg "Deaktiviere & MASKe PipeWire, WirePlumber und PulseAudio (User-Services) …"
su -l "$U" -c '
  systemctl --user stop pipewire pipewire-pulse wireplumber pulseaudio 2>/dev/null || true
  systemctl --user disable --now pipewire.socket pipewire-pulse.socket pulseaudio.socket 2>/dev/null || true
  systemctl --user mask --now pipewire.service pipewire.socket 2>/dev/null || true
  systemctl --user mask --now pipewire-pulse.service pipewire-pulse.socket 2>/dev/null || true
  systemctl --user mask --now wireplumber.service 2>/dev/null || true
  systemctl --user mask --now pulseaudio.service pulseaudio.socket 2>/dev/null || true
' || warn "Konnte nicht mit user systemd sprechen (kein User-Login?). Wirksam nach nächster Anmeldung."

# 9) HDA-Treiber neu laden (Best-Effort)
msg "Lade snd_hda_intel neu …"
modprobe -r snd_hda_intel 2>/dev/null || true
sleep 1
modprobe snd_hda_intel || warn "Konnte snd_hda_intel nicht laden; dmesg prüfen."

# 10) ALSA-States speichern
if have_cmd alsactl; then
  msg "Speichere ALSA-State (alsactl store) …"
  alsactl store || warn "alsactl store fehlgeschlagen; ggf. nach Mixer-Anpassung erneut ausführen."
else
  warn "alsactl nicht gefunden (paket alsa-utils fehlt?)."
fi

# 11) Verifikation & Hinweise
cat <<'EOT'

=== Verifikation (PURE ALSA) ===
1) Karten & Geräte (ALSA):
   aplay -l
   arecord -l
   # Erwartung: Karte 0 = HDA Intel PCH (CS8409), Karte 1 = HDMI

2) Default-Device testen (ein kurzer Ton):
   speaker-test -D default -c 2 -t sine -f 440 -l 1

3) Prüfen, dass **kein** PipeWire/PulseAudio aktiv ist:
   # Prozesse
   ps -C pipewire -o pid,cmd
   ps -C pulseaudio -o pid,cmd
   # Systemd-Status (User)
   systemctl --user is-active pipewire.service pipewire-pulse.service wireplumber.service pulseaudio.service || true
   systemctl --user is-enabled pipewire.socket pipewire-pulse.socket pulseaudio.socket || true

4) Optionaler Check mit pactl (falls installiert):
   pactl info | grep -i "Server Name" || echo "OK: Kein PulseAudio-Server aktiv oder pactl nicht vorhanden."
   # Wenn dennoch etwas wie "PulseAudio (on PipeWire …)" erscheint, ist der PipeWire-Stack noch aktiv.

5) Mixer prüfen/setzen (z. B. Kanäle entmuten, Lautstärke anheben):
   alsamixer
   # Danach den Zustand persistent speichern:
   sudo alsactl store

— Hinweis —
- Ein Reboot ist empfehlenswert, damit GRUB-Parameter + initramfs-Änderungen vollständig greifen.
- Desktop-Einstellungen (GNOME/KDE) zeigen im PURE‑ALSA‑Modus keine Geräte an. Verwende alsamixer/qasmixer.
- Für Studio/Mehrfach‑App‑Audio erwäge JACK:  jackd -d alsa -d hw:0 -r 48000 -p 128 -n 3
EOT

msg "Fertig. Reboot empfohlen."
