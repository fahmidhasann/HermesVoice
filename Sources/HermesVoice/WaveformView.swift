import SwiftUI

struct WaveformView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var bars: [CGFloat] = Array(repeating: 0.02, count: 32)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<bars.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.Colors.accent.opacity(0.5))
                    .frame(width: 3, height: max(3, bars[index] * 32))
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .background(Theme.Colors.textPrimary.opacity(0.03))
        .cornerRadius(10)
        .onChange(of: viewModel.audioLevel) { _, newLevel in
            withAnimation(.linear(duration: 0.08)) {
                bars.removeFirst()
                bars.append(newLevel)
            }
        }
    }
}
