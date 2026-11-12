import SwiftUI

extension Color {
    /// Sip's tint. A system colour, so it adapts to light, dark and increased contrast.
    static let water = Color.blue
}

extension ShapeStyle where Self == Color {
    static var water: Color { .water }
}
