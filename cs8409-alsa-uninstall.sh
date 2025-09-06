#!/usr/bin/env bash
set -euo pipefail

# cs8409-alsa-uninstall-pw.sh — Reset to PipeWire + WirePlumber (without PulseAudio)
# - Removes PURE-ALSA configuration files/blacklists (packages are NOT removed)
# - Restores the user stack to PipeWire + WirePlumber
# - Disables and stops PulseAudio (optionally masks it to keep it off across reboots)
#
# Usage:
#   sudo ./cs8409-alsa-uninstall-pw.sh [--mask-pulse]
#
# If --mask-pulse is given, pulseaudio.service/socket will be masked as well.

MASK_PULSE=0
for arg in "${@:-}"; do
  case "$arg" in
    --mask-pulse) MASK_PULSE=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

msg()  { printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m[✗] %s\033[0m\n" "$*"; }

require_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "Please run as root (sudo)."; exit 1
  fi
}

user_name(){
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
msg "Target user for --user systemd: $U"

# 1) Remove PURE-ALSA files (if present)
msg "Removing /etc/asound.conf …"
rm -f /etc/asound.conf

msg "Removing /etc/modprobe.d/cs8409.conf …"
rm -f /etc/modprobe.d/cs8409.conf

msg "Removing /etc/modprobe.d/blacklist-generic.conf …"
rm -f /etc/modprobe.d/blacklist-generic.conf

msg "Removing /etc/modprobe.d/blacklist-sof.conf …"
rm -f /etc/modprobe.d/blacklist-sof.conf

# 2) Revert GRUB parameter (remove snd_intel_dspcfg.dsp_driver=1)
GRUB_CFG=/etc/default/grub
PARAM=snd_intel_dspcfg.dsp_driver=1
if [[ -f "$GRUB_CFG" ]]; then
  if grep -q "$PARAM" "$GRUB_CFG"; then
    msg "Removing $PARAM from GRUB_CMDLINE_LINUX_DEFAULT …"
    sed -i "s/ *$PARAM//" "$GRUB_CFG" || true
    if command -v update-grub >/dev/null 2>&1; then
      msg "Running update-grub …"
      update-grub
    fi
  fi
fi

# 3) Update initramfs
if command -v update-initramfs >/dev/null 2>&1; then
  msg "Updating initramfs …"
  update-initramfs -u
fi

# 4) User stack: enable PipeWire + WirePlumber, keep PulseAudio off
msg "Enabling PipeWire + WirePlumber for the user; keeping PulseAudio disabled …"
su -l "$U" -c '
  # Ensure PipeWire/WirePlumber are not masked
  systemctl --user unmask pipewire.service pipewire.socket 2>/dev/null || true
  systemctl --user unmask pipewire-pulse.service pipewire-pulse.socket 2>/dev/null || true
  systemctl --user unmask wireplumber.service 2>/dev/null || true

  # Explicitly stop/disable PulseAudio (do not unmask here)
  systemctl --user disable --now pulseaudio.service pulseaudio.socket 2>/dev/null || true

  # Start/enable PipeWire + WirePlumber
  systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true
  systemctl --user enable --now pipewire.socket pipewire-pulse.socket 2>/dev/null || true
' || warn "Could not talk to user systemd (no user login?). Re-check after next login."

# Optionally mask PulseAudio to keep it off across reboots
if (( MASK_PULSE == 1 )); then
  msg "Masking PulseAudio user services to keep them off across reboots …"
  su -l "$U" -c '
    systemctl --user mask pulseaudio.service pulseaudio.socket 2>/dev/null || true
  ' || warn "Could not mask PulseAudio for user."
fi

# 5) Optional ALSA→PipeWire defaults
cat <<'EOT'

Optional (recommended for plain ALSA apps):
  sudo tee /etc/asound.conf >/dev/null <<'EOF'
  pcm.!default { type pipewire }
  ctl.!default { type pipewire }
  EOF

=== Verification ===
- Server identity:
  pactl info | grep -i "Server Name"   # Expect: "PulseAudio (on PipeWire 0.3.xx)"
- Services:
  systemctl --user is-active pipewire.service pipewire-pulse.service wireplumber.service
- Processes:
  ps -C pipewire -o pid,cmd
- Overview:
  wpctl status

If `pactl` still reports real PulseAudio, ensure pulseaudio.service/socket are disabled (and optionally masked):
  systemctl --user disable --now pulseaudio.service pulseaudio.socket
EOT

msg "Done. A reboot is recommended to ensure all changes take full effect."
