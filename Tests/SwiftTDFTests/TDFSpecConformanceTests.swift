// TDFSpecConformanceTests.swift
// SwiftTDF — one test per spec rule fixed or clarified during the
// production audit. Every fixture is hand-built from the spec.

import XCTest
@testable import SwiftTDF

final class TDFSpecConformanceTests: XCTestCase {

    // MARK: - Container layout

    func testHeaderSizesMatchSpec() {
        XCTAssertEqual(TDFFontCollection.fileHeaderSize, 20)
        XCTAssertEqual(TDFFontCollection.fontHeaderSize, 213)
        XCTAssertEqual(Fixture.font(block: [], glyphs: [:]).count, 213)
    }

    /// TheDraw layout: fonts back to back, block size includes the NUL that
    /// ends every non-final font.
    func testMultiFontFileInTheDrawLayout() throws {
        let collection = try TDFParser.parse(Fixture.multiFont)
        XCTAssertEqual(collection.fonts.map(\.name), ["Blocky", "Colory", "Outliny"])
        XCTAssertEqual(collection.fonts.map(\.type), [.block, .color, .outline])
        XCTAssertEqual(collection.fonts.map(\.letterSpacing), [1, 0, 2])
    }

    func testWriterUsesTheDrawMultiFontLayout() throws {
        let glyph = TDFCharacter(maxWidth: 1, maxHeight: 1, lines: [TDFLine(cells: [TDFCell(code: 0xDB)])])
        let a = TDFFont(name: "A", type: .block, characters: [0x41: glyph])
        let b = TDFFont(name: "B", type: .block, characters: [0x41: glyph])
        let bytes = [UInt8](try TDFWriter.encode(TDFFontCollection(fonts: [a, b])))

        // Font 1 block: 01 01 DB 00 + trailing font NUL = 5 bytes.
        let blockSize1 = Int(bytes[43]) | Int(bytes[44]) << 8
        XCTAssertEqual(blockSize1, 5)
        XCTAssertEqual(Array(bytes[233..<238]), [0x01, 0x01, 0xDB, 0x00, 0x00])
        // Font 2 header starts immediately after font 1's block.
        let font2 = 233 + blockSize1
        XCTAssertEqual(Array(bytes[font2..<(font2 + 4)]), [0x55, 0xAA, 0x00, 0xFF])
        // Last font is not NUL-terminated beyond its glyph terminator.
        let blockSize2 = Int(bytes[font2 + 23]) | Int(bytes[font2 + 24]) << 8
        XCTAssertEqual(blockSize2, 4)
        XCTAssertEqual(bytes.count, font2 + 213 + blockSize2)
    }

    /// Files whose separator NUL sits outside the block size (as older
    /// SwiftTDF builds wrote them) are still read.
    func testSeparatorOutsideBlockSizeAccepted() throws {
        let block: [UInt8] = [0x01, 0x01, 0xDB, 0x00]
        let bytes = Fixture.fileHeader
            + Fixture.font(name: "One", block: block, glyphs: [0x41: 0])
            + [0x00]
            + Fixture.font(name: "Two", block: block, glyphs: [0x41: 0])
        let collection = try TDFParser.parse(Data(bytes))
        XCTAssertEqual(collection.fonts.map(\.name), ["One", "Two"])
    }

    func testNulAtFontBoundaryTerminatesFontList() throws {
        let block: [UInt8] = [0x01, 0x01, 0xDB, 0x00]
        let bytes = Fixture.fileHeader
            + Fixture.font(name: "One", block: block, glyphs: [0x41: 0])
            + [0x00, 0xDE, 0xAD, 0xBE, 0xEF]
        let collection = try TDFParser.parse(Data(bytes))
        XCTAssertEqual(collection.fonts.map(\.name), ["One"])
    }

    func testTrailingSauceRecordIgnored() throws {
        let block: [UInt8] = [0x01, 0x01, 0xDB, 0x00]
        let sauce: [UInt8] = [0x1A] + Array("SAUCE00".utf8) + [UInt8](repeating: 0x20, count: 121)
        let bytes = Fixture.fileHeader + Fixture.font(name: "One", block: block, glyphs: [0x41: 0]) + sauce
        XCTAssertEqual(try TDFParser.parse(Data(bytes)).fonts.count, 1)
    }

    func testGarbageAtFontBoundaryRejected() {
        let block: [UInt8] = [0x01, 0x01, 0xDB, 0x00]
        let bytes = Fixture.fileHeader + Fixture.font(block: block, glyphs: [0x41: 0]) + [0x42]
        XCTAssertThrowsError(try TDFParser.parse(Data(bytes))) { error in
            XCTAssertEqual(error as? TDFError, .invalidFontSentinel(at: 20 + 213 + 4))
        }
    }

