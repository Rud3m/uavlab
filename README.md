# Defcon — UAV Security Workshop

Hands-on workshop materials for attacking the 3DR Solo UAV platform.

---

## Quickstart

**Requirements:** Python 3 (pre-installed on Kali)

```bash
git clone https://github.com/Rud3m/uavlab.git
cd uavlab/lab
python3 serve.py
```

Your browser will open automatically at `http://localhost:8080`.  
Press **Ctrl+C** in the terminal to stop the server.

> **Custom port:** `python3 serve.py 9000`

---

## Lab Structure

The workshop is divided into three sections, shown in the left sidebar:

| Section | What you'll do |
|---------|---------------|
| **UAV** | Physically disassemble the drone, extract the microSD, copy the firmware partitions, and find credentials inside the filesystem |
| **GCS** | Pull the companion Android app off a phone via ADB, decompile it with jadx-gui, and extract hardcoded secrets |
| **COMMS** | Crack the drone's WiFi password, sniff MAVLink telemetry with Wireshark, then hijack the GCS connection from the phone |

---

## Navigating the UI

- The **left sidebar** lists every step. Click any link to jump directly to it.
- The sidebar highlights your **current position** as you scroll.
- **Green callout boxes** mark key findings and credentials to note down.
- **Amber callout boxes** are warnings or steps that require attention.
- Code blocks show exact commands to run — copy them as-is unless told otherwise.

---

## What's in this Repo

```
uavlab/
├── lab/
│   ├── index.html          # Lab UI (open this in a browser, or use serve.py)
│   ├── serve.py            # Local web server
│   └── images/             # All lab screenshots and photos
├── files/
│   ├── keys/               # SSH key pair for the 3DR Solo root account
│   ├── mavlink_2_common.lua  # Wireshark plugin for MAVLink decoding
│   ├── opensolo.words      # Wordlist for WiFi cracking (no internet needed)
│   └── solo/               # Drone firmware (squashfs, kernel, bootloader)
└── Lab Overview.pdf        # Original workshop notes (same content as the UI)
```

---

## Tool Installation

All commands assume **Kali Linux**. Run these before starting the lab. The lab UI also has a full **Setup** section with these same instructions.

### squashfs-tools
Used to extract the drone's compressed root filesystem.
```bash
sudo apt update && sudo apt install -y squashfs-tools
```

### openssh-client-ssh1
Legacy SSH client that supports the older key algorithms the 3DR Solo's SSH server requires.
```bash
sudo apt update && sudo apt install -y openssh-client-ssh1
```
> If the package isn't found, try `sudo apt install -y ssh1` and ensure your Kali repos are up to date.

### ADB (Android Debug Bridge)
Used to pull the 3DR Solo APK off the phone.
```bash
sudo apt update && sudo apt install -y adb
```
Enable **USB Debugging** on the phone first: **Settings → System → Developer Options → USB Debugging**. If Developer Options is hidden, tap **Build Number** seven times under About Phone.

### jadx-gui
APK decompiler. Used to find hardcoded credentials in the 3DR Solo app.
```bash
sudo apt update && sudo apt install -y jadx
```
> Requires Java 11+: `sudo apt install -y default-jdk`

### QGroundControl
Ground control station app for connecting to the drone over WiFi.
```bash
wget https://d176tv9ibo4jno.cloudfront.net/latest/QGroundControl.AppImage
chmod +x QGroundControl.AppImage
# Required libraries
sudo apt install -y libgstreamer1.0-dev gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad gstreamer1.0-libav libfuse2
./QGroundControl.AppImage
```
> No internet? Check the thumbdrive for a pre-downloaded AppImage.

### cewl
Scrapes a website to generate a targeted wordlist for brute-force attacks.
```bash
sudo apt update && sudo apt install -y cewl
```
> No internet during the lab? Use the pre-generated wordlist at `files/opensolo.words`.

### wifite + dependencies
Automated WPA handshake capture and cracking.
```bash
sudo apt update && sudo apt install -y wifite aircrack-ng tshark hcxdumptool hcxtools
```
> **A USB WiFi adapter that supports monitor mode is required** (included in your lab kit). Verify with `sudo airmon-ng`.

### Wireshark + MAVLink plugin
Packet analyzer with MAVLink decoding. Run from the repo root (`bh25/`):
```bash
sudo apt update && sudo apt install -y wireshark
sudo usermod -aG wireshark $USER && newgrp wireshark
mkdir -p ~/.local/lib/wireshark/plugins
cp files/mavlink_2_common.lua ~/.local/lib/wireshark/plugins/
```
Restart Wireshark after copying the plugin.

### MAVProxy
Command-line MAVLink ground station, used as a lightweight alternative to Wireshark.
```bash
sudo apt update && sudo apt install -y mavproxy
# If not in apt:
pip3 install MAVProxy --break-system-packages
```

---

## Troubleshooting

**Browser doesn't open automatically**  
Navigate to `http://localhost:8080` manually.

**Port already in use**  
Run on a different port: `python3 serve.py 9000`, then open `http://localhost:9000`.

**Images not loading**  
Make sure you're serving through `serve.py` and not opening `index.html` directly as a `file://` URL — browsers block local image loads from file paths.
