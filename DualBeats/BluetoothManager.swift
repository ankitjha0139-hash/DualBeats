import Foundation
import CoreBluetooth
import Combine

class BluetoothSpeaker: ObservableObject, Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    @Published var connectionState: ConnectionState
    @Published var isSelected: Bool
    let signalStrength: Int

    enum ConnectionState {
        case disconnected, connecting, connected, failed

        var displayText: String {
            switch self {
            case .disconnected: return "Not Connected"
            case .connecting:   return "Connecting..."
            case .connected:    return "Connected"
            case .failed:       return "Failed — Retry"
            }
        }
    }

    init(peripheral: CBPeripheral, rssi: Int) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.connectionState = .disconnected
        self.isSelected = false
        self.signalStrength = rssi
    }

    // Display name — show real device name, clean up BT prefixes
    var displayName: String {
        let raw = peripheral.name ?? "Unknown Speaker"
        return raw
            .replacingOccurrences(of: "LE-", with: "")
            .replacingOccurrences(of: "BLE-", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    var rawName: String { peripheral.name ?? "" }
}

class BluetoothManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    private var audioManager: AudioManager
    static let maxSpeakers = 5

    @Published var discoveredSpeakers: [BluetoothSpeaker] = []
    @Published var isScanning: Bool = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var statusMessage: String = "Ready to scan"
    @Published var isPlayingOnAll: Bool = false

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    // MARK: - Scanning

    func retrieveAlreadyConnectedSpeakers() {
        discoveredSpeakers.removeAll()
        let audioServiceUUID = CBUUID(string: "0000110B-0000-1000-8000-00805F9B34FB")
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [audioServiceUUID])
        for peripheral in connected {
            guard isSpeaker(peripheral.name) else { continue }
            let speaker = BluetoothSpeaker(peripheral: peripheral, rssi: -50)
            speaker.connectionState = .connected
            discoveredSpeakers.append(speaker)
            print("✅ Already connected: \(peripheral.name ?? "unknown")")
        }
        startScan()
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth is not available"
            return
        }
        isScanning = true
        statusMessage = "Scanning for speakers..."
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        statusMessage = discoveredSpeakers.isEmpty
            ? "No speakers found. Power them on and scan again."
            : "\(discoveredSpeakers.count) speaker(s) found — select up to \(BluetoothManager.maxSpeakers)"
    }

    // MARK: - Selection

    func toggleSelection(_ speaker: BluetoothSpeaker) {
        if speaker.isSelected {
            speaker.isSelected = false
        } else if selectedCount < BluetoothManager.maxSpeakers {
            speaker.isSelected = true
        } else {
            statusMessage = "Maximum \(BluetoothManager.maxSpeakers) speakers at once"
        }
    }

    // MARK: - Connect & Play (one flow)

    func connectSelectedAndPlay() {
        let selected = discoveredSpeakers.filter { $0.isSelected }
        guard selected.count >= 2 else {
            statusMessage = "Select at least 2 speakers"
            return
        }

        let needsConnection = selected.filter { $0.connectionState != .connected }

        if needsConnection.isEmpty {
            setupMultiOutput(for: selected)
            return
        }

        statusMessage = "Connecting \(needsConnection.count) speaker(s)..."
        for speaker in needsConnection {
            speaker.connectionState = .connecting
            connectAtSystemLevel(speaker)
        }
        waitForAllConnected(selected: selected, attempts: 0)
    }

    private func connectAtSystemLevel(_ speaker: BluetoothSpeaker) {
        // Check classic audio (A2DP sink) profile
        let a2dpUUID  = CBUUID(string: "0000110B-0000-1000-8000-00805F9B34FB")
        // Check HFP profile too
        let hfpUUID   = CBUUID(string: "0000111E-0000-1000-8000-00805F9B34FB")

        let alreadyConnected = centralManager.retrieveConnectedPeripherals(withServices: [a2dpUUID, hfpUUID])
        if alreadyConnected.contains(where: { $0.identifier == speaker.peripheral.identifier }) {
            speaker.connectionState = .connected
            print("✅ Already connected via classic BT: \(speaker.displayName)")
            return
        }
        // Connect with options that prefer classic BT audio over BLE
        centralManager.connect(speaker.peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey:    true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
        print("🔗 Connecting: \(speaker.displayName)")
    }

    private func waitForAllConnected(selected: [BluetoothSpeaker], attempts: Int) {
        guard attempts < 20 else {
            statusMessage = "Connection timed out — try again"
            return
        }
        if selected.contains(where: { $0.connectionState == .failed }) {
            statusMessage = "A speaker failed to connect — retry"
            return
        }
        if selected.allSatisfy({ $0.connectionState == .connected }) {
            setupMultiOutput(for: selected)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitForAllConnected(selected: selected, attempts: attempts + 1)
        }
    }

    private func setupMultiOutput(for speakers: [BluetoothSpeaker]) {
        statusMessage = "Setting up multi-output..."
        let rawNames = speakers.map { $0.rawName }
        let uuids = speakers.map { $0.id.uuidString }
        audioManager.createMultiOutputDevice(speakerRawNames: rawNames, speakerUIDs: uuids) { [weak self] success, message in
            DispatchQueue.main.async {
                self?.isPlayingOnAll = success
                self?.statusMessage = message
            }
        }
    }

    func stopMultiOutput() {
        audioManager.restoreDefaultOutput()
        isPlayingOnAll = false
        statusMessage = "Restored default audio output"
    }

    func disconnectSpeaker(_ speaker: BluetoothSpeaker) {
        centralManager.cancelPeripheralConnection(speaker.peripheral)
        speaker.connectionState = .disconnected
        speaker.isSelected = false
    }

    // MARK: - Helpers

    var selectedSpeakers: [BluetoothSpeaker] { discoveredSpeakers.filter { $0.isSelected } }
    var selectedCount: Int { selectedSpeakers.count }

    private func isDuplicate(_ peripheral: CBPeripheral) -> Bool {
        if discoveredSpeakers.contains(where: { $0.id == peripheral.identifier }) { return true }
        // Deduplicate by cleaned display name too
        let incomingName = (peripheral.name ?? "")
            .replacingOccurrences(of: "LE-", with: "")
            .replacingOccurrences(of: "BLE-", with: "")
            .trimmingCharacters(in: .whitespaces)
        return !incomingName.isEmpty && discoveredSpeakers.contains(where: {
            $0.displayName.lowercased() == incomingName.lowercased()
        })
    }

    private func isSpeaker(_ name: String?) -> Bool {
        guard let name = name, !name.isEmpty else { return false }
        let lower = name.lowercased()
        let exclude = ["airpods", "mouse", "keyboard", "trackpad",
                       "magic", "iphone", "ipad", "macbook", "watch", "pencil"]
        return !exclude.contains(where: { lower.contains($0) })
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        switch central.state {
        case .poweredOn:    statusMessage = "Bluetooth ready — tap Scan"
        case .poweredOff:   statusMessage = "Please turn on Bluetooth"
        case .unauthorized: statusMessage = "Bluetooth permission denied"
        default:            statusMessage = "Bluetooth initializing..."
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !isDuplicate(peripheral), isSpeaker(peripheral.name) else { return }
        let speaker = BluetoothSpeaker(peripheral: peripheral, rssi: RSSI.intValue)
        discoveredSpeakers.append(speaker)
        print("🔊 Found: '\(peripheral.name ?? "unnamed")' | UUID: \(peripheral.identifier)")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let speaker = discoveredSpeakers.first(where: { $0.id == peripheral.identifier }) {
            speaker.connectionState = .connected
            print("✅ Connected: \(peripheral.name ?? "")")
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let speaker = discoveredSpeakers.first(where: { $0.id == peripheral.identifier }) {
            speaker.connectionState = .failed
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let speaker = discoveredSpeakers.first(where: { $0.id == peripheral.identifier }) {
            speaker.connectionState = .disconnected
            speaker.isSelected = false
            if isPlayingOnAll { statusMessage = "\(speaker.displayName) disconnected" }
        }
    }
}
