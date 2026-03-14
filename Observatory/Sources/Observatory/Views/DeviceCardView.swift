import JoebotSDK
import SwiftUI

struct DeviceCardView: View {
    let info: NexusClientInfo
    var useLiquidGlass: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(info.clientId)
                    .font(.headline.monospaced())
                    .foregroundStyle(.white)
                Spacer()
                Circle()
                    .fill(info.online ? Color.green : Color.red)
                    .frame(width: 11, height: 11)
            }

            Text(info.clientType)
                .font(.caption)
                .foregroundStyle(.orange.opacity(0.9))

            Text(info.stateSummary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let lastSeen = info.lastSeen {
                Text("Last seen: \(lastSeen)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 8)

            Button("Open App") {
                print("[Observatory] Open App tapped for \(info.clientId)")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(14)
        .frame(minHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    useLiquidGlass
                        ? AnyShapeStyle(.regularMaterial)
                        : AnyShapeStyle(
                            info.online ? Color(red: 0.16, green: 0.16, blue: 0.20) : Color(red: 0.20, green: 0.20, blue: 0.20)
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(info.online ? Color.orange.opacity(useLiquidGlass ? 0.85 : 0.7) : Color.gray.opacity(useLiquidGlass ? 0.8 : 0.65), lineWidth: 1)
        )
    }
}
