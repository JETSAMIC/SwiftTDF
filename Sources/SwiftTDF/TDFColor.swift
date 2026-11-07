// TDFColor.swift
// SwiftTDF — the 16-color EGA palette referenced by color-font attribute bytes.

/// The 16-color PC text-mode (EGA/VGA) palette used by TheDraw color fonts.
///
/// Indices are referenced by ``TDFAttribute/foreground`` (`0...15`) and
/// ``TDFAttribute/background`` (`0...7`). RGB values are the canonical
/// IBM EGA/VGA text-mode palette (with brown as `#AA5500`).
public enum TDFColor {
    /// Human-readable color names indexed by palette position.
    public static let names: [String] = [
        "Black", "Blue", "Green", "Cyan",
        "Red", "Magenta", "Brown", "Light Gray",
        "Dark Gray", "Bright Blue", "Bright Green", "Bright Cyan",
        "Bright Red", "Bright Magenta", "Yellow", "White",
    ]

    /// 8-bit-per-channel RGB triples indexed by palette position.
    public static let rgb: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (0,0,0), (0,0,170), (0,170,0), (0,170,170),
        (170,0,0), (170,0,170), (170,85,0), (170,170,170),
        (85,85,85), (85,85,255), (85,255,85), (85,255,255),
        (255,85,85), (255,85,255), (255,255,85), (255,255,255),
    ]

    /// Returns the human-readable name for a palette index.
    ///
    /// - Parameter index: Palette index.
    /// - Returns: The color name, or `"Unknown"` for indices outside `0...15`.
    public static func name(_ index: Int) -> String {
        guard (0..<16).contains(index) else { return "Unknown" }
        return names[index]
    }
}
