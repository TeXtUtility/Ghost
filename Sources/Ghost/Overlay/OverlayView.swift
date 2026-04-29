import SwiftUI

struct OverlayView: View {
    let state: OverlayState
    let engine: TypingEngine
    let picker: Picker
    let settings: Settings

    var body: some View {
        Group {
            switch state.mode {
            case .picker:
                PickerView(picker: picker, settings: settings)
            case .typing:
                HStack(spacing: 6) {
                    TypingStripView(engine: engine, settings: settings)
                    ProgressRingView(progress: engine.progress, diameter: settings.fontSize + 6)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            // .regularMaterial is system-vibrant: it adapts to the windows
            // behind it (light / dark / colored) and gives the overlay a
            // subtle frosted definition without being visually heavy.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            // Faint border so the overlay reads against busy backgrounds.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .opacity(settings.opacity)
        .fixedSize()
    }
}