    func testMoreThan34FontsRejectedByParser() {
        let one = Fixture.font(block: [0x01, 0x01, 0xDB, 0x00], glyphs: [0x41: 0])
        let bytes = Fixture.fileHeader + Array([[UInt8]](repeating: one, count: 35).joined())
        XCTAssertThrowsError(try TDFParser.parse(Data(bytes))) { error in
            XCTAssertEqual(error as? TDFError, .tooManyFonts(count: 35))
        }
        let ok = Fixture.fileHeader + Array([[UInt8]](repeating: one, count: 34).joined())
        XCTAssertEqual(try TDFParser.parse(Data(ok)).fonts.count, 34)
    }

    // MARK: - Font header fields

    func testNameLengthAbove12IsClamped() throws {
        let bytes = Fixture.fileHeader + Fixture.font(name: "ABCDEFGHIJKL", nameLength: 0xFF, block: [], glyphs: [:])
        XCTAssertEqual(try TDFParser.parse(Data(bytes)).fonts.first?.name, "ABCDEFGHIJKL")
    }

    func testNamePaddingPastDeclaredLengthIgnored() throws {
        let bytes = Fixture.fileHeader + Fixture.font(name: "RoyGarbage", nameLength: 3, block: [], glyphs: [:])
        XCTAssertEqual(try TDFParser.parse(Data(bytes)).fonts.first?.name, "Roy")
    }

    func testLetterSpacingEncoding() throws {
        // 0x01 → 0, 0x29 → 40, 0x00 accepted leniently as 0, 0x2A rejected.
        for (byte, expected) in [(UInt8(0x01), UInt8(0)), (0x29, 40), (0x00, 0)] {
            let bytes = Fixture.fileHeader + Fixture.font(spacing: byte, block: [], glyphs: [:])
            XCTAssertEqual(try TDFParser.parse(Data(bytes)).fonts.first?.letterSpacing, expected)
        }
        let bad = Fixture.fileHeader + Fixture.font(spacing: 0x2A, block: [], glyphs: [:])
        XCTAssertThrowsError(try TDFParser.parse(Data(bad))) { error in
            XCTAssertEqual(error as? TDFError, .invalidLetterSpacing(0x2A))
        }
    }

    // MARK: - Offset table

    func testUndefinedGlyphSentinel() throws {
        let bytes = Fixture.fileHeader + Fixture.font(block: [0x01, 0x01, 0xDB, 0x00], glyphs: [0x7E: 0])
        let font = try XCTUnwrap(TDFParser.parse(Data(bytes)).fonts.first)
        XCTAssertEqual(Array(font.characters.keys), [0x7E])  // '~' is the 94th entry
    }

    func testGlyphOffsetBeyondBlockRejected() {
        let bytes = Fixture.fileHeader + Fixture.font(block: [0x01, 0x01, 0xDB, 0x00], glyphs: [0x41: 4])
        XCTAssertThrowsError(try TDFParser.parse(Data(bytes))) { error in
            XCTAssertEqual(error as? TDFError, .glyphOffsetOutOfRange(font: 0, ascii: 0x41, offset: 4))
        }
    }

    func testGlyphHeaderStraddlingBlockEndRejected() {
        let bytes = Fixture.fileHeader + Fixture.font(block: [0x01, 0x01, 0xDB, 0x00], glyphs: [0x41: 3])
        XCTAssertThrowsError(try TDFParser.parse(Data(bytes))) { error in
            XCTAssertEqual(error as? TDFError, .characterDataTruncated(font: 0, ascii: 0x41))
        }
    }

    func testBlockSizeBeyondFileRejected() {
        let bytes = Fixture.fileHeader + Fixture.font(block: [0x01, 0x01, 0xDB, 0x00], glyphs: [0x41: 0], blockSize: 0xFFFE)
        XCTAssertThrowsError(try TDFParser.parse(Data(bytes))) { error in
            XCTAssertEqual(error as? TDFError, .characterDataTruncated(font: 0, ascii: 0))
        }
    }

    func testSharedOffsetsDecodeIdentically() throws {
        let font = try XCTUnwrap(TDFParser.parse(Fixture.multiFont).fonts.first)
        XCTAssertEqual(font[0x41], font[0x42])
        XCTAssertEqual(font[0x41]?.lines.count, 2)
    }

    // MARK: - Glyph data

