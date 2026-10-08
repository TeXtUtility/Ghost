import Foundation
import Observation
import AppKit

enum OverlayCorner: String, CaseIterable, Codable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var next: OverlayCorner {
        let all = OverlayCorner.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

@MainActor
@Observable
final class Settings {
    var corner: OverlayCorner {
        didSet { ud.set(corner.rawValue, forKey: K.corner) }
    }
    var fontSize: Double {
        didSet { ud.set(fontSize, forKey: K.fontSize) }
    }
    var opacity: Double {
        didSet { ud.set(opacity, forKey: K.opacity) }
    }
    var windowChars: Int {
        didSet { ud.set(windowChars, forKey: K.windowChars) }
    }
    /// Jump ahead to where the user is when they go off script (see TypingEngine.autoSkip).
    var autoSkip: Bool {
        didSet { ud.set(autoSkip, forKey: K.autoSkip) }
    }

    private let ud = UserDefaults.standard

    private enum K {
        static let corner = "ghost.corner"
        static let fontSize = "ghost.fontSize"
        static let opacity = "ghost.opacity"
        static let windowChars = "ghost.windowChars"
        static let autoSkip = "ghost.autoSkip"
    }

    init() {
        self.corner = OverlayCorner(rawValue: ud.string(forKey: K.corner) ?? "") ?? .bottomRight
        let storedSize = ud.double(forKey: K.fontSize)
        self.fontSize = storedSize > 0 ? storedSize : 11
        let storedOpacity = ud.double(forKey: K.opacity)
        self.opacity = storedOpacity > 0 ? storedOpacity : 0.85
        let storedChars = ud.integer(forKey: K.windowChars)
        self.windowChars = storedChars > 0 ? storedChars : 18
        self.autoSkip = ud.object(forKey: K.autoSkip) as? Bool ?? true
    }
}
