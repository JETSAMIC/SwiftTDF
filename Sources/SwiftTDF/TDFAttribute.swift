// TDFAttribute.swift
// SwiftTDF — color attribute byte for color fonts.

/// One color attribute as stored in a color-font cell's second byte.
///
/// The on-disk encoding is the standard PC text-mode attribute byte:
/// - Bits 0–3 (`byte & 0x0F`) — foreground color index `0..15`.
/// - Bits 4–6 (`(byte >> 4) & 0x07`) — background color index `0..7`.
/// - Bit 7 (`byte & 0x80`) — blink (or, on displays in "iCE color" mode,
///   high-intensity background). TheDraw fonts rarely set it, but it is
///   preserved so that every attribute byte round-trips unchanged.
///
/// See ``TDFColor`` for the palette these indices reference.
///
/// `0x00` is a legal attribute byte (black on black) and must not be confused
/// with the glyph NUL terminator — the terminator only ever appears where a
/// cell's *character* byte would be.
public struct TDFAttribute: Sendable, Hashable, Codable {
    /// Foreground color index in the 16-color palette (`0...15`).
    public var foreground: UInt8
    /// Background color index in the palette (`0...7`).
    public var background: UInt8
    /// Bit 7 of the attribute byte: blink, or high-intensity background in
    /// iCE color mode. Interpretation is left to the consumer.
    public var blink: Bool

    /// Memberwise initializer.
    ///
    /// Callers are responsible for keeping the indices within their
    /// respective ranges; out-of-range values are masked to the encodable
    /// bits by ``rawByte``.
    ///
    /// - Parameters:
    ///   - foreground: Foreground palette index, `0...15`.
    ///   - background: Background palette index, `0...7`.
    ///   - blink: Whether bit 7 (blink / bright background) is set.
    public init(foreground: UInt8, background: UInt8, blink: Bool = false) {
        self.foreground = foreground
        self.background = background
        self.blink = blink
    }

    /// Decodes the on-disk attribute byte.
    ///
    /// - Parameter rawByte: The attribute byte exactly as stored in the file.
    public init(rawByte: UInt8) {
        self.foreground = rawByte & 0x0F
        self.background = (rawByte >> 4) & 0x07
        self.blink = rawByte & 0x80 != 0
    }

    /// The on-disk attribute byte.
    public var rawByte: UInt8 {
        (blink ? 0x80 : 0x00) | ((background & 0x07) << 4) | (foreground & 0x0F)
    }

    /// Light gray on black (`0x07`) — the default attribute used by TheDraw
    /// for newly placed cells.
    public static let defaultAttribute = TDFAttribute(foreground: 7, background: 0)
}
