import SwiftUI

struct PickerView: View {
    let picker: Picker
    let settings: Settings

    var body: some View {
        Text("‹ \(picker.currentDisplayName) ›")
            .font(.system(size: settings.fontSize, design: .monospaced))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
    }
}
