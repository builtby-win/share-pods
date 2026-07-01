import AppKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

private final class VolumeKeyMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start(_ adjustVolume: @escaping @MainActor (Float) -> Void) {
        guard localMonitor == nil, globalMonitor == nil else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
            if let delta = Self.volumeDelta(from: event) {
                Task { @MainActor in adjustVolume(delta) }
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { event in
            guard let delta = Self.volumeDelta(from: event) else {
                return
            }

            Task { @MainActor in adjustVolume(delta) }
        }
    }

    private static func volumeDelta(from event: NSEvent) -> Float? {
        guard event.subtype.rawValue == 8 else {
            return nil
        }

        let keyCode = (event.data1 >> 16) & 0xffff
        let keyState = (event.data1 >> 8) & 0xff
        guard keyState == 0x0a else {
            return nil
        }

        switch keyCode {
        case 0:
            return 0.0625
        case 1:
            return -0.0625
        default:
            return nil
        }
    }
}

@main
struct SharePodsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state: SharePodsState
    private static let volumeKeyMonitor = VolumeKeyMonitor()

    init() {
        let state = SharePodsState()
        _state = StateObject(wrappedValue: state)
        Self.volumeKeyMonitor.start { [weak state] delta in
            state?.adjustSharedVolume(by: delta)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            SharePodsPopover(
                state: state,
                checkForUpdates: { appDelegate.checkForUpdates() }
            )
        } label: {
            Image(systemName: state.mode.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)
    }
}
