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
            HStack(spacing: 4) {
                Image(systemName: state.mode.menuBarSystemImage)
                Text("SharePods")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
