// TDFRenderer.swift
// SwiftTDF — pure-data rasterizer from a ``TDFCharacter`` to a grid of
// painted cells. No SwiftUI, no AppKit/UIKit; consumers layer their own
// drawing on top of ``TDFRenderedCell``.

/// One painted cell in a rendered glyph row.
///
/// The renderer has already applied the outline-style substitution (for
/// outline fonts) and resolved attributes (block and outline fonts use the
/// caller-supplied default, color fonts use the cell's own attribute). The
/// consumer draws ``code`` (a CP437 byte) with ``foreground`` /
/// ``background`` from ``TDFColor`` — unless ``isFiller`` is `true`, in
/// which case the cell is transparent.
public struct TDFRenderedCell: Sendable, Hashable {
    /// CP437 byte to draw (already outline-substituted where applicable).
    public var code: UInt8
    /// Foreground palette index, `0...15`.
    public var foreground: UInt8
    /// Background palette index, `0...7`.
    public var background: UInt8
    /// `true` when the source cell is a non-drawing marker: the outline
    /// leading-space filler `@`, or a `&` marker in the middle of a line.
    /// The consumer should treat the cell as transparent. ``code`` is a
    /// blank (`0x20`) for these cells.
    public var isFiller: Bool
    /// `true` when the source cell is an opaque blank ("hard space"): the
    /// outline letter `O`, or the `0xFF` hard blank in block and color
    /// fonts. ``code`` is `0x20` for outline hard spaces and `0xFF` (which
    /// CP437 draws as a blank) otherwise.
    public var isHardSpace: Bool

    /// Memberwise initializer.
    ///
    /// - Parameters:
    ///   - code: CP437 byte to draw.
    ///   - foreground: Foreground palette index, `0...15`.
    ///   - background: Background palette index, `0...7`.
    ///   - isFiller: Whether the cell is transparent.
    ///   - isHardSpace: Whether the cell is an opaque blank.
    public init(
        code: UInt8,
        foreground: UInt8,
        background: UInt8,
        isFiller: Bool = false,
        isHardSpace: Bool = false
    ) {
        self.code = code
        self.foreground = foreground
        self.background = background
        self.isFiller = isFiller
        self.isHardSpace = isHardSpace
    }
}

/// Pure-data rasterizer for ``TDFCharacter``.
///
/// Namespaced as an empty `enum`; no state is shared between calls.
public enum TDFRenderer {
    /// Renders a glyph to a row-major grid of ``TDFRenderedCell``.
    ///
    /// - Parameters:
    ///   - char: The glyph to render.
    ///   - type: The parent font's type, which selects the per-cell
    ///     decoding strategy (block/color/outline).
    ///   - defaultAttribute: Colors used for block and outline fonts. Color
    ///     fonts use each cell's own attribute and fall back to this only
    ///     for cells that have none.
    ///   - outlineStyle: The TheDraw outline style used to substitute
    ///     outline placeholder letters. Ignored for block and color fonts.
    ///     Defaults to ``TDFOutlineStyle/roySAC`` (style 9).
    /// - Returns: One row per entry in `char.lines` (descender lines
    ///   included, in order). Each row holds exactly the line's stored
    ///   cells; positions beyond a row's length up to
    ///   ``TDFCharacter/maxWidth`` are transparent and not materialized.
    public static func render(
        _ char: TDFCharacter,
        type: TDFFontType,
        defaultAttribute: TDFAttribute = .defaultAttribute,
        outlineStyle: TDFOutlineStyle = .roySAC
    ) -> [[TDFRenderedCell]] {
        char.lines.map { line in
            line.cells.map {
                renderCell($0, type: type, defaultAttribute: defaultAttribute, outlineStyle: outlineStyle)
            }
        }
    }

    /// Translates a single ``TDFCell`` according to its font type.
    private static func renderCell(
        _ cell: TDFCell,
        type: TDFFontType,
        defaultAttribute: TDFAttribute,
        outlineStyle: TDFOutlineStyle
    ) -> TDFRenderedCell {
        let attribute = type == .color ? (cell.attribute ?? defaultAttribute) : defaultAttribute

        if cell.code == TDFCell.markerCode {
            return TDFRenderedCell(
                code: 0x20,
                foreground: attribute.foreground,
                background: attribute.background,
                isFiller: true
            )
        }

        switch type {
        case .block, .color:
            return TDFRenderedCell(
                code: cell.code,
                foreground: attribute.foreground,
                background: attribute.background,
                isHardSpace: cell.code == 0xFF
            )

        case .outline:
            return TDFRenderedCell(
                code: outlineStyle.substitute(cell.code),
                foreground: attribute.foreground,
                background: attribute.background,
                isFiller: TDFOutlineGlyphs.isFiller(cell.code),
                isHardSpace: cell.code == 0x4F
            )
        }
    }
}

// MARK: - Convenience

public extension TDFCharacter {
    /// Renders this glyph to a row-major grid of ``TDFRenderedCell``.
    ///
    /// Equivalent to
    /// ``TDFRenderer/render(_:type:defaultAttribute:outlineStyle:)``.
    ///
    /// - Parameters:
    ///   - type: The parent font's type.
    ///   - defaultAttribute: Colors used for block and outline fonts.
    ///   - outlineStyle: Outline style for outline fonts.
    /// - Returns: The rendered rows.
    func rendered(
        type: TDFFontType,
        defaultAttribute: TDFAttribute = .defaultAttribute,
        outlineStyle: TDFOutlineStyle = .roySAC
    ) -> [[TDFRenderedCell]] {
        TDFRenderer.render(self, type: type, defaultAttribute: defaultAttribute, outlineStyle: outlineStyle)
    }
}
