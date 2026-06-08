# DualBeats — Detailed Setup Guide

A step-by-step guide for building and running DualBeats, written for those new to Xcode.

---

## Prerequisites

- A Mac running macOS 13 (Ventura) or later
- An Apple ID (free — no paid developer account needed)
- Two or more Bluetooth speakers

---

## Step 1 — Install Xcode

1. Open the **App Store** on your Mac
2. Search for **Xcode**
3. Click **Get** then **Install** (it's free, ~8GB, takes a while)
4. Once installed, open Xcode once to let it finish setup

---

## Step 2 — Open the Project

1. Download or clone this repository
2. Double-click **DualBeats.xcodeproj**
3. Xcode opens with the project loaded

---

## Step 3 — Set Your Developer Account

1. In Xcode: **Xcode → Settings** (`⌘,`)
2. Click **Accounts**
3. Click **+** → **Apple ID** → sign in
4. Close Settings
5. Click **DualBeats** (blue icon, top of left panel)
6. Click the **DualBeats** target → **Signing & Capabilities**
7. Under **Team**, select your Apple ID

---

## Step 4 — Build and Run

1. Confirm the scheme at the top shows **DualBeats** and **My Mac**
2. Press the **▶ play button** or `⌘R`
3. When macOS asks for Bluetooth permission, click **Allow**
4. The 🔊 icon appears in your menu bar

---

## Step 5 — Pair Your Speakers (one-time)

Before using DualBeats, pair each speaker to your Mac normally:

1. Power on the speaker
2. **System Settings → Bluetooth**
3. Find the speaker under "Nearby Devices" → **Connect**
4. Repeat for each speaker

---

## Step 6 — Using DualBeats

1. Power on all speakers
2. Click the 🔊 menu bar icon
3. Tap **Scan**
4. Tick the speakers you want
5. Tap **Connect & Play**
6. Play music from any app — it plays on all selected speakers
7. Use the master slider to adjust volume

---

## Troubleshooting

**A speaker doesn't appear when scanning:**
- Make sure it's powered on and not connected to another device (like your phone)
- Toggle Bluetooth off/on on your Mac

**Only one speaker plays:**
- One speaker may have connected in BLE mode. Power it off, wait 5 seconds, power it on, and reconnect.
- Check System Settings → Sound → Output shows "DualBeats Multi-Output"

**Volume slider doesn't change anything:**
- Ensure you're playing through the DualBeats Multi-Output device (check the footer in the app)

---

## How the Code Is Organised

| File | Responsibility |
|------|---------------|
| `DualBeatsApp.swift` | App entry point, menu bar (NSStatusItem) setup |
| `BluetoothManager.swift` | Scanning, connecting, and managing Bluetooth speakers |
| `AudioManager.swift` | Creating the CoreAudio aggregate device, volume control |
| `ContentView.swift` | The SwiftUI interface shown in the menu bar popover |

---

Enjoy your music on every speaker at once! 🔊🔊
