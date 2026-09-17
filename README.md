<div align="center">

# 〰️ pico-tools

### Linux helper tools for PicoScope Automotive

**Install, configure and verify a PicoScope 4225A on Ubuntu with a single command.**

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![PicoScope](https://img.shields.io/badge/PicoScope-4225A-0072CE?style=for-the-badge)](https://www.picoauto.com/)
[![PyPI](https://img.shields.io/pypi/v/pico-tools?style=for-the-badge&logo=pypi&logoColor=white&label=PyPI)](https://pypi.org/project/pico-tools/)
[![Python](https://img.shields.io/badge/Python-3.9+-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Shell](https://img.shields.io/badge/Bash-scripts-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](#-quick-start)
[![License](https://img.shields.io/badge/License-Apache_2.0-D22128?style=for-the-badge&logo=apache&logoColor=white)](LICENSE)

[Quick start](#-quick-start) •
[Python package](#-python-package) •
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
| 🚀 | **One-command setup** | Updates Ubuntu, adds the Pico repository, installs PicoScope 7 and drivers, and creates a Python environment |
| 🔁 | **Idempotent** | Safe to run again at any time. Steps that are already done are skipped |
| 🧹 | **Clean removal** | Removes everything the setup added, and only that |
| 🔌 | **No sudo for the scope** | Installs a USB `udev` rule so your user can access the scope |
| 🐍 | **pip installable** | `pip install pico-tools` gives you the `pico-tools` command and a Python API |
| 📈 | **Channel test** | `pico-tools test` captures Channel A and B and reports min / max / mean voltage |

## 🧰 Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Ubuntu 24.04 LTS (64-bit, `amd64`) |
| **Hardware** | PicoScope 4225A connected over USB |
| **Access** | A user account with `sudo` rights |
| **Python** | 3.9 or newer (Ubuntu 24.04 ships 3.12) |
| **Network** | Internet access to reach `labs.picotech.com`, GitHub and PyPI |

## 🚀 Quick start

```bash
git clone https://github.com/tonynv/pico-tools.git
cd pico-tools
./setup_pico_tools.sh
```

Then install the Python package, **close PicoScope 7**, connect a test lead and run a capture:

```bash
source ~/picoscope-env/bin/activate
pip install .            # from this repo, or: pip install pico-tools
pico-tools test
```

## 🐍 Python package

`pico-tools` is a regular Python package with a command line tool and a small API.

> [!NOTE]
> pip installs the Python side only. The native `libps4000a` driver comes from Pico's apt repository, which `./setup_pico_tools.sh` installs.

```bash
pip install pico-tools            # from PyPI
pip install "pico-tools[plot]"    # with matplotlib for --plot
pip install .                     # from a clone of this repo
```

| Command | What it does |
|---------|--------------|
| `pico-tools test` | Capture 100 ms from Channel A and B at ±20 V |
| `pico-tools test --range 5V` | Use a smaller range for low voltages |
| `pico-tools test --duration 0.5` | Capture for 500 ms |
| `pico-tools test --plot` | Also save the capture to `capture.png` |
| `pico-tools --version` | Show the installed version |

Use it from Python:

```python
from pico_tools.scope import Scope

with Scope() as scope:
    cap = scope.capture(range_name="5V", duration_s=0.1)

print(cap.volts["A"].mean())   # average voltage on Channel A
```

## 📦 What gets installed

```mermaid
flowchart LR
    A[🐧 Ubuntu update<br/>& prerequisites] --> B[🔑 Pico apt<br/>repository]
    B --> C[📺 PicoScope 7<br/>& ps4000a driver]
    C --> D[🔌 USB udev<br/>rule]
    D --> E[🐍 Python<br/>venv]
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
├── pyproject.toml          # Python package definition (PyPI: pico-tools)
├── lib/
│   └── ui.sh               # Shared terminal styling for the scripts
└── src/pico_tools/
    ├── cli.py              # pico-tools command line
    └── scope.py            # ps4000a capture API
```

## 📈 Testing the scope

| Lead connected to | Expected result |
|-------------------|-----------------|
| Nothing | About `0 V` on both channels |
| 1.5 V AA battery (`--range 5V`) | About `1.5 V` |
| 12 V car battery | About `12.6 V` |

```bash
pico-tools test --range 5V   # smaller range for low voltages
pico-tools test --plot       # also save capture.png
```

> [!IMPORTANT]
> Only one program can use the scope at a time. **Close PicoScope 7** before running `pico-tools`.

## 🧹 Uninstall

```bash
./remove_pico_tools.sh                 # remove everything (asks first)
./remove_pico_tools.sh --python-only   # keep PicoScope 7, remove the Python env
./remove_pico_tools.sh --yes           # no confirmation prompt
```

## 🛠️ Troubleshooting

<details>
<summary><b><code>pico-tools test</code> says "Could not open the scope"</b></summary>

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

## 📄 License

Licensed under the [Apache License, Version 2.0](LICENSE).

## 🎬 Watch the video

📺 **Full install walkthrough on YouTube: coming soon.**

<!-- Replace with the video link once published -->

---

<div align="center">

Made for the garage 🔧 by [tonynv](https://github.com/tonynv)

</div>
