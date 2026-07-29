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
│   ├── lab.md              # Editable lab source — edit this
│   ├── build.py            # Rebuilds index.html from lab.md
│   ├── index.html          # Generated Lab UI (open in a browser, or use serve.py)
│   ├── serve.py            # Local web server
│   └── images/             # All lab screenshots and photos
├── apps/
│   ├── install-lab-tools.sh      # One-shot installer for this lab's tools
│   ├── install-workshop-apps.sh  # Full Dark Wolf workshop provisioner
│   ├── runQGC.sh                 # QGroundControl launch helper
│   └── libfuse2.sh               # Builds libfuse2 from source (QGC fallback)
├── files/
│   ├── keys/               # SSH key pair for the 3DR Solo root account
│   ├── mavlink_2_common.lua  # Wireshark plugin for MAVLink decoding
│   ├── opensolo.words      # Wordlist for WiFi cracking (no internet needed)
│   └── solo/               # Drone firmware (squashfs, kernel, bootloader)
└── Lab Overview.pdf        # Original workshop notes (same content as the UI)
```

> **Editing the lab:** `lab/index.html` is generated. Edit `lab/lab.md`, then run
> `python3 build.py` from `lab/` to regenerate it.

---

## Tool Installation

All commands assume **Kali Linux**. Every tool the lab uses installs from one script — run it as your normal **kali** user (not root) before starting:

```bash
cd apps
chmod +x install-lab-tools.sh
./install-lab-tools.sh
```

The script is idempotent (safe to re-run) and prints a pass/fail summary at the end. **Log out and back in** afterward so Wireshark's capture-group membership takes effect. It installs:

| Tool | Provides | Used in |
|------|----------|---------|
| squashfs-tools | `unsquashfs` | UAV › Extract Firmware |
| openssh-client-ssh1 | `ssh1` | UAV › SquashFS Analysis |
| adb | `adb` | GCS › Download App |
| jadx (+ default-jdk) | `jadx-gui` | GCS › Analyze APK |
| QGroundControl | `QGroundControl.AppImage` | GCS › QGroundControl |
| cewl | `cewl` | COMMS › Crack WiFi Password |
| wifite + aircrack-ng, tshark, hcxdumptool, hcxtools | `wifite` | COMMS › Crack WiFi Password |
| Wireshark + MAVLink plugin | `wireshark` | COMMS › Sniff MAVLink |
| MAVProxy | `mavproxy.py` | COMMS › Sniff MAVLink |

QGroundControl is placed in `~/apps/QGroundControl/`; launch it with `./runQGC.sh` from there.

**Notes**
- **wifite** needs a USB WiFi adapter with monitor-mode support (included in the kit); verify with `sudo airmon-ng`.
- **Offline?** Pre-stage `QGroundControl.AppImage` into `~/apps/QGroundControl/` and use the bundled `files/opensolo.words` instead of running cewl.
- `apps/install-workshop-apps.sh` is the broader Dark Wolf workshop provisioner; `apps/install-lab-tools.sh` is the trimmed installer for just this lab.

The lab UI's **Setup** section has the same instructions.

---

## Troubleshooting

**Browser doesn't open automatically**  
Navigate to `http://localhost:8080` manually.

**Port already in use**  
Run on a different port: `python3 serve.py 9000`, then open `http://localhost:9000`.

**Images not loading**  
Make sure you're serving through `serve.py` and not opening `index.html` directly as a `file://` URL — browsers block local image loads from file paths.
