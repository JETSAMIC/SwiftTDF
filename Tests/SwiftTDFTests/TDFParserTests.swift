// TDFParserTests.swift
// SwiftTDF — high-level decoder coverage: header/signature validation,
// truncation handling, and round-trip with the writer for the empty file.

import XCTest
@testable import SwiftTDF

final class TDFParserTests: XCTestCase {

    // MARK: - Empty-file round-trip

    /// Parsing the writer's output for an empty collection should yield an
    /// empty collection back. This is the canonical round-trip identity for
    /// the empty-file case described in `Reference/TDF-Format.md`.
    func testEmptyCollectionRoundTrip() throws {
        let encoded = try TDFWriter.encode(.empty)
        let parsed = try TDFParser.parse(encoded)
        XCTAssertEqual(parsed.fonts.count, 0,
                       "parse(encode(.empty)) should yield an empty collection")
    }

    /// The spec's "empty-file invariant": an encoded empty collection is the
    /// 20-byte file header followed by a per-font placeholder header.
    ///
    /// The spec's intro paragraph quotes **232 bytes** here, but its own
    /// offset table places "Font 1 data" at offset 233 — the per-font header
    /// is structurally 213 bytes (4 sentinel + 1 name-length + 12 name + 4
    /// reserved + 1 type + 1 spacing + 2 block-size + 188 offsets), not 212.
    /// The writer follows the offset table (the authoritative part of the
    /// spec) and emits **233 bytes** for an empty file.
    func testEmptyFileIsExactly233Bytes() throws {
        let encoded = try TDFWriter.encode(.empty)
        XCTAssertEqual(encoded.count, 233,
                       "Empty .tdf file is 20-byte header + 213-byte placeholder = 233 bytes")
    }

    // MARK: - Signature validation

    /// Feeding 20 bytes of garbage as a "header" must throw `.invalidSignature`.
    func testInvalidSignatureRejected() {
        let garbage = Data(repeating: 0xAB, count: 32)
        XCTAssertThrowsError(try TDFParser.parse(garbage)) { error in
            XCTAssertEqual(error as? TDFError, .invalidSignature)
        }
    }

    /// A buffer shorter than the fixed 20-byte file header must throw
    /// `.fileTooShort` (NOT `.invalidSignature` — we can't even compare).
    func testFileShorterThanHeaderRejected() {
        let tiny = Data([0x13, 0x54, 0x68])
        XCTAssertThrowsError(try TDFParser.parse(tiny)) { error in
            XCTAssertEqual(error as? TDFError, .fileTooShort)
        }
    }

    // MARK: - Truncation

    /// Feeding only the valid 20-byte file header (no font data at all) is
    /// treated as an empty collection — symmetric with the empty-collection
    /// round-trip. Note that TDFONTS.EXE itself doesn't write header-only
    /// files (it always emits the placeholder font), but we accept them on
    /// read so manually-constructed buffers don't surprise the caller.
    func testHeaderOnlyParsesAsEmpty() throws {
        let headerOnly = Data(TDFFontCollection.fileSignature)
        let parsed = try TDFParser.parse(headerOnly)
        XCTAssertEqual(parsed.fonts.count, 0,
                       "header-only buffer should parse as an empty collection")
    }

    /// Feeding the file header followed by a half-finished font header
    /// (sentinel present, but the rest of the 212-byte header missing)
    /// must throw a truncation error rather than crashing.
    func testTruncatedFontHeaderRejected() {
        var bytes = Data(TDFFontCollection.fileSignature)
        // Add a sentinel and ONE more byte — far short of a full header.
        bytes.append(contentsOf: TDFFontCollection.fontStartSentinel)
        bytes.append(0x00)
        XCTAssertThrowsError(try TDFParser.parse(bytes)) { error in
            guard let tdfError = error as? TDFError else {
                XCTFail("Expected TDFError, got \(error)")
                return
            }
            switch tdfError {
            case .characterDataTruncated, .fileTooShort:
                break  // either is acceptable for truncation
            default:
                XCTFail("Expected truncation error, got \(tdfError)")
            }
        }
    }

    // MARK: - Field validation

    // MARK: - Glyph terminator (TDFONTS.EXE compatibility)

