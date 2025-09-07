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
## Verify after login
```bash
# Check that PulseAudio is active
systemctl --user is-active pulseaudio.socket pulseaudio.service
# expected: "active" "active"

# Check that PipeWire/WirePlumber are not running
systemctl --user is-active pipewire.socket pipewire-pulse.socket wireplumber.service
# expected: "inactive" or "failed" (they should not run)

# Check the PulseAudio server info
pactl info | egrep 'Name des Servers|Standard-Ziel'
# expected: "Server Name: pulseaudio"
# expected: "Default Sink: alsa_output.pci-0000_00_1f.3.analog-stereo" (or similar)

# List available sinks
pactl list short sinks
# expected: at least one real hardware sink 
# (e.g. "alsa_output.pci-0000_00_1f.3.analog-stereo"),
# not only "auto_null"
```
## Uninstall

Script uninstalls the PulseAudio profile set up by the installer: 
- removes ALSA & CS8409 configs, blacklist files, reverts the GRUB kernel parameter `snd_intel_dspcfg.dsp_driver=1`, 
- deletes the APT pin that blocked PipeWire, and resets user services (unmasks PipeWire units, disables/stops PulseAudio).

```bash
sudo ./imac2019_audio_uninstall.sh
sudo reboot
```

## Notes

- Please review before use on production systems.
- Experimental — feedback and pull requests are welcome.

  
