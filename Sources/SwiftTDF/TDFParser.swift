// TDFParser.swift
// SwiftTDF — decode raw .tdf bytes into a ``TDFFontCollection``.
//
// See Reference/TDF_SPECIFICATION.md for the format reference. Reads
// liberally (accepts anything TDFONTS.EXE would have produced, plus the
// common variants written by other tools) and treats every offset and size
// in the file as untrusted.

import Foundation

/// Stateless decoder for the TheDraw `.tdf` binary container.
///
/// The decoder is namespaced as an empty `enum`: every call site is a
/// ``parse(_:)`` invocation that fully consumes its input. There is no state
/// to configure or share between calls, so it is safe to call concurrently.
///
/// ## Robustness
///
/// Every offset, size and length in a `.tdf` file is treated as untrusted.
/// The parser never reads outside the input, never traps on arithmetic,
/// and bounds the work done per glyph (see ``maxCellsPerGlyph``), so any
/// input either decodes or throws a ``TDFError``.
public enum TDFParser {
    /// Maximum number of cells the decoder accepts on a single glyph line.
    /// TheDraw caps glyph width at 30; anything above this limit is treated
    /// as corrupt input and reported as ``TDFError/glyphTooLarge(font:ascii:)``.
    public static let maxCellsPerLine = 255
    /// Maximum number of lines (including descender lines) the decoder
    /// accepts in a single glyph. TheDraw caps glyph height at 12.
    public static let maxLinesPerGlyph = 255
    /// Maximum total number of cells the decoder accepts in a single glyph.
    /// This bounds memory use on hostile input whose offset table points
    /// many glyphs into one large unterminated run of data.
    public static let maxCellsPerGlyph = 4_096

    /// Decodes a `.tdf` file into a ``TDFFontCollection``.
    ///
    /// Fonts are read back to back: each font header is followed by exactly
    /// `blockSize` bytes of character data, and the next font header (if
    /// any) starts immediately after. At a font boundary the parser stops
    /// on end of input, on a `0x00` font-list terminator, or on a `0x1A`
    /// DOS EOF byte (which introduces a trailing SAUCE record in many
    /// distributed files). A stray `0x00` immediately followed by another
    /// font sentinel is skipped, so files that place a separator outside the
    /// block size are also accepted.
    ///
    /// The canonical empty file written by ``TDFWriter/encode(_:)`` (a single
    /// nameless block font with no glyphs) and a bare 20-byte file header
    /// both decode to ``TDFFontCollection/empty``.
    ///
    /// - Parameter data: The complete contents of a `.tdf` file. May be a
    ///   slice with a non-zero `startIndex`.
    /// - Returns: The decoded collection, fonts in file order.
    /// - Throws: ``TDFError`` describing the first malformation found. The
    ///   parser stops with ``TDFError/tooManyFonts(count:)`` as soon as it
    ///   meets a 35th font header.
    public static func parse(_ data: Data) throws -> TDFFontCollection {
        let bytes = [UInt8](data)
        var cursor = Cursor(bytes: bytes)
        try validateFileHeader(&cursor)

        var fonts: [TDFFont] = []

        while cursor.remaining > 0 {
            // Font-list boundary handling.
            let next = bytes[cursor.position]
            if next == 0x1A {
                break  // DOS EOF; usually followed by a SAUCE record.
            }
            if next == 0x00 {
                if cursor.hasSentinel(at: cursor.position + 1) {
                    cursor.position += 1  // legacy separator outside the block
                } else {
                    break  // font-list terminator
                }
            }

            guard fonts.count < TDFFontCollection.maxFontsPerCollection else {
                throw TDFError.tooManyFonts(count: fonts.count + 1)
            }
            fonts.append(try readFont(&cursor, fontIndex: fonts.count))
        }

        // Empty-collection round-trip: the writer synthesizes a placeholder
        // font (empty name, block type, no glyphs) for empty collections so
        // the output is still a structurally valid TDFONTS.EXE file. Reverse
        // that here so `parse(encode(.empty)) == .empty`.
        if fonts.count == 1, isEmptyPlaceholder(fonts[0]) {
            return TDFFontCollection.empty
        }

        return TDFFontCollection(fonts: fonts)
    }

    /// True for the writer's synthesized "empty collection" placeholder
    /// font: zero-length name, block type, no defined glyphs, zero spacing.
    private static func isEmptyPlaceholder(_ font: TDFFont) -> Bool {
        font.name.isEmpty
            && font.type == .block
            && font.letterSpacing == 0
            && font.characters.isEmpty
    }

    // MARK: - File header

