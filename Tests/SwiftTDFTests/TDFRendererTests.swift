// TDFRendererTests.swift
// SwiftTDF — verify the renderer's per-cell translation rules for each
// font type.

import XCTest
@testable import SwiftTDF

final class TDFRendererTests: XCTestCase {

    // MARK: - Outline-font cells

    /// An outline cell containing letter 'A' (0x41) should translate to
    /// CP437 0xCD (double horizontal beam).
    func testOutlineCellLetterATranslatesToCP437DoubleHorizontal() {
        let glyph = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [TDFCell(code: 0x41)])]
        )
        let grid = TDFRenderer.render(glyph, type: .outline)
        XCTAssertEqual(grid.first?.first?.code, 0xCD)
    }

    /// An outline cell containing 'O' (0x4F) must set isHardSpace=true.
    ///
    /// Changed during the production audit: this test used to expect CP437
    /// 0xF7 ('≈'). That is only how the TDFONTS.EXE *editor* visualises a
    /// hard space (Roy/SAC's table, still exposed as
    /// `TDFOutlineGlyphs.render`). TheDraw's display renderer — and every
    /// one of its 19 outline styles — draws the hard space as an opaque
    /// blank, which is what `TDFRenderer` now produces.
    func testOutlineCellLetterOIsHardSpace() {
        let glyph = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [TDFCell(code: 0x4F)])]
        )
        let grid = TDFRenderer.render(glyph, type: .outline)
        let cell = grid.first?.first
        XCTAssertEqual(cell?.code, 0x20, "O renders as an opaque blank")
        XCTAssertEqual(cell?.isHardSpace, true)
        XCTAssertEqual(cell?.isFiller, false)
    }

    /// An outline cell containing '@' (0x40) must set isFiller=true.
    func testOutlineCellAtSignIsFiller() {
        let glyph = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [TDFCell(code: 0x40)])]
        )
        let grid = TDFRenderer.render(glyph, type: .outline)
        let cell = grid.first?.first
        XCTAssertEqual(cell?.isFiller, true)
        XCTAssertEqual(cell?.isHardSpace, false)
    }

    // MARK: - Color-font cells

    /// A color cell with attribute byte 0x00 (BLACK ON BLACK) must render
    /// with fg=0 and bg=0 — both colors are legal, and the renderer must
    /// not silently substitute the default.
    func testColorCellBlackOnBlackRenders() {
        let glyph = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [
                TDFCell(code: 0xB0, attribute: TDFAttribute(rawByte: 0x00))
            ])]
        )
        let grid = TDFRenderer.render(glyph, type: .color)
        let cell = grid.first?.first
        XCTAssertEqual(cell?.code, 0xB0)
        XCTAssertEqual(cell?.foreground, 0)
        XCTAssertEqual(cell?.background, 0)
    }

    /// A color cell carries its own attribute and ignores the caller's
    /// `defaultAttribute`.
    func testColorCellIgnoresDefaultAttribute() {
        let glyph = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [
                TDFCell(code: 0x41, attribute: TDFAttribute(foreground: 14, background: 4))
            ])]
        )
        let grid = TDFRenderer.render(
            glyph,
            type: .color,
            defaultAttribute: TDFAttribute(foreground: 1, background: 2)
        )
        let cell = grid.first?.first
        XCTAssertEqual(cell?.foreground, 14)
        XCTAssertEqual(cell?.background, 4)
    }

    // MARK: - Block-font cells

    /// A block cell preserves its CP437 code byte verbatim and uses the
    /// supplied default attribute for color.
    func testBlockCellPreservesCodeAndUsesDefaultAttribute() {
        let glyph = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [TDFCell(code: 0xDB)])]
        )
        let grid = TDFRenderer.render(
            glyph,
            type: .block,
            defaultAttribute: TDFAttribute(foreground: 9, background: 0)
        )
        let cell = grid.first?.first
        XCTAssertEqual(cell?.code, 0xDB)
        XCTAssertEqual(cell?.foreground, 9)
        XCTAssertEqual(cell?.background, 0)
    }

    // MARK: - Multi-line shape

    /// The renderer should produce one row per source line, in order,
    /// including descender lines.
    func testRowShapeMatchesSourceLines() {
        let glyph = TDFCharacter(
            maxWidth: 3, maxHeight: 2,
            lines: [
                TDFLine(cells: [TDFCell(code: 0x41), TDFCell(code: 0x42)]),
                TDFLine(cells: [TDFCell(code: 0x43)], isDescender: true),
            ]
        )
        let grid = TDFRenderer.render(glyph, type: .outline)
        XCTAssertEqual(grid.count, 2)
        XCTAssertEqual(grid[0].count, 2)
        XCTAssertEqual(grid[1].count, 1)
    }
}
