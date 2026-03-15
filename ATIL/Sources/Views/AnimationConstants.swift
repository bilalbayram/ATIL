import SwiftUI

/// Centralized animation constants for ATIL.
/// Each constant provides a reduce-motion variant:
///   - Structural animations → shortened, not removed
///   - Decorative animations → nil (instant)
enum ATILAnimation {
    // MARK: - Structural

    /// Group/category expand, disclosure sections (~250ms spring)
    static let snappy: Animation = .spring(response: 0.25, dampingFraction: 0.85)

    /// Batch bar, inspector content switch (~300ms spring)
    static let smooth: Animation = .spring(response: 0.3, dampingFraction: 0.9)

    /// List row insert/remove, footer stats (200ms ease)
    static let subtle: Animation = .easeInOut(duration: 0.2)

    // MARK: - Decorative

    /// Badge appearance, hover enter (150ms)
    static let quick: Animation = .easeOut(duration: 0.15)

    /// Button press down (80ms)
    static let pressed: Animation = .easeOut(duration: 0.08)

    /// Button press release (200ms bouncy spring)
    static let released: Animation = .spring(response: 0.2, dampingFraction: 0.6)

    // MARK: - Reduce Motion Variants

    /// Shortened structural animation for reduce-motion contexts.
    static let reducedStructural: Animation = .easeOut(duration: 0.1)

    /// Returns `snappy` or a reduced variant based on reduce-motion preference.
    static func snappy(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedStructural : snappy
    }

    /// Returns `smooth` or a reduced variant based on reduce-motion preference.
    static func smooth(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedStructural : smooth
    }

    /// Returns `subtle` or nil (instant) based on reduce-motion preference.
    static func subtle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : subtle
    }

    /// Returns `quick` or nil (instant) based on reduce-motion preference.
    static func quick(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : quick
    }
}

// MARK: - Plain Pressable Button Style

/// A button style that gives `.plain`-styled buttons tactile press feedback.
/// Press: scale 0.95 + opacity 0.7 with 80ms ease-out.
/// Release: spring bounce back.
/// Reduce-motion: opacity only, no scale.
struct PlainPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.95 : 1.0))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(
                configuration.isPressed ? ATILAnimation.pressed : ATILAnimation.released,
                value: configuration.isPressed
            )
    }
}
