// TDFRoundTripTests.swift
// SwiftTDF — synthesize a font in code, encode it, parse the bytes back, and
// assert the round-trip equals the source. Covers all three font types plus
// a multi-font collection so the inter-font separator is exercised.

import XCTest
@testable import SwiftTDF

final class TDFRoundTripTests: XCTestCase {

    // MARK: - Block font

    /// Block font: 1 byte per cell, 2 glyphs of differing shape.
    func testBlockFontRoundTrip() throws {
        // '!' = 1x1 cell with CP437 code 0x41 ('A').
        let exclaim = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [TDFCell(code: 0x41)])]
        )
        // 'A' = 3x2: two rows of three cells.
        let bigA = TDFCharacter(
            maxWidth: 3, maxHeight: 2,
            lines: [
                TDFLine(cells: [TDFCell(code: 0xDB), TDFCell(code: 0xDB), TDFCell(code: 0xDB)]),
                TDFLine(cells: [TDFCell(code: 0xDB), TDFCell(code: 0x20), TDFCell(code: 0xDB)]),
            ]
        )
        let font = TDFFont(
            name: "BlockTest",
            type: .block,
            letterSpacing: 1,
            characters: [0x21: exclaim, 0x41: bigA]
        )
        let source = TDFFontCollection(fonts: [font])

        let encoded = try TDFWriter.encode(source)
        let decoded = try TDFParser.parse(encoded)

        try assertCollectionsEquivalent(source, decoded)
    }

    // MARK: - Color font (key edge case: 0x00 attribute)

    /// Color font with a single glyph whose only cell uses a 0x00 attribute
    /// byte (BLACK ON BLACK). This is the spec's key parser edge case — the
    /// 0x00 attribute must NOT be confused with the glyph NUL terminator.
    func testColorFontRoundTripWithBlackOnBlackAttribute() throws {
        // 1x1 color glyph: CP437 code 0xB0 (light shade), attribute 0x00.
        let glyph = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [
                TDFCell(code: 0xB0, attribute: TDFAttribute(rawByte: 0x00))
            ])]
        )
        let font = TDFFont(
            name: "ColorBlack",
            type: .color,
            letterSpacing: 0,
            characters: [0x21: glyph]
        )
        let source = TDFFontCollection(fonts: [font])

        let encoded = try TDFWriter.encode(source)
        let decoded = try TDFParser.parse(encoded)

        try assertCollectionsEquivalent(source, decoded)

        // Explicit assertion on the edge case: the surviving cell should
        // have BOTH foreground and background = 0 (black on black).
        let cell = try XCTUnwrap(decoded.fonts.first?.characters[0x21]?.lines.first?.cells.first)
        XCTAssertEqual(cell.attribute?.foreground, 0,
                       "0x00 attribute must decode to foreground=0")
        XCTAssertEqual(cell.attribute?.background, 0,
                       "0x00 attribute must decode to background=0")
    }

    // MARK: - Outline font (descender)

    /// Outline font containing one glyph with a descender — a line that
    /// ended with `&` in the source. The descender flag must survive the
    /// round trip even though the `&` byte itself is stripped by the parser.
    func testOutlineFontRoundTripWithDescender() throws {
        // 2x2 outline glyph; second line is a descender (e.g. tail of 'g').
        let glyph = TDFCharacter(
            maxWidth: 2, maxHeight: 1,
            lines: [
                TDFLine(cells: [TDFCell(code: 0x41), TDFCell(code: 0x41)],
                        isDescender: false),
                TDFLine(cells: [TDFCell(code: 0x4B), TDFCell(code: 0x42)],
                        isDescender: true),
            ]
        )
        let font = TDFFont(
            name: "Outliny",
            type: .outline,
            letterSpacing: 0,
            characters: [0x67: glyph]  // 'g'
        )
        let source = TDFFontCollection(fonts: [font])

        let encoded = try TDFWriter.encode(source)
        let decoded = try TDFParser.parse(encoded)

        try assertCollectionsEquivalent(source, decoded)

        // Explicit descender survival check.
        let lines = try XCTUnwrap(decoded.fonts.first?.characters[0x67]?.lines)
        XCTAssertEqual(lines.count, 2, "descender line should survive")
        XCTAssertFalse(lines[0].isDescender)
        XCTAssertTrue(lines[1].isDescender, "second line must be flagged as descender")
        // The trailing 0x26 must NOT appear in cells — only the flag carries it.
        XCTAssertFalse(lines[1].cells.contains { $0.code == 0x26 },
                       "parser must strip the literal & byte from cells")
    }

    // MARK: - Multi-font collection (separator exercise)

    /// Two fonts in one collection — verifies the inter-font NUL separator
    /// is correctly emitted by the writer and consumed by the parser.
    func testTwoFontCollectionRoundTrip() throws {
        let blockGlyph = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [TDFCell(code: 0xDB)])]
        )
        let block = TDFFont(
            name: "First",
            type: .block,
            letterSpacing: 2,
            characters: [0x41: blockGlyph]
        )

        let colorGlyph = TDFCharacter(
            maxWidth: 1, maxHeight: 1,
            lines: [TDFLine(cells: [
                TDFCell(code: 0xDB, attribute: TDFAttribute(foreground: 15, background: 1))
            ])]
        )
        let color = TDFFont(
            name: "Second",
            type: .color,
            letterSpacing: 0,
            characters: [0x42: colorGlyph]
        )

        let source = TDFFontCollection(fonts: [block, color])
        let encoded = try TDFWriter.encode(source)
        let decoded = try TDFParser.parse(encoded)

        XCTAssertEqual(decoded.fonts.count, 2)
        try assertCollectionsEquivalent(source, decoded)
    }

    // MARK: - Helpers

    /// Compare two collections ignoring details the format is allowed to
    /// drop (e.g. unused capacity in `lines.count` declared via maxHeight).
    private func assertCollectionsEquivalent(
        _ expected: TDFFontCollection,
        _ actual: TDFFontCollection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(actual.fonts.count, expected.fonts.count,
                       "font count differs", file: file, line: line)
        for (i, expectedFont) in expected.fonts.enumerated() {
            let actualFont = actual.fonts[i]
            XCTAssertEqual(actualFont.name, expectedFont.name,
                           "font[\(i)] name", file: file, line: line)
            XCTAssertEqual(actualFont.type, expectedFont.type,
                           "font[\(i)] type", file: file, line: line)
            XCTAssertEqual(actualFont.letterSpacing, expectedFont.letterSpacing,
                           "font[\(i)] letterSpacing", file: file, line: line)
            XCTAssertEqual(actualFont.characters.keys.sorted(),
                           expectedFont.characters.keys.sorted(),
                           "font[\(i)] defined glyphs", file: file, line: line)
            for (ascii, expectedGlyph) in expectedFont.characters {
                let actualGlyph = try XCTUnwrap(actualFont.characters[ascii],
                                                "missing glyph \(ascii) in font[\(i)]",
                                                file: file, line: line)
                XCTAssertEqual(actualGlyph.maxWidth, expectedGlyph.maxWidth,
                               "glyph \(ascii) maxWidth", file: file, line: line)
                XCTAssertEqual(actualGlyph.maxHeight, expectedGlyph.maxHeight,
                               "glyph \(ascii) maxHeight", file: file, line: line)
                XCTAssertEqual(actualGlyph.lines, expectedGlyph.lines,
                               "glyph \(ascii) lines", file: file, line: line)
            }
        }
    }
}
