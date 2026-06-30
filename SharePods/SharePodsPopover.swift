import SwiftUI

struct SharePodsPopover: View {
    @ObservedObject var state: SharePodsState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            devicesSection
            primaryActions
        }
        .padding(18)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.mode.menuBarSystemImage)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(headerColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.mode.title)
                    .font(.headline)

                Text(state.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Devices")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if state.sortedDevices.isEmpty {
                Text("No output devices found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(state.sortedDevices) { device in
                    DeviceCard(device: device)
                }
            }
        }
    }

    private var primaryActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(primaryButtonTitle) {
                performPrimaryAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(state.mode == .idle)

            HStack(spacing: 12) {
                Toggle("Auto-share", isOn: Binding(
                    get: { state.autoShareEnabled },
                    set: { state.setAutoShareEnabled($0) }
                ))
                .toggleStyle(.switch)

                Spacer(minLength: 8)

                Button("Refresh") {
                    state.refresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var primaryButtonTitle: String {
        switch state.mode {
        case .idle:
            return "Waiting for another device"
        case .ready:
            return "Start Sharing"
        case .sharing:
            return "Stop Sharing"
        case .issue:
            return state.isSharingActive ? "Stop Sharing" : "Reset"
        }
    }

    private var headerColor: Color {
        switch state.mode {
        case .idle:
            return .secondary
        case .ready:
            return .blue
        case .sharing:
            return .green
        case .issue:
            return .orange
        }
    }

    private func performPrimaryAction() {
        switch state.mode {
        case .idle:
            break
        case .ready:
            state.startSharing()
        case .sharing:
            state.stopSharing()
        case .issue:
            if state.isSharingActive {
                state.stopSharing()
            } else {
                state.reset()
            }
        }
    }
}

#Preview {
    SharePodsPopover(state: SharePodsState())
}
