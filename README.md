# 🔊 DualBeats

**Play audio through multiple Bluetooth speakers simultaneously on macOS — regardless of brand.**

DualBeats is a lightweight macOS menu bar app that lets you stream the same audio to multiple Bluetooth speakers at once, with a single master volume control. It works around a longstanding macOS limitation where audio can only be routed to one Bluetooth output at a time.

Built natively in Swift using CoreAudio and CoreBluetooth.

---

## The Problem

macOS (and iOS) only let you play audio through **one Bluetooth speaker at a time**. If you own speakers from different brands — say a Beats Pill and a Marshall Stanmore — there's no built-in way to play music through both simultaneously. Apple's AirPlay 2 multi-room only works with AirPlay-certified speakers, which most Bluetooth speakers aren't.

DualBeats solves this.

---

## What It Does

- 🔍 **Scans** for nearby Bluetooth speakers of any brand
- ✅ **Select** up to 5 speakers with a simple checkbox interface
- 🔗 **One-tap Connect & Play** — connects all selected speakers and routes audio to all of them at once
- 🎚️ **Master volume slider** — control the volume of all connected speakers together
- 🔇 **Mute** toggle
- 🎵 Works with **any audio source** — Spotify, Apple Music, YouTube, system sounds, anything

---

## How It Works

DualBeats combines two of Apple's low-level frameworks:

### CoreBluetooth
Discovers and connects to Bluetooth speakers. The app detects speakers already connected at the system level and handles fresh connections, working around the BLE-vs-classic-audio profile differences that cause speakers to sometimes register inconsistently.

### CoreAudio
The core trick is creating an **aggregate audio device** programmatically (the same mechanism behind macOS's "Multi-Output Device" in Audio MIDI Setup) with the `kAudioAggregateDeviceIsStackedKey` flag set to `true`. This puts the device into mirror mode, duplicating the audio stream to all sub-devices simultaneously. The app then sets this aggregate as both the default output and default system output device.

Volume is controlled via `AudioHardwareServiceSetPropertyData` using the `VirtualMasterVolume` property targeted directly at the aggregate device.

```
Bluetooth Scan  ─┐
                 ├─→  Match BT peripherals to CoreAudio devices
CoreAudio Query ─┘            │
                              ▼
              Create stacked aggregate device
                              │
                              ▼
        Set as default output + system output
                              │
                              ▼
            Audio plays on all speakers in sync
```

---

## Tech Stack

- **Swift 5** + **SwiftUI** for the interface
- **CoreAudio** / **AudioToolbox** for aggregate device creation and volume control
- **CoreBluetooth** for device discovery and connection
- **AppKit** (`NSStatusItem`) for the menu bar integration
- No third-party dependencies

---

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later (to build)
- Two or more Bluetooth speakers

---

## Building & Running

1. Clone the repo:
   ```bash
   git clone https://github.com/YOUR_USERNAME/DualBeats.git
   cd DualBeats
   ```
2. Open `DualBeats.xcodeproj` in Xcode
3. Select your Apple ID under **Signing & Capabilities → Team**
4. Press **⌘R** to build and run
5. Grant Bluetooth permission when prompted
6. The 🔊 icon appears in your menu bar

See [SETUP.md](SETUP.md) for detailed step-by-step instructions.

---

## Usage

1. Power on your Bluetooth speakers (pair them to your Mac once via System Settings first)
2. Click the 🔊 menu bar icon
3. Tap **Scan**
4. Tick the speakers you want to use
5. Tap **Connect & Play**
6. Play audio from any app — it comes out of all selected speakers
7. Use the master slider to control volume

---

## Known Limitations

- **Per-speaker volume** isn't possible — CoreAudio aggregate devices only expose a single master volume across all sub-devices. DualBeats provides unified master control.
- **Latency** between speakers depends on their individual Bluetooth firmware. Many speaker pairs sync perfectly; some may have a slight offset.
- Some speakers occasionally connect in BLE mode and need a quick power cycle to register as an audio output in CoreAudio.

---

## Roadmap

- [ ] Auto-connect to a saved speaker preset on launch
- [ ] Latency compensation / per-speaker delay offset
- [ ] iPhone support (Mac as an audio relay hub)
- [ ] Speaker presets / favourites

---

## License

MIT License — see [LICENSE](LICENSE)

---

## Acknowledgements

Built as a personal project to solve a real problem: playing music through a Beats Pill and a Marshall Stanmore at the same time. The CoreAudio aggregate device approach was the key breakthrough after experimenting with several methods.
