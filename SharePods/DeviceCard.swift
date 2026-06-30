import SwiftUI

struct DeviceCard: View {
    let device: MockDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "airpodspro")
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
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .opacity(device.isConnected ? 1 : 0.52)
    }

    private var subtitle: String {
        guard let batteryPercent = device.batteryPercent else {
            return device.isConnected ? "Connected" : "Last seen recently"
        }

        return "Battery \(batteryPercent)%"
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
        DeviceCard(device: MockDevice.initialDevices[0])
        DeviceCard(device: MockDevice.initialDevices[1])
    }
    .padding()
    .frame(width: 360)
}
