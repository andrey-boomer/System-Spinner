# Changelog

## 5.5.2

- Remap 3/4 button on Logi mouse for spaces change

## 5.5.1

- Re check external ip adress in time

## 5.5.0

- Scan SMC data on startup, no more fixed sensors
- Add diagnostic tool (look troubleshooting)
- Update OSD level, it not shown when video plaeyd on fullscreen
- Fix power usage for Air.

## 5.1.2

- Add an option for SmoothScroll (like MOS, but self-implemented) for other mice (non-Apple).
- Check switches for applicability now; if they are not applicable, they are neither shown nor applied.
- Exclude localhost IPv4/IPv6 addresses.
- Fix power usage for Air.

## 5.1.1

- Fix power text in Russian
- Now we can use static icons
- Use for spinner cpu and gpu

## 5.1.0

- Fix mute audio bug
- Return keyboard backlight controll with OSD
- Update OSD position when screen cursor changes
- Update key by lastVersionCheckTime

## 5.0.2

- Fix bugs

## 5.0.1

- Fix bugs
- Update pictures
- Add test
- Update actions for build

## 5.0.0

- Custom level indicators instead of the system ones: GPU load with the stats
  window open dropped from 70% to 8%
- Migrated to Swift 6 with complete concurrency checking
- New "Show external ip address" option — the external address lookup can be
  turned off
- Sensors and GPU load are polled only while the stats window is open
- Fixed OSD placement on its first appearance
- Fixed the empty process list on the first chart open
- Manual update check is no longer blocked by the scheduled one

## 4.7.0

- Fan readings restored
