// TDFFontType.swift
// SwiftTDF — TheDraw font type discriminator.

/// The three TheDraw font types, stored in byte 21 of a font header.
///
/// The per-cell layout of the character data differs per type — see
/// ``TDFCell`` and ``TDFParser`` for the encoding details:
///
/// - ``outline``: 1 byte per cell, a placeholder letter (`A`…`Q`) that the
///   renderer substitutes with a box-drawing character from the selected
///   ``TDFOutlineStyle``.
/// - ``block``: 1 byte per cell, the raw CP437 character code.
/// - ``color``: 2 bytes per cell, CP437 code followed by a PC attribute byte.
public enum TDFFontType: UInt8, Sendable, CaseIterable, Codable {
    /// Outline font (`0x00`).
    case outline = 0x00
    /// Block font (`0x01`).
    case block = 0x01
    /// Color font (`0x02`).
    case color = 0x02
}
