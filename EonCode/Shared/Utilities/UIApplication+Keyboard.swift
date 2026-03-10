#if os(iOS)
import UIKit
import SwiftUI

// MARK: - UIApplication Keyboard Dismiss
// Global helper for dismissing the keyboard programmatically on iOS.

extension UIApplication {
    /// Dismiss the software keyboard.
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder),
                   to: nil, from: nil, for: nil)
    }
}

// MARK: - View Modifiers

/// Dismisses the keyboard when the user taps anywhere outside a text field.
struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                UIApplication.shared.dismissKeyboard()
            }
    }
}

/// Dismisses the keyboard when the user begins dragging.
struct DismissKeyboardOnDrag: ViewModifier {
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in
                        UIApplication.shared.dismissKeyboard()
                    }
            )
    }
}

extension View {
    /// Adds a tap gesture that dismisses the keyboard.
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTap())
    }

    /// Adds a drag gesture that dismisses the keyboard.
    func dismissKeyboardOnDrag() -> some View {
        modifier(DismissKeyboardOnDrag())
    }
}

#endif
