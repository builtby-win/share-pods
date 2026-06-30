import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct SharePodsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = SharePodsState()

    var body: some Scene {
        MenuBarExtra {
            SharePodsPopover(state: state)
        } label: {
            Label("SharePods", systemImage: state.mode.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)
    }
}
