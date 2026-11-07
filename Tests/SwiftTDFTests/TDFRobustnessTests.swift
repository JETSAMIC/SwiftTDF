// TDFRobustnessTests.swift
// SwiftTDF — hostile-input coverage: truncation at every byte offset and a
// deterministic random-mutation fuzz. The assertion is simply that the
// parser returns or throws a TDFError — never traps or hangs.

import XCTest
@testable import SwiftTDF

final class TDFRobustnessTests: XCTestCase {

    func testTruncationAtEveryOffset() {
        let full = Fixture.multiFont
        for length in 0..<full.count {
            let prefix = full.prefix(length)
            do {
                _ = try TDFParser.parse(prefix)
            } catch {
                XCTAssertTrue(error is TDFError, "length \(length): \(error)")
            }
        }
    }

    func testTruncatedSliceWithNonZeroStartIndex() throws {
        var padded = Data([0xEE, 0xEE, 0xEE])
        padded.append(Fixture.multiFont)
        let slice = padded[3...]
        XCTAssertEqual(try TDFParser.parse(slice), try TDFParser.parse(Fixture.multiFont))
    }

    func testSeededMutationFuzz() {
        var rng = SplitMix64(seed: 0x5444_4620_4655_5A5A)  // "TDF FUZZ"
        let seed = [UInt8](Fixture.multiFont)
        var decoded = 0
        for _ in 0..<4_000 {
            var bytes = seed
            let mutations = Int.random(in: 1...8, using: &rng)
            for _ in 0..<mutations {
                switch Int.random(in: 0..<4, using: &rng) {
                case 0:  // flip a byte
                    let i = Int.random(in: 0..<bytes.count, using: &rng)
                    bytes[i] = UInt8.random(in: 0...255, using: &rng)
                case 1:  // hit the structurally interesting header bytes
                    let i = Int.random(in: 20..<min(bytes.count, 233), using: &rng)
                    bytes[i] = [0x00, 0x0D, 0x26, 0xFF, 0x7F, 0x80][Int.random(in: 0..<6, using: &rng)]
                case 2:  // truncate
                    bytes.removeLast(Int.random(in: 0..<min(bytes.count, 32), using: &rng))
                default:  // insert
                    let i = Int.random(in: 0...bytes.count, using: &rng)
                    bytes.insert(UInt8.random(in: 0...255, using: &rng), at: i)
                }
                if bytes.isEmpty { bytes = [0x13] }
            }
            do {
                let collection = try TDFParser.parse(Data(bytes))
                decoded += 1
                // Anything that decodes must be renderable and, if within the
                // writer's limits, re-encodable without trapping.
                for font in collection.fonts {
                    for glyph in font.characters.values {
                        _ = TDFRenderer.render(glyph, type: font.type)
                    }
                }
                _ = try? TDFWriter.encode(collection)
            } catch {
                XCTAssertTrue(error is TDFError, "\(error)")
            }
        }
        XCTAssertGreaterThan(decoded, 0, "fuzz corpus should not be rejected wholesale")
    }

    func testHostileOffsetTableIsBounded() throws {
        // 94 glyphs pointing at consecutive offsets of one long, unterminated
        // run of cells: the per-glyph cap keeps work and memory bounded.
        let run = [UInt8](repeating: 0xDB, count: 60_000)
        var glyphs: [UInt8: UInt16] = [:]
        for ascii in TDFFont.definedASCIIRange { glyphs[ascii] = UInt16(ascii - 33) }
        let bytes = Fixture.fileHeader + Fixture.font(block: run, glyphs: glyphs)
        XCTAssertThrowsError(try TDFParser.parse(Data(bytes))) { error in
            XCTAssertEqual(error as? TDFError, .glyphTooLarge(font: 0, ascii: 33))
        }
    }

    func testREADMEQuickStartCompiles() throws {
        // Mirrors the README "Quick start" snippet.
        let data = Fixture.multiFont
        let collection = try TDFParser.parse(data)
        guard let font = collection.fonts.first, let glyph = font[0x41] else {
            return XCTFail("fixture should define 'A'")
        }
        var painted = 0
        for row in TDFRenderer.render(glyph, type: font.type) {
            for cell in row where !cell.isFiller {
                _ = (cell.code, TDFColor.rgb[Int(cell.foreground)], TDFColor.rgb[Int(cell.background)])
                painted += 1
            }
        }
        XCTAssertEqual(painted, 4)
        let style = TDFOutlineStyle(index: 15)!
        let rows = TDFRenderer.render(glyph, type: .outline, outlineStyle: style)
        XCTAssertEqual(rows.count, 2)
        let bytes = try TDFWriter.encode(collection)
        XCTAssertEqual(bytes, data)
    }
}
