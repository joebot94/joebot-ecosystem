import SwiftUI

struct PresetBarView: View {
    @ObservedObject var boardState: BoardState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(boardState.presetSlots) { slot in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(slot.name)
                            .font(.caption)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Button("Recall") {
                                boardState.recallPreset(slot: slot.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!slot.hasData)

                            Button("Save") {
                                boardState.savePreset(slot: slot.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(10)
                    .frame(width: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.17, green: 0.17, blue: 0.19))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(slot.hasData ? Color.orange.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }
}