    /// In color fonts `&` is a one-byte marker with no attribute byte. The
    /// old parser read the following 0x0D as an attribute and merged lines.
    func testColorDescenderMarkerHasNoAttributeByte() throws {
        let block: [UInt8] = [0x01, 0x01, 0xDB, 0x07, 0x26, 0x0D, 0xDF, 0x0F, 0x00]
        let bytes = Fixture.fileHeader + Fixture.font(type: 0x02, block: block, glyphs: [0x67: 0])
        let glyph = try XCTUnwrap(TDFParser.parse(Data(bytes)).fonts.first?[0x67])
        XCTAssertEqual(glyph.lines.count, 2)
        XCTAssertTrue(glyph.lines[0].isDescender)
        XCTAssertEqual(glyph.lines[0].cells, [TDFCell(code: 0xDB, attribute: TDFAttribute(rawByte: 0x07))])
        XCTAssertFalse(glyph.lines[1].isDescender)
        XCTAssertEqual(glyph.lines[1].cells, [TDFCell(code: 0xDF, attribute: TDFAttribute(rawByte: 0x0F))])
    }

    func testMidLineMarkerPreservedAndRoundTrips() throws {
        let block: [UInt8] = [0x03, 0x01, 0xDB, 0x07, 0x26, 0xB0, 0x01, 0x00]
        let bytes = Fixture.fileHeader + Fixture.font(type: 0x02, block: block, glyphs: [0x41: 0])
        let collection = try TDFParser.parse(Data(bytes))
        let line = try XCTUnwrap(collection.fonts.first?[0x41]?.lines.first)
        XCTAssertEqual(line.cells.map(\.code), [0xDB, 0x26, 0xB0])
        XCTAssertNil(line.cells[1].attribute)
        XCTAssertEqual([UInt8](try TDFWriter.encode(collection)), bytes)
    }

    func testAttributeBlinkBitPreserved() throws {
        let attribute = TDFAttribute(rawByte: 0xCF)
        XCTAssertEqual(attribute.foreground, 0x0F)
        XCTAssertEqual(attribute.background, 0x04)
        XCTAssertTrue(attribute.blink)
        XCTAssertEqual(attribute.rawByte, 0xCF)

        let block: [UInt8] = [0x01, 0x01, 0xDB, 0xCF, 0x00]
        let bytes = Fixture.fileHeader + Fixture.font(type: 0x02, block: block, glyphs: [0x41: 0])
        XCTAssertEqual([UInt8](try TDFWriter.encode(TDFParser.parse(Data(bytes)))), bytes)
    }

    func testCRBeforeTerminatorAccepted() throws {
        let block: [UInt8] = [0x01, 0x02, 0x41, 0x0D, 0x42, 0x0D, 0x00]
        let bytes = Fixture.fileHeader + Fixture.font(block: block, glyphs: [0x41: 0])
        let glyph = try XCTUnwrap(TDFParser.parse(Data(bytes)).fonts.first?[0x41])
        XCTAssertEqual(glyph.lines.map { $0.cells.map(\.code) }, [[0x41], [0x42]])
    }

    func testMissingTerminatorAtBlockEndTolerated() throws {
        let bytes = Fixture.fileHeader + Fixture.font(block: [0x01, 0x01, 0x41], glyphs: [0x41: 0])
        let glyph = try XCTUnwrap(TDFParser.parse(Data(bytes)).fonts.first?[0x41])
        XCTAssertEqual(glyph.lines.first?.cells.map(\.code), [0x41])
    }

    func testOversizedGlyphRejected() {
        let block: [UInt8] = [0x1E, 0x0C] + [UInt8](repeating: 0xDB, count: TDFParser.maxCellsPerLine + 1) + [0x00]
        let bytes = Fixture.fileHeader + Fixture.font(block: block, glyphs: [0x41: 0])
        XCTAssertThrowsError(try TDFParser.parse(Data(bytes))) { error in
            XCTAssertEqual(error as? TDFError, .glyphTooLarge(font: 0, ascii: 0x41))
        }
    }

    // MARK: - Writer

    func testWriterEmitsBareNulTerminator() throws {
        let glyph = TDFCharacter(maxWidth: 1, maxHeight: 2, lines: [
            TDFLine(cells: [TDFCell(code: 0x41)]),
            TDFLine(cells: [TDFCell(code: 0x42)]),
        ])
        let bytes = [UInt8](try TDFWriter.encode(TDFFontCollection(fonts: [TDFFont(name: "X", type: .block, characters: [0x21: glyph])])))
        XCTAssertEqual(Array(bytes[233...]), [0x01, 0x02, 0x41, 0x0D, 0x42, 0x00])
    }

