# Architecture

A technical overview of how DualBeats works under the hood.

## Overview

DualBeats is a menu bar (`NSStatusItem`) application with three core components coordinated through SwiftUI's `@EnvironmentObject` dependency injection:

```
┌─────────────────────────────────────────────┐
│                DualBeatsApp                   │
│         (AppDelegate + NSStatusItem)          │
└───────────────────┬───────────────────────────┘
                    │ injects
        ┌───────────┴────────────┐
        ▼                        ▼
┌──────────────────┐    ┌──────────────────┐
│ BluetoothManager │    │   AudioManager   │
│  (CoreBluetooth) │    │   (CoreAudio)    │
└──────────────────┘    └──────────────────┘
        │                        │
        ▼                        ▼
   Discovers &            Creates aggregate
   connects speakers      device + volume
        │                        │
        └────────┬───────────────┘
                 ▼
          ┌──────────────┐
          │ ContentView  │
          │  (SwiftUI)   │
          └──────────────┘
```

## The Core Challenge

By default, macOS routes audio to a single output device. Bluetooth's A2DP profile is point-to-point — one source, one sink. To play to multiple speakers, we need to create a virtual device that fans out a single audio stream to multiple physical outputs.

## The Solution: Aggregate Audio Devices

CoreAudio supports **aggregate devices** — virtual devices composed of multiple physical sub-devices. The macOS "Audio MIDI Setup" app exposes this as "Create Multi-Output Device". DualBeats does this programmatically.

### Key implementation detail: stacked mode

```swift
let aggregateDesc: [String: Any] = [
    kAudioAggregateDeviceNameKey: "DualBeats Multi-Output",
    kAudioAggregateDeviceUIDKey: aggregateUID,
    kAudioAggregateDeviceSubDeviceListKey: subDeviceList,
    kAudioAggregateDeviceMasterSubDeviceKey: matchedUIDs[0],
    kAudioAggregateDeviceIsPrivateKey: false,
    kAudioAggregateDeviceIsStackedKey: true   // ← critical
]
AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &aggregateID)
```

Setting `kAudioAggregateDeviceIsStackedKey` to `true` puts the aggregate into **mirror mode** — the same audio is duplicated to all sub-devices, rather than being split across channels. This was the key breakthrough; without it, audio only reaches one speaker.

### Setting both output selectors

macOS distinguishes between the default output device and the default *system* output device. Both must be set for reliable routing:

```swift
setDefaultOutputDevice(aggregateID)         // app audio
setDefaultSystemOutputDevice(aggregateID)   // system sounds
```

## Bluetooth Discovery

`BluetoothManager` uses CoreBluetooth's `CBCentralManager` to scan for peripherals. Two notable challenges were handled:

1. **Already-connected devices** — `retrieveConnectedPeripherals(withServices:)` finds speakers already connected at the OS level, which a fresh scan won't surface.

2. **BLE vs Classic profiles** — speakers may advertise under names like `STANMORE III [LE]` (Bluetooth Low Energy) versus `STANMORE III` (classic A2DP audio). Only the classic profile registers as a CoreAudio output, so the matching logic strips `[LE]` and `LE-` prefixes when correlating Bluetooth peripherals to CoreAudio devices.

## Matching Bluetooth ↔ CoreAudio

A speaker discovered via CoreBluetooth must be matched to its corresponding CoreAudio output device. Since names differ slightly between the two layers (e.g. `LE-Ankit's Pill` in Bluetooth vs `Ankit's Pill` in CoreAudio), the matcher:

1. Strips BT mode prefixes (`LE-`, `BLE-`, `[LE]`)
2. Removes possessives and short words
3. Matches remaining significant words against CoreAudio device names

This is brand-agnostic — it works for any speaker without hardcoded names.

## Volume Control

Aggregate device volume is set through the AudioHardwareService API:

```swift
var addr = AudioObjectPropertyAddress(
    mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
    mScope: kAudioDevicePropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMain)
AudioHardwareServiceSetPropertyData(deviceID, &addr, 0, nil,
    UInt32(MemoryLayout<Float>.size), &vol)
```

`VirtualMasterVolume` is what macOS uses internally for the system volume slider, and it works on aggregate devices where the raw `VolumeScalar` property does not.

## Lifecycle Management

On launch and before each new session, `cleanupStaleAggregates()` destroys any leftover `com.dualbeats.*` aggregate devices from previous runs, preventing CoreAudio device-list pollution. On stop, the previous default output is restored and the aggregate destroyed.