    private static func validateFileHeader(_ cursor: inout Cursor) throws {
        guard cursor.remaining >= TDFFontCollection.fileHeaderSize else {
            throw TDFError.fileTooShort
        }
        let header = cursor.take(TDFFontCollection.fileHeaderSize)
        if !header.elementsEqual(TDFFontCollection.fileSignature) {
            throw TDFError.invalidSignature
        }
    }

    // MARK: - Per-font

    private static func readFont(_ cursor: inout Cursor, fontIndex: Int) throws -> TDFFont {
        // (a) sentinel
        let sentinelOffset = cursor.position
        guard cursor.hasSentinel(at: sentinelOffset) else {
            throw TDFError.invalidFontSentinel(at: sentinelOffset)
        }

        // The remainder of the 213-byte header must be present in full.
        guard cursor.remaining >= TDFFontCollection.fontHeaderSize else {
            throw TDFError.characterDataTruncated(font: fontIndex, ascii: 0)
        }
        cursor.position += TDFFontCollection.fontStartSentinel.count

        // (b) name length + 12-byte name buffer. Lengths above 12 are
        // clamped; bytes past the declared length are undefined padding.
        let nameLength = min(Int(cursor.readUInt8()), 12)
        let nameBuffer = cursor.take(12)
        let name = decodeFontName(nameBuffer.prefix(nameLength))

        // (c) 4 reserved bytes
        cursor.position += 4

        // (d) font type
        let typeByte = cursor.readUInt8()
        guard let fontType = TDFFontType(rawValue: typeByte) else {
            throw TDFError.invalidFontType(typeByte)
        }

        // (e) letter spacing; on-disk 0x01...0x29 → in-memory 0...40. A
        // 0x00 byte is accepted leniently as zero spacing.
        let spacingByte = cursor.readUInt8()
        guard spacingByte <= 0x29 else {
            throw TDFError.invalidLetterSpacing(spacingByte)
        }
        let letterSpacing = spacingByte == 0 ? 0 : spacingByte - 1

        // (f) block size (LE UInt16)
        let blockSize = Int(cursor.readUInt16LE())

        // (g) 94 × UInt16 LE offsets, 188 bytes total
        var offsets: [UInt16] = []
        offsets.reserveCapacity(TDFFont.glyphCount)
        for _ in 0..<TDFFont.glyphCount {
            offsets.append(cursor.readUInt16LE())
        }

        // (h) character-data block
        guard cursor.remaining >= blockSize else {
            throw TDFError.characterDataTruncated(font: fontIndex, ascii: 0)
        }
        let block = cursor.take(blockSize)

        // (i) decode each defined glyph. Glyphs that share an offset (the
        // editor's "Copy character") are decoded once.
        var characters: [UInt8: TDFCharacter] = [:]
        var decodedByOffset: [Int: TDFCharacter] = [:]
        let asciiStart = TDFFont.definedASCIIRange.lowerBound
        for (index, rawOffset) in offsets.enumerated() where rawOffset != 0xFFFF {
            let ascii = asciiStart + UInt8(index)
            let glyphStart = Int(rawOffset)
            if let cached = decodedByOffset[glyphStart] {
                characters[ascii] = cached
                continue
            }
            guard glyphStart < block.count else {
                throw TDFError.glyphOffsetOutOfRange(font: fontIndex, ascii: ascii, offset: glyphStart)
            }
            let glyph = try decodeGlyph(
                in: block,
                glyphStart: glyphStart,
                fontType: fontType,
                fontIndex: fontIndex,
                ascii: ascii
            )
            decodedByOffset[glyphStart] = glyph
            characters[ascii] = glyph
        }

        return TDFFont(
            name: name,
            type: fontType,
            letterSpacing: letterSpacing,
            characters: characters
        )
    }

    // MARK: - Glyph