    func testTrailingEmptyLineSurvivesRoundTrip() throws {
        let glyph = TDFCharacter(maxWidth: 1, maxHeight: 2, lines: [
            TDFLine(cells: [TDFCell(code: 0x41)]),
            TDFLine(cells: []),
        ])
        let source = TDFFontCollection(fonts: [TDFFont(name: "X", type: .block, characters: [0x21: glyph])])
        XCTAssertEqual(try TDFParser.parse(TDFWriter.encode(source)), source)
    }

    func testWriterRejectsReservedCellCodes() {
        for code: UInt8 in [0x00, 0x0D] {
            let glyph = TDFCharacter(maxWidth: 1, maxHeight: 1, lines: [TDFLine(cells: [TDFCell(code: code)])])
            let collection = TDFFontCollection(fonts: [TDFFont(name: "X", type: .block, characters: [0x41: glyph])])
            XCTAssertThrowsError(try TDFWriter.encode(collection)) { error in
                XCTAssertEqual(error as? TDFError, .unencodableCell(font: 0, ascii: 0x41, code: code))
            }
        }
    }

    func testWriterRejectsGlyphOutsideOffsetTable() {
        let collection = TDFFontCollection(fonts: [TDFFont(name: "X", type: .block, characters: [0x20: .empty])])
        XCTAssertThrowsError(try TDFWriter.encode(collection)) { error in
            XCTAssertEqual(error as? TDFError, .characterOutOfRange(font: 0, ascii: 0x20))
        }
    }

