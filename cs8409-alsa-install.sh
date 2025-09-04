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

ensure_packages() {
  if have_cmd apt-get; then
    msg "Installing required packages (alsa-utils, grub tooling)…"
    DEBIAN_FRONTEND=noninteractive apt-get update -y || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y alsa-utils grub-common || true
  else
    warn "apt-get not found — please install ALSA and GRUB tooling manually on your distro."
  fi
}

check_driver() {
  if ! modinfo snd_hda_codec_cs8409 >/dev/null 2>&1; then
    warn "Kernel module snd_hda_codec_cs8409 not found by modinfo."
    warn "Install it first via: https://github.com/frogro/cs8409-dkms-wrapper"
  else
    msg "Detected kernel module snd_hda_codec_cs8409 (ok)."
  fi
}

add_kernel_param() {
  local param="snd_intel_dspcfg.dsp_driver=1"
  local grub="/etc/default/grub"

  if [[ ! -f "$grub" ]]; then
    warn "$grub not found — skipping kernel parameter step."
    return
  fi

  cp -a "$grub" "${grub}.bak-${TS}"
  msg "Backup created: ${grub}.bak-${TS}"

  if grep -qE '^\s*GRUB_CMDLINE_LINUX=' "$grub"; then
    if grep -q "$param" "$grub"; then
      msg "Kernel parameter already present in GRUB_CMDLINE_LINUX."
    else
      # Insert the parameter safely into the existing quoted value
      sed -i -E "s|^(GRUB_CMDLINE_LINUX=\"[^\"]*)\"$|\1 ${param}\"|" "$grub"
      msg "Added kernel parameter to GRUB_CMDLINE_LINUX."
    fi
  else
    printf 'GRUB_CMDLINE_LINUX="%s"\n' "$param" >> "$grub"
    msg "Created GRUB_CMDLINE_LINUX with required parameter."
  fi

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

write_blacklist() {
  local f="/etc/modprobe.d/blacklist-sof.conf"
  msg "Writing SOF/SoundWire blacklist to $f"
  cat > "$f" <<EOF
$HEADER
# Prevent SOF/SoundWire/HD-Audio conflicts with CS8409 on some Macs
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
# Alternative: enforce classic HDA via modprobe option (redundant to kernel cmdline)
# options snd_intel_dspcfg dsp_driver=1
EOF
}

write_asound_conf() {
  local f="/etc/asound.conf"
  msg "Writing ALSA defaults to $f"
  cat > "$f" <<'EOF'
### cs8409-alsa-install (managed)
# Stable defaults: 44.1 kHz, 16-bit, route to card 0
pcm.!default {
  type plug
  slave.pcm "sysdefault:0"
  slave {
    rate 44100
    format S16_LE
  }
}
ctl.!default {
  type hw
  card 0
}
EOF
}

main() {
  require_root
  ensure_packages
  check_driver
  add_kernel_param
  write_blacklist
  write_asound_conf
  msg "Done. Please reboot to apply all changes."
}

main "$@"
