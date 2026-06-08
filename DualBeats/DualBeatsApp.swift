import SwiftUI

@main
struct DualBeatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var audioManager = AudioManager()  // init() cleans up stale aggregates
    var bluetoothManager: BluetoothManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.behavior = .transient
        popover.animates = true

        let bluetoothManager = BluetoothManager(audioManager: audioManager)
        self.bluetoothManager = bluetoothManager

        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(bluetoothManager)
                .environmentObject(audioManager)
        )
        self.popover = popover

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hifispeaker.2.fill", accessibilityDescription: "DualBeats")
            button.action = #selector(togglePopover)
            button.target = self
        }
        self.statusItem = statusItem
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