    func testWriterRejectsOversizedCharacterData() {
        // 94 distinct 30x12 color glyphs need ~69 KB, more than 16 bits allow.
        var characters: [UInt8: TDFCharacter] = [:]
        for ascii in TDFFont.definedASCIIRange {
            let row = TDFLine(cells: [TDFCell](repeating: TDFCell(code: ascii, attribute: .defaultAttribute), count: 30))
            characters[ascii] = TDFCharacter(maxWidth: 30, maxHeight: 12, lines: [TDFLine](repeating: row, count: 12))
        }
        let collection = TDFFontCollection(fonts: [TDFFont(name: "Huge", type: .color, characters: characters)])
        XCTAssertThrowsError(try TDFWriter.encode(collection)) { error in
            guard case .characterDataTooLarge(font: 0, _)? = error as? TDFError else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    // MARK: - Outline styles and rendering

    func testOutlineStyleNineMatchesRoySACTable() {
        for letter in UInt8(0x41)...0x4E {
            XCTAssertEqual(TDFOutlineStyle.roySAC.substitute(letter), TDFOutlineGlyphs.render(letter))
        }
    }

    func testOutlineStylesTable() {
        XCTAssertEqual(TDFOutlineStyle.all.count, 19)
        XCTAssertNil(TDFOutlineStyle(index: 19))
        XCTAssertNil(TDFOutlineStyle(index: -1))
        XCTAssertEqual(TDFOutlineStyle(index: 0)?.substitute(0x41), 0xC4)  // ─
        XCTAssertEqual(TDFOutlineStyle(index: 15)?.substitute(0x45), 0xC9) // ╔
        XCTAssertEqual(TDFOutlineStyle(index: 16)?.substitute(0x43), 0xDB) // █
        for style in TDFOutlineStyle.all {
            for blank: UInt8 in [0x4F, 0x50, 0x51, 0x40] {
                XCTAssertEqual(style.substitute(blank), 0x20)
            }
            XCTAssertEqual(style.substitute(0x52), 0x52)  // 'R' passes through
            XCTAssertEqual(style.substitute(0x20), 0x20)
        }
    }

    /// TDF-Format.md §4.4/§4.5: in styles 0–15, bit 0 doubles `A` (top
    /// edges), bit 1 `B` (bottom), bit 2 `C` (left), bit 3 `D` (right), and
    /// every corner/tee is the box-drawing join of its two edge letters.
    func testLineStylesFollowEdgeCompositionRule() {
        // Box-drawing joins indexed by [horizontal double] + 2 × [vertical double].
        let topLeft: [UInt8] = [0xDA, 0xD5, 0xD6, 0xC9]      // ┌ ╒ ╓ ╔
        let topRight: [UInt8] = [0xBF, 0xB8, 0xB7, 0xBB]     // ┐ ╕ ╖ ╗
        let bottomLeft: [UInt8] = [0xC0, 0xD4, 0xD3, 0xC8]   // └ ╘ ╙ ╚
        let bottomRight: [UInt8] = [0xD9, 0xBE, 0xBD, 0xBC]  // ┘ ╛ ╜ ╝
        let rightTee: [UInt8] = [0xB4, 0xB5, 0xB6, 0xB9]     // ┤ ╡ ╢ ╣
        let leftTee: [UInt8] = [0xC3, 0xC6, 0xC7, 0xCC]      // ├ ╞ ╟ ╠
        // Placeholder → (join table, horizontal edge, vertical edge).
        let joins: [(UInt8, [UInt8], Int, Int)] = [
            (0x45, topLeft, 0, 2),      // E = A + C
            (0x46, topRight, 0, 3),     // F = A + D
            (0x47, topLeft, 1, 3),      // G = B + D
            (0x48, topRight, 1, 2),     // H = B + C
            (0x49, bottomLeft, 0, 3),   // I = A + D
            (0x4A, bottomRight, 0, 2),  // J = A + C
            (0x4B, bottomLeft, 1, 2),   // K = B + C
            (0x4C, bottomRight, 1, 3),  // L = B + D
            (0x4D, rightTee, 0, 2),     // M = A + C
            (0x4E, leftTee, 1, 3),      // N = B + D
        ]
        for index in 0..<16 {
            let style = TDFOutlineStyle(index: index)!
            let double = (0..<4).map { (index >> $0) & 1 }
            XCTAssertEqual(style.substitute(0x41), double[0] == 1 ? 0xCD : 0xC4, "style \(index) A")
            XCTAssertEqual(style.substitute(0x42), double[1] == 1 ? 0xCD : 0xC4, "style \(index) B")
            XCTAssertEqual(style.substitute(0x43), double[2] == 1 ? 0xBA : 0xB3, "style \(index) C")
            XCTAssertEqual(style.substitute(0x44), double[3] == 1 ? 0xBA : 0xB3, "style \(index) D")
            for (letter, table, horizontal, vertical) in joins {
                XCTAssertEqual(
                    style.substitute(letter),
                    table[double[horizontal] + 2 * double[vertical]],
                    "style \(index) letter \(UnicodeScalar(letter))"
                )
            }
        }
    }

    /// TDF-Format.md §4.5: the three block styles, `A`…`N`.
    func testBlockStylesMatchSpecTable() {
        let expected: [Int: [UInt8]] = [
            16: [0xDC, 0xDC, 0xDB, 0xDB, 0xDC, 0xDC, 0xDC, 0xDC, 0xDB, 0xDB, 0xDB, 0xDB, 0xDB, 0xDB],
            17: [0xDF, 0xDF, 0xDB, 0xDB, 0xDB, 0xDB, 0xDB, 0xDB, 0xDF, 0xDF, 0xDF, 0xDF, 0xDB, 0xDB],
            18: [0xDF, 0xDC, 0xDE, 0xDD, 0xDE, 0xDD, 0xDC, 0xDC, 0xDF, 0xDF, 0xDE, 0xDD, 0xDB, 0xDB],
        ]
        for (index, row) in expected {
            let style = TDFOutlineStyle(index: index)!
            for (offset, code) in row.enumerated() {
                XCTAssertEqual(style.substitute(0x41 + UInt8(offset)), code, "style \(index) column \(offset)")
            }
        }
    }

    func testOutlineRendererUsesSelectedStyle() {
        let glyph = TDFCharacter(maxWidth: 3, maxHeight: 1, lines: [
            TDFLine(cells: [TDFCell(code: 0x40), TDFCell(code: 0x41), TDFCell(code: 0x4F)]),
        ])
        let row = TDFRenderer.render(glyph, type: .outline, outlineStyle: TDFOutlineStyle(index: 0)!)[0]
        XCTAssertTrue(row[0].isFiller)
        XCTAssertEqual(row[0].code, 0x20)
        XCTAssertEqual(row[1].code, 0xC4)
        XCTAssertTrue(row[2].isHardSpace)
        XCTAssertEqual(row[2].code, 0x20)
    }

    func testHardBlankAndMarkerRendering() {
        let glyph = TDFCharacter(maxWidth: 2, maxHeight: 1, lines: [
            TDFLine(cells: [TDFCell(code: 0xFF, attribute: .defaultAttribute), TDFCell(code: 0x26)]),
        ])
        let row = TDFRenderer.render(glyph, type: .color)[0]
        XCTAssertTrue(row[0].isHardSpace)
        XCTAssertTrue(row[1].isFiller)
        XCTAssertEqual(row[1].code, 0x20)
    }

    // MARK: - Full fixture

    func testMultiFontFixtureRoundTripsByteForByte() throws {
        let parsed = try TDFParser.parse(Fixture.multiFont)
        XCTAssertEqual(try TDFWriter.encode(parsed), Fixture.multiFont)
    }
}
