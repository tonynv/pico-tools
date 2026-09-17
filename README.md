<div align="center">

# 〰️ pico-tools

### Linux helper tools for PicoScope Automotive

**Install, configure and verify a PicoScope 4225A on Ubuntu with a single command.**

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![PicoScope](https://img.shields.io/badge/PicoScope-4225A-0072CE?style=for-the-badge)](https://www.picoauto.com/)
[![Python](https://img.shields.io/badge/Python-3-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Shell](https://img.shields.io/badge/Bash-scripts-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](#-quick-start)

[Quick start](#-quick-start) •
[What gets installed](#-what-gets-installed) •
[Uninstall](#-uninstall) •
[Troubleshooting](#-troubleshooting) •
[Video](#-watch-the-video)

</div>

---

## 📖 About

This repository contains helper tools that make it easy to **install and configure a PicoScope on Linux**. They are built and tested specifically for the **PicoScope 4225A** two-channel automotive oscilloscope, which uses Pico's `ps4000a` driver.

This repo accompanies a YouTube walkthrough of the full install. You can follow along with the video, or run the scripts yourself.

> [!NOTE]
> These are community tools and are **not affiliated with or endorsed by Pico Technology**. Other PicoScope models may work, but only the 4225A is tested.

## ✨ Features

|   | Feature | Description |
|---|---------|-------------|
| 🚀 | **One-command setup** | Updates Ubuntu, adds the Pico repository, installs PicoScope 7, drivers and Python libraries |
| 🔁 | **Idempotent** | Safe to run again at any time. Steps that are already done are skipped |
| 🧹 | **Clean removal** | Removes everything the setup added, and only that |
| 🔌 | **No sudo for the scope** | Installs a USB `udev` rule so your user can access the scope |
| 🐍 | **Python ready** | Creates a virtual environment with the official PicoSDK wrappers, numpy and matplotlib |
| 📈 | **Channel test** | Captures from Channel A and B and reports min / max / mean voltage |

## 🧰 Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Ubuntu 24.04 LTS (64-bit, `amd64`) |
| **Hardware** | PicoScope 4225A connected over USB |
| **Access** | A user account with `sudo` rights |
| **Network** | Internet access to reach `labs.picotech.com` and GitHub |

## 🚀 Quick start

```bash
git clone https://github.com/tonynv/pico-tools.git
cd pico-tools
./setup_pico_tools.sh
```

Then **close PicoScope 7**, connect a test lead and run:

```bash
source ~/picoscope-env/bin/activate
python tools/test_channels.py
```

## 📦 What gets installed

```mermaid
flowchart LR
    A[🐧 Ubuntu update<br/>& prerequisites] --> B[🔑 Pico apt<br/>repository]
    B --> C[📺 PicoScope 7<br/>& ps4000a driver]
    C --> D[🔌 USB udev<br/>rule]
    D --> E[🐍 Python venv<br/>& PicoSDK]
    E --> F[✅ Verify]
```

| Component | Location |
|-----------|----------|
| Pico signing key | `/usr/share/keyrings/picotech-archive-keyring.gpg` |
| Pico apt repository | `/etc/apt/sources.list.d/picoscope7.list` |
| PicoScope 7 + drivers | `picoscope`, `libps4000a`, `libpicoipp` packages (`/opt/picoscope`) |
| USB permissions | `/etc/udev/rules.d/95-pico.rules` |
| Python environment | `~/picoscope-env` |

## 🗂️ Repository layout

```text
pico-tools/
├── setup_pico_tools.sh     # Install and configure everything
├── remove_pico_tools.sh    # Undo everything setup installed
├── lib/
│   └── ui.sh               # Shared terminal styling for the scripts
└── tools/
    └── test_channels.py    # Quick Channel A / B capture test
```

## 📈 Testing the scope

| Lead connected to | Expected result |
|-------------------|-----------------|
| Nothing | About `0 V` on both channels |
| 1.5 V AA battery (`--range 5V`) | About `1.5 V` |
| 12 V car battery | About `12.6 V` |

```bash
python tools/test_channels.py --range 5V   # smaller range for low voltages
python tools/test_channels.py --plot       # also save capture.png
```

> [!IMPORTANT]
> Only one program can use the scope at a time. **Close PicoScope 7** before running Python scripts.

## 🧹 Uninstall

```bash
./remove_pico_tools.sh                 # remove everything (asks first)
./remove_pico_tools.sh --python-only   # keep PicoScope 7, remove the Python env
./remove_pico_tools.sh --yes           # no confirmation prompt
```

## 🛠️ Troubleshooting

<details>
<summary><b>Script says "Could not open scope"</b></summary>

- Make sure PicoScope 7 is closed.
- Check that the scope appears on USB: `lsusb | grep 0ce9`
- Unplug the scope and plug it back in, so the `udev` rule applies.
</details>

<details>
<summary><b>PicoScope 7 shows "Demo" instead of the 4225A</b></summary>

- Try a different USB port or cable.
- Re-run `./setup_pico_tools.sh`. It will fix any missing pieces.
</details>

<details>
<summary><b>Python cannot find <code>libps4000a</code></b></summary>

Re-run `./setup_pico_tools.sh`. It registers `/opt/picoscope/lib` with the system linker.
</details>

## 🎬 Watch the video

📺 **Full install walkthrough on YouTube: coming soon.**

<!-- Replace with the video link once published -->

---

<div align="center">

Made for the garage 🔧 by [tonynv](https://github.com/tonynv)

</div>
