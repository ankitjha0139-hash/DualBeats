import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            SpeakerListView()
            Divider()
            if bluetoothManager.isPlayingOnAll {
                VolumeControlView()
                Divider()
            }
            ActionBarView()
            Divider()
            FooterView()
        }
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Header

struct HeaderView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: 22))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("DualBeats")
                    .font(.system(size: 15, weight: .semibold))
                Text(bluetoothManager.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: {
                if bluetoothManager.isScanning {
                    bluetoothManager.stopScan()
                } else {
                    bluetoothManager.retrieveAlreadyConnectedSpeakers()
                }
            }) {
                HStack(spacing: 5) {
                    if bluetoothManager.isScanning {
                        ProgressView().scaleEffect(0.65).frame(width: 14, height: 14)
                        Text("Scanning")
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(bluetoothManager.isScanning
                    ? Color.accentColor.opacity(0.15)
                    : Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(bluetoothManager.bluetoothState != .poweredOn)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Speaker List

struct SpeakerListView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager

    var body: some View {
        Group {
            if bluetoothManager.discoveredSpeakers.isEmpty {
                EmptySpeakersView()
            } else {
                VStack(spacing: 0) {
                    // Instruction + capacity banner
                    HStack {
                        Image(systemName: "checkmark.square")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Select speakers (up to \(BluetoothManager.maxSpeakers)), then tap Connect & Play")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        if bluetoothManager.selectedCount > 0 {
                            Text("\(bluetoothManager.selectedCount)/\(BluetoothManager.maxSpeakers)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.05))

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(bluetoothManager.discoveredSpeakers) { speaker in
                                SpeakerRowView(speaker: speaker)
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
        }
    }
}

struct EmptySpeakersView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hifispeaker.slash.fill")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No speakers found")
                .font(.system(size: 13, weight: .medium))
            Text("Power on your speakers and tap Scan")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Speaker Row

struct SpeakerRowView: View {
    @ObservedObject var speaker: BluetoothSpeaker
    @EnvironmentObject var bluetoothManager: BluetoothManager

    var stateColor: Color {
        switch speaker.connectionState {
        case .connected:    return .green
        case .connecting:   return .orange
        case .failed:       return .red
        case .disconnected: return Color.secondary.opacity(0.4)
        }
    }

    var isDisabled: Bool {
        !speaker.isSelected && bluetoothManager.selectedCount >= BluetoothManager.maxSpeakers
    }

    var body: some View {
        Button(action: { bluetoothManager.toggleSelection(speaker) }) {
            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(speaker.isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 20, height: 20)
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            speaker.isSelected ? Color.accentColor :
                            isDisabled ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.4),
                            lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if speaker.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Speaker icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(speaker.isSelected ? 0.15 : 0.08))
                        .frame(width: 34, height: 34)
                    Image(systemName: "hifispeaker.fill")
                        .font(.system(size: 14))
                        .foregroundColor(speaker.isSelected ? .accentColor : .secondary)
                }

                // Name + status
                VStack(alignment: .leading, spacing: 3) {
                    Text(speaker.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDisabled ? .secondary : .primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(stateColor).frame(width: 6, height: 6)
                        Text(speaker.connectionState.displayText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        if speaker.connectionState == .connecting {
                            ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                        }
                    }
                }

                Spacer()

                // Signal strength
                SignalStrengthView(rssi: speaker.signalStrength)
                    .opacity(isDisabled ? 0.3 : 1.0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(speaker.isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct SignalStrengthView: View {
    let rssi: Int
    var bars: Int {
        switch rssi {
        case -55...0:      return 3
        case -70 ... -56:  return 2
        default:           return 1
        }
    }
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(bar <= bars ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: CGFloat(bar * 4 + 2))
            }
        }
    }
}

// MARK: - Volume Control (shown only when playing)

struct VolumeControlView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // Tap to mute
                Button(action: { audioManager.setMasterVolume(0) }) {
                    Image(systemName: audioManager.masterVolume == 0 ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 12))
                        .foregroundColor(audioManager.masterVolume == 0 ? .red : .secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { Double(audioManager.masterVolume) },
                        set: { audioManager.setMasterVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .accentColor(.accentColor)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                Text("\(Int(audioManager.masterVolume * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
                    .monospacedDigit()
            }

            HStack {
                Text("Master Volume — controls all speakers")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.03))
        .onAppear {
            // Sync slider to actual system volume when it appears
            audioManager.syncVolumeFromSystem()
        }
    }
}

// MARK: - Action Bar

struct ActionBarView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager

    var selectedCount: Int { bluetoothManager.selectedCount }
    var canPlay: Bool { selectedCount >= 2 }

    var buttonLabel: String {
        if bluetoothManager.isPlayingOnAll { return "Stop — Restore Default Output" }
        if selectedCount == 0 { return "Select speakers above" }
        if selectedCount == 1 { return "Select 1 more speaker" }
        return "Connect & Play on \(selectedCount) Speaker\(selectedCount > 1 ? "s" : "")"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Selected speaker pills
            if selectedCount > 0 && !bluetoothManager.isPlayingOnAll {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(bluetoothManager.selectedSpeakers) { s in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(s.connectionState == .connected ? Color.green : Color.orange)
                                    .frame(width: 5, height: 5)
                                Text(s.displayName)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 10)
            }

            // Main CTA button
            Button(action: {
                if bluetoothManager.isPlayingOnAll {
                    bluetoothManager.stopMultiOutput()
                } else if canPlay {
                    bluetoothManager.connectSelectedAndPlay()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: bluetoothManager.isPlayingOnAll ? "stop.fill" : "hifispeaker.2.fill")
                    Text(buttonLabel).lineLimit(1)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(bluetoothManager.isPlayingOnAll ? Color.red :
                            canPlay ? Color.accentColor : Color.secondary)
                .cornerRadius(9)
            }
            .buttonStyle(.plain)
            .disabled(!canPlay && !bluetoothManager.isPlayingOnAll)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("Output: \(audioManager.currentOutputDevice)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
