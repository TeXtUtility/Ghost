import Foundation
import Observation

@MainActor
@Observable
final class OverlayState {
    enum Mode: Equatable { case picker, typing }
    var mode: Mode = .picker

    /// Session-only opacity override. When non-nil, this is what the overlay
    /// renders at instead of the persisted Settings.opacity. Resets to nil
    /// every time the app launches, so dimming the overlay with the hotkey
    /// is intentionally a per-session affordance and never permanently hides
    /// it via stale UserDefaults.
    var sessionOpacity: Double?
}
