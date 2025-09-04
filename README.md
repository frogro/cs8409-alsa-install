# ALSA Configuration for Macs with Cirrus Logic CS8409

This repository provides a **one-click installer** for configuring ALSA on compatible Mac models such as **iMac and MacBook devices** equipped with the **Cirrus Logic CS8409 audio codec**.  
✅ Verified on **iMac 21.5-inch 4K Late 2019**. Other CS8409-based Macs may also be supported.

> **Important:** This repository does **not** build or install the kernel driver itself.  
> Install the driver first via: [frogro/cs8409-dkms-wrapper](https://github.com/frogro/cs8409-dkms-wrapper).

---

## What the installer does

1. Installs required dependencies (ALSA utilities, GRUB tooling).
2. Adds the kernel boot parameter:
   ```
   snd_intel_dspcfg.dsp_driver=1
   ```
   to `/etc/default/grub` and runs `update-grub` (or `grub-mkconfig`).
3. Blacklists SOF/SoundWire modules to avoid driver conflicts.
4. Creates `/etc/asound.conf` with stable ALSA defaults: **44.1 kHz / 16-bit** output.

---

## Usage
## Option A: Clone the repository (recommended)

```bash
git clone https://github.com/frogro/cs8409-alsa-install.git
cd cs8409-alsa-install
chmod +x cs8409-alsa-install.sh cs8409-alsa-uninstall.sh
sudo ./cs8409-alsa-install.sh
sudo reboot
```
## Option B: Download only the scripts (quick method)

```bash
wget https://raw.githubusercontent.com/frogro/cs8409-alsa-install/main/cs8409-alsa-install.sh
wget https://raw.githubusercontent.com/frogro/cs8409-alsa-install/main/cs8409-alsa-uninstall.sh
chmod +x cs8409-alsa-install.sh cs8409-alsa-uninstall.sh
sudo ./cs8409-alsa-install.sh
sudo reboot
```

## Uninstall

```bash
sudo ./imac2019_audio_uninstall.sh
sudo reboot
```

## Requirements

- Linux with GRUB bootloader (tested on Debian 12/13)  
- Kernel module installed via [`cs8409-dkms-wrapper`](https://github.com/frogro/cs8409-dkms-wrapper)  
- ALSA utilities (`alsa-utils`)

## Notes

- The script modifies system files:
  - `/etc/default/grub`
  - `/etc/modprobe.d/blacklist-sof.conf`
  - `/etc/asound.conf`
- Please review before use on production systems.
- Experimental — feedback and pull requests are welcome.
