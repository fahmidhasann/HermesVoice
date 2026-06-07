import SwiftUI

/// Live capture waveform. Bars are filled with the warm amber gradient and
/// fade toward the edges so the energy reads as centred, sitting on a soft
/// amber wash. Driven entirely by `viewModel.audioLevel`.
struct WaveformView: View {
    @ObservedObject var viewModel: OverlayViewModel
    private let barCount = 32
    @State private var bars: [CGFloat] = Array(repeating: 0.02, count: 32)

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<bars.count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Theme.Gradients.accent)
                    .frame(width: 3, height: max(3, bars[index] * 34))
                    .opacity(edgeFade(index))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Colors.accentSoft.opacity(0.5))
        )
        .onChange(of: viewModel.audioLevel) { _, newLevel in
            withAnimation(.linear(duration: 0.08)) {
                bars.removeFirst()
                bars.append(newLevel)
            }
        }
    }

    /// Bars near the two ends sit a little quieter so the form feels centred.
    private func edgeFade(_ index: Int) -> Double {
        let mid = Double(barCount - 1) / 2
        let dist = abs(Double(index) - mid) / mid     // 0 at centre → 1 at edge
        return 0.55 + 0.45 * (1 - dist)               // 1.0 centre → 0.55 edge
    }
}