    /// Decodes one glyph starting at `glyphStart` inside `block`.
    ///
    /// The loop top is always at a *cell boundary*. There, three bytes are
    /// control codes in every font type and are consumed as single bytes:
    ///
    /// - `0x00` ends the glyph. TDFONTS.EXE writes it directly after the
    ///   last cell (no trailing CR); a `0x0D 0x00` sequence is equally
    ///   accepted. A `0x00` *attribute* byte is never at a cell boundary,
    ///   so it cannot be mistaken for the terminator.
    /// - `0x0D` ends the current line.
    /// - `0x26` (`&`) is a marker, not content. In color fonts it carries
    ///   **no** attribute byte. When it is the last cell of a line the line
    ///   is a descender (``TDFLine/isDescender``); elsewhere it is kept as
    ///   a ``TDFCell`` with code `0x26` and no attribute so it round-trips.
    ///
    /// Any other byte starts a cell: one byte for block/outline fonts, a
    /// character byte plus an attribute byte for color fonts.
    private static func decodeGlyph(
        in block: [UInt8],
        glyphStart: Int,
        fontType: TDFFontType,
        fontIndex: Int,
        ascii: UInt8
    ) throws -> TDFCharacter {
        guard glyphStart + 2 <= block.count else {
            throw TDFError.characterDataTruncated(font: fontIndex, ascii: ascii)
        }
        let maxWidth = block[glyphStart]
        let maxHeight = block[glyphStart + 1]

        var position = glyphStart + 2
        let blockEnd = block.count
        var lines: [TDFLine] = []
        var currentCells: [TDFCell] = []
        var totalCells = 0

        func appendCell(_ cell: TDFCell) throws {
            totalCells += 1
            guard currentCells.count < maxCellsPerLine, totalCells <= maxCellsPerGlyph else {
                throw TDFError.glyphTooLarge(font: fontIndex, ascii: ascii)
            }
            currentCells.append(cell)
        }

        while position < blockEnd {
            let byte = block[position]

            switch byte {
            case 0x00:
                if !currentCells.isEmpty {
                    appendLine(cells: &currentCells, into: &lines)
                }
                return TDFCharacter(maxWidth: maxWidth, maxHeight: maxHeight, lines: lines)

            case 0x0D:
                guard lines.count < maxLinesPerGlyph else {
                    throw TDFError.glyphTooLarge(font: fontIndex, ascii: ascii)
                }
                appendLine(cells: &currentCells, into: &lines)
                position += 1

            case TDFCell.markerCode:
                try appendCell(TDFCell(code: byte, attribute: nil))
                position += 1

            default:
                switch fontType {
                case .block, .outline:
                    try appendCell(TDFCell(code: byte, attribute: nil))
                    position += 1
                case .color:
                    guard position + 1 < blockEnd else {
                        throw TDFError.characterDataTruncated(font: fontIndex, ascii: ascii)
                    }
                    let attribute = TDFAttribute(rawByte: block[position + 1])
                    try appendCell(TDFCell(code: byte, attribute: attribute))
                    position += 2
                }
            }
        }

        // Ran off the end of the block without a terminator. TDFONTS.EXE
        // always terminates, but other writers sometimes omit the final
        // NUL; keep what was decoded.
        if !currentCells.isEmpty {
            appendLine(cells: &currentCells, into: &lines)
        }
        return TDFCharacter(maxWidth: maxWidth, maxHeight: maxHeight, lines: lines)
    }

    /// Appends the current line to `lines`, applying the `&` descender rule:
    /// a line whose final cell is the `&` marker is a descender line; the
    /// marker itself is dropped from the cells and recorded in the flag.
    private static func appendLine(cells: inout [TDFCell], into lines: inout [TDFLine]) {
        var line = TDFLine(cells: cells, isDescender: false)
        if let last = cells.last, last.code == TDFCell.markerCode {
            line.cells.removeLast()
            line.isDescender = true
        }
        lines.append(line)
        cells.removeAll(keepingCapacity: true)
    }

    // MARK: - Name decoding

    /// Decodes the first `L` bytes of a font name as ASCII, dropping NULs and
    /// non-printable bytes. In practice the 12-byte buffer is often padded
    /// with junk past the declared length, and some files NUL-pad inside it.
    private static func decodeFontName(_ bytes: ArraySlice<UInt8>) -> String {
        let filtered = bytes.filter { $0 >= 0x20 && $0 <= 0x7E }
        return String(decoding: filtered, as: UTF8.self)
    }
}

// MARK: - Cursor

/// Linear cursor over a zero-based byte array. Callers check `remaining`
/// before every unchecked read; the helpers below never trap as long as
/// that contract holds.
private struct Cursor {
    let bytes: [UInt8]
    var position: Int = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var remaining: Int { bytes.count - position }

    func hasSentinel(at offset: Int) -> Bool {
        let sentinel = TDFFontCollection.fontStartSentinel
        guard offset >= 0, bytes.count - offset >= sentinel.count else { return false }
        return bytes[offset..<(offset + sentinel.count)].elementsEqual(sentinel)
    }

    mutating func readUInt8() -> UInt8 {
        let b = bytes[position]
        position += 1
        return b
    }

    mutating func readUInt16LE() -> UInt16 {
        let lo = bytes[position]
        let hi = bytes[position + 1]
        position += 2
        return UInt16(lo) | (UInt16(hi) << 8)
    }

    mutating func take(_ count: Int) -> [UInt8] {
        let out = Array(bytes[position..<(position + count)])
        position += count
        return out
    }
}
