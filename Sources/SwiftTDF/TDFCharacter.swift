// TDFCharacter.swift
// SwiftTDF — one glyph in a font.

/// One line of a ``TDFCharacter``.
///
/// Cells beyond the line's length are treated as transparent per the format
/// spec — glyphs are not required to be rectangular, so trailing empty cells
/// are simply not stored.
public struct TDFLine: Sendable, Hashable, Codable {
    /// The cells in this line, in left-to-right order. May be shorter than
    /// the parent character's ``TDFCharacter/maxWidth``; missing trailing
    /// cells render as transparent.
    public var cells: [TDFCell]
    /// `true` if this line was terminated with `&` in the source (descender).
    /// Descender lines are part of the glyph but excluded from line-height
    /// calculation so cursor positioning is consistent between letters with
    /// and without descenders.
    public var isDescender: Bool

    /// Memberwise initializer.
    ///
    /// - Parameters:
    ///   - cells: Cells in left-to-right order.
    ///   - isDescender: Whether the line is a descender line.
    public init(cells: [TDFCell] = [], isDescender: Bool = false) {
        self.cells = cells
        self.isDescender = isDescender
    }
}

/// One glyph in a ``TDFFont``.
///
/// ## Line-height vs total height
///
/// ``maxHeight`` is read from the glyph's binary header (byte 1 of the glyph)
/// and is **unreliable** for total visual extent — descender lines marked
/// with `&` in the source are not counted by the original TheDraw editor.
/// Consumers should generally use:
///
/// - `lines.count` for the total number of rendered lines.
/// - `lines.count - (descender lines)` for true line-height/advance.
///
/// ## Width
///
/// ``maxWidth`` is declared `1..30` (`0x1E`) by the spec but is not validated
/// at the type level — callers and encoders are responsible for keeping the
/// value within range. Width is not always exactly observed either: a glyph
/// may contain shorter lines that end with `0x0D` before reaching maxWidth.
public struct TDFCharacter: Sendable, Hashable, Codable {
    /// Maximum width in cells. Spec range is `1..30`; not enforced at the
    /// type level.
    public var maxWidth: UInt8
    /// Maximum height in lines, as declared by the glyph header. Spec range
    /// is `1..12`. **Unreliable for total visual height** — see the type
    /// documentation.
    public var maxHeight: UInt8
    /// The per-line content of the glyph, top to bottom. May contain fewer
    /// than ``maxHeight`` entries when the glyph terminated early.
    public var lines: [TDFLine]

    /// Memberwise initializer.
    ///
    /// - Parameters:
    ///   - maxWidth: Declared width in cells (`1...30`).
    ///   - maxHeight: Declared height in lines, excluding descenders (`1...12`).
    ///   - lines: Glyph content, top to bottom.
    public init(maxWidth: UInt8, maxHeight: UInt8, lines: [TDFLine] = []) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.lines = lines
    }

    /// A 1x1 placeholder glyph with no line content. Useful as a sentinel
    /// when constructing a font from scratch.
    public static let empty = TDFCharacter(maxWidth: 1, maxHeight: 1, lines: [])
}
