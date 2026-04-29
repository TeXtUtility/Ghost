import SwiftUI

struct ProgressRingView: View {
    let progress: Double
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.25), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.12), value: progress)
        }
        .frame(width: diameter, height: diameter)
    }
}
