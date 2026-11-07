// TDFCell.swift
// SwiftTDF — one cell of glyph content.

/// One cell within a ``TDFLine``.
///
/// For block and outline fonts, only ``code`` is meaningful (the format
/// stores 1 byte per cell). For color fonts, ``attribute`` carries the
/// attribute byte stored after the character byte. A `nil` attribute
/// indicates a non-color cell — it is **not** equivalent to the default
/// attribute byte (`0x07`).
///
/// ## Reserved codes
///
/// `0x00` (glyph terminator) and `0x0D` (line break) can never be stored as
/// cell content; ``TDFWriter`` rejects them. `0x26` (`&`, ``markerCode``) is
/// always a marker: a trailing `&` is folded into ``TDFLine/isDescender``
/// by the parser, and a `&` anywhere else is kept as a cell with no
/// attribute (it is written as a single byte even in color fonts).
public struct TDFCell: Sendable, Hashable, Codable {
    /// CP437 character code (block/color fonts) or outline letter code
    /// (outline fonts; see the outline glyph mapping in the spec).
    public var code: UInt8
    /// Color attribute for color-font cells; `nil` for block and outline fonts.
    public var attribute: TDFAttribute?

    /// Memberwise initializer.
    ///
    /// - Parameters:
    ///   - code: CP437 character code, or outline letter code.
    ///   - attribute: The color attribute (color fonts only).
    public init(code: UInt8, attribute: TDFAttribute? = nil) {
        self.code = code
        self.attribute = attribute
    }

    /// A transparent placeholder cell — CP437 space (`0x20`), no attribute.
    /// Used for sparse/undefined positions in non-rectangular glyphs.
    public static let empty = TDFCell(code: 0x20, attribute: nil)

    /// The `&` (`0x26`) marker byte. At the end of a line it flags a
    /// descender line; elsewhere it is a non-drawing marker.
    public static let markerCode: UInt8 = 0x26
}
