import SwiftUI

struct DeviceCard: View {
    let device: AudioOutputDevice
    var isSelected = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.systemImageName)
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(device.isConnected ? .primary : .secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }


            Text(device.status.rawValue)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(statusColor)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.blue.opacity(0.45) : Color.primary.opacity(0.08))
        }
        .opacity(device.isConnected ? 1 : 0.54)
    }

    private var subtitle: String {
        if device.isConnected {
            return "Connected · Last seen just now"
        }

        return "Last seen \(Self.relativeFormatter.localizedString(for: device.lastSeen, relativeTo: .now))"
    }

    private var statusColor: Color {
        switch device.status {
        case .connected:
            return .blue
        case .disconnected:
            return .secondary
        case .sharing:
            return .green
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        DeviceCard(
            device: AudioOutputDevice(
                uid: "00000000-0000-0000-0000-000000000001",
                name: "Winston’s AirPods Pro",
                lastSeen: .now,
                isConnected: true
            )
        )
        DeviceCard(
            device: AudioOutputDevice(
                uid: "00000000-0000-0000-0000-000000000002",
                name: "Beats Fit Pro",
                lastSeen: .now.addingTimeInterval(-3_600),
                isConnected: false
            )
        )
    }
    .padding()
    .frame(width: 360)
}
