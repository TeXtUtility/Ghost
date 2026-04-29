import Foundation
import Observation

@MainActor
@Observable
final class OverlayState {
    enum Mode: Equatable { case picker, typing }
    var mode: Mode = .picker
}
