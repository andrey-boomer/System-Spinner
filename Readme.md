![System Spinner](Pictures/icon.jpg)
# System Spinner

System Spinner provides macOS system information in status bar. Minimal, small and light!

[![Downloads](https://img.shields.io/github/downloads/andrey-lysikov/System-Spinner/total)](https://github.com/andrey-lysikov/System-Spinner/releases/latest)
[![Release](https://img.shields.io/github/v/release/andrey-lysikov/System-Spinner)](https://github.com/andrey-lysikov/System-Spinner/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg?style=flat)](https://github.com/andrey-lysikov/System-Spinner/releases/latest)

This is the macOS version, if you are looking for Windows go to [System Spinner x64](https://github.com/andrey-lysikov/System-Spinner-x64)

## Features

- Spinner speed follows the CPU and GPU load, whichever is higher
- Show the load in the status bar
- Animated and static spinners, with overlay effects
- Audio and brightness control for external monitors (over HDMI/DVI/USB-C with the standard media keys)
- Keyboard backlight control on F5/F6
- Custom OSD for macOS Tahoe for volume and brightness control
- Custom adjustment steps (more accurate volume and brightness control)
- Top CPU/MEM processes in popup window
- Memory statistics with swap
- Network utilisation and external ip address (uses checkip.dyndns.org, you can turn off showing external ip)
- SMC information for CPU temp and fan
- Full macOS 26 Tahoe Liquid Glass support
- Localization (English, Arabic, Chinese, French, German, Italian, Japanese, Russian)

*WARNING: The application is not officially signed, you will need to allow it to run in "Settings" -> "Security" when you first launch it.*

## Screenshots

<p align="center">
  <img src="Pictures/main_window.jpg" height="380">
  <img src="Pictures/spin_menu.jpg" height="380">
  <img src="Pictures/main_detail_window.jpg" height="380">
</p>

## Tech
Written in Swift 6, Apple Silicon only, for macOS 26 Tahoe


Thanks for language translate:
- Japanese by [@1024jp](https://github.com/1024jp)

Based on: [Menubar_runcat](https://github.com/Kyome22/menubar_runcat), [Stats](https://github.com/exelban/stats), [MonitorControl](https://github.com/MonitorControl/MonitorControl), [Better-osd](https://github.com/zmlabs/better-osd), [Mos](https://github.com/Caldis/Mos)
