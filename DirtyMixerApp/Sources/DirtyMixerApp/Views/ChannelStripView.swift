import SwiftUI

struct ChannelStripView: View {
    @ObservedObject var channel: ChannelState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CH\(channel.id)")
                    .font(.headline.monospaced())
                Spacer()
                Circle()
                    .fill(channel.isActive ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
            }

            Toggle("Input A", isOn: $channel.inputAEnabled)
                .toggleStyle(.switch)

            Toggle("Input B", isOn: $channel.inputBEnabled)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                Text("Mix")
                    .font(.subheadline)
                Slider(value: $channel.mix, in: 0...255, step: 1)
                    .tint(.orange)
                HStack {
                    Text("0")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(channel.mix))")
                        .font(.title3.monospacedDigit())
                        .fontWeight(.semibold)
                    Spacer()
                    Text("255")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.13, green: 0.13, blue: 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