    /// TDFONTS.EXE writes a glyph's terminator as a bare 0x00 at the cell
    /// boundary after the last line — it does NOT emit a trailing 0x0D
    /// before the NUL. The Roy/SAC spec phrases the terminator as "NUL
    /// after 0x0D", but the canonical TDFONTS.TDF distribution's
    /// "ColorRounded" font (and every real-world color font we've seen)
    /// uses the bare-NUL form. A parser that requires a preceding CR
    /// walks straight past the terminator, mis-strides into subsequent
    /// glyphs, and fails with `.characterDataTruncated` on glyph 33.
    ///
    /// This test builds that exact byte layout by hand (so we don't rely
    /// on the writer's choice of terminator form) and asserts the parser
    /// recovers the full glyph.
    func testColorGlyphTerminatorWithoutTrailingCR() throws {
        var bytes = Data(TDFFontCollection.fileSignature)
        // Per-font header
        bytes.append(contentsOf: TDFFontCollection.fontStartSentinel)
        bytes.append(0x05)                                              // name length
        bytes.append(contentsOf: Array("Color".utf8))
        bytes.append(contentsOf: [UInt8](repeating: 0x00, count: 7))    // name padding
        bytes.append(contentsOf: [UInt8](repeating: 0x00, count: 4))    // reserved
        bytes.append(0x02)                                              // type = color
        bytes.append(0x01)                                              // spacing = 0

        // Character data block:
        //   glyph header: width=2, height=2
        //   line 1: 2 color cells, then 0x0D
        //   line 2: 2 color cells, then 0x00 (terminator with NO leading CR)
        let block: [UInt8] = [
            0x02, 0x02,                            // header
            0xDB, 0x07,  0xDB, 0x07,  0x0D,        // line 1 + CR
            0xDB, 0x0D,  0xDB, 0x70,  0x00,        // line 2 + bare NUL terminator
        ]
        let blockSize = UInt16(block.count)
        bytes.append(UInt8(blockSize & 0xFF))
        bytes.append(UInt8((blockSize >> 8) & 0xFF))

        // Offset table: glyph '!' (ASCII 33) at offset 0 of the block, rest 0xFFFF.
        var offsets = [UInt8](repeating: 0xFF, count: 188)
        offsets[0] = 0x00
        offsets[1] = 0x00
        bytes.append(contentsOf: offsets)

        // Character data
        bytes.append(contentsOf: block)

        let collection = try TDFParser.parse(bytes)
        XCTAssertEqual(collection.fonts.count, 1)
        let font = try XCTUnwrap(collection.fonts.first)
        XCTAssertEqual(font.type, .color)
        let glyph = try XCTUnwrap(font.characters[0x21])
        XCTAssertEqual(glyph.lines.count, 2, "both lines must survive bare-NUL terminator")
        XCTAssertEqual(glyph.lines[0].cells.count, 2)
        XCTAssertEqual(glyph.lines[1].cells.count, 2)
        // Specifically: the cell with attribute 0x0D (bright magenta on black)
        // is the one that fooled the old parser into treating it as a CR.
        XCTAssertEqual(glyph.lines[1].cells[0].attribute?.rawByte, 0x0D)
    }

    /// A font header with an invalid font-type byte (not 0x00/0x01/0x02)
    /// must throw `.invalidFontType` with the offending byte attached.
    func testInvalidFontTypeRejected() {
        var bytes = Data(TDFFontCollection.fileSignature)
        bytes.append(contentsOf: TDFFontCollection.fontStartSentinel)
        bytes.append(0x00)                                  // name length
        bytes.append(contentsOf: [UInt8](repeating: 0x00, count: 12))  // name
        bytes.append(contentsOf: [UInt8](repeating: 0x00, count: 4))   // reserved
        bytes.append(0x77)                                  // BAD font type
        bytes.append(0x01)                                  // spacing = 0
        bytes.append(0x00); bytes.append(0x00)              // block size = 0
        bytes.append(contentsOf: [UInt8](repeating: 0xFF, count: 188)) // offsets

        XCTAssertThrowsError(try TDFParser.parse(bytes)) { error in
            XCTAssertEqual(error as? TDFError, .invalidFontType(0x77))
        }
    }
}
