# Linux ALSA + PulseAudio Configuration for Macs with Cirrus Logic CS8409
![Tested on iMac 2019](https://img.shields.io/badge/Tested%20on-iMac%202019-2b90ff?logo=apple&logoColor=white&style=flat-square)
[![ShellCheck](https://img.shields.io/github/actions/workflow/status/frogro/cs8409-alsa-install/main.yml?branch=main&label=ShellCheck<br/>&logo=gnu-bash&logoColor=white&style=flat-square)](https://github.com/frogro/cs8409-alsa-install/actions/workflows/main.yml)


This repository provides a **one-click installer** for configuring **ALSA + PulseAudio** on compatible Mac models such as **iMac and MacBook devices** equipped with the **Cirrus Logic CS8409 audio codec**.  

✅ Verified on **iMac 21.5-inch 4K Late 2019**. Other CS8409-based Macs may also be supported.<br/>✅ Verified on Debian 12 (Bookworm) and Debian 13 (Trixie). Other Linux distributions or versions — especially Debian-based ones such as Ubuntu or Linux Mint — may also work, but have not been tested.

> **Important:** This repository does **not** build or install the kernel driver itself.  
> Install the driver first via: [frogro/cs8409-dkms-wrapper](https://github.com/frogro/cs8409-dkms-wrapper).

---

## What the installer does

- Adds APT pin to block `pipewire-audio`, `pipewire-alsa`, `pipewire-pulse`
- Installs **PulseAudio + tools** (`pulseaudio`, `pulseaudio-utils`, `pavucontrol`, `alsa-utils`, `libasound2-plugins`)
- Removes any PipeWire audio components (idempotent)
- Writes **driver options** (`/etc/modprobe.d/cs8409.conf`) and **ALSA defaults** (`/etc/asound.conf`)
- Blacklists conflicting modules (`snd_hda_codec_generic`, `SOF/SoundWire`)
- Adds GRUB parameter `snd_intel_dspcfg.dsp_driver=1` if missing
- Masks **PipeWire/WirePlumber** in user services and enables PulseAudio (socket-activated)
- Reloads `snd_hda_intel` and stores ALSA state
- Ends with reboot prompt

**Result:**  
- Active profile: **ALSA + PulseAudio 16.1**  
- `pactl info` → `Server Name: pulseaudio (16.1)`
---

## Usage
## Option A: Clone the repository (recommended)

```bash
git clone https://github.com/frogro/cs8409-alsa-install.git
cd cs8409-alsa-install
sudo chmod +x cs8409-alsa-install.sh cs8409-alsa-uninstall.sh
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

  
