// TDFWriter.swift
// SwiftTDF — encode a ``TDFFontCollection`` into the raw `.tdf` binary
// container.
//
// See Reference/TDF_SPECIFICATION.md for the authoritative format reference.
// Writes conservatively (output that TDFONTS.EXE accepts without complaint)
// and round-trips cleanly through ``TDFParser/parse(_:)`` modulo unspecified
// padding bytes (e.g. the font-name buffer past the declared length).

import Foundation

/// Stateless encoder for the TheDraw `.tdf` binary container.
///
/// Mirrors ``TDFParser``: every call site is a single ``encode(_:)``
/// invocation; there is no state to configure between calls.
public enum TDFWriter {
    /// Encodes a ``TDFFontCollection`` to its on-disk `.tdf` byte stream.
    ///
    /// Soft limits are clamped the way the TDFONTS.EXE editor does when it
    /// saves: font names are reduced to their first 12 printable ASCII
    /// characters, letter spacing above 40 becomes 40, and glyph widths and
    /// heights above 30 and 12 are clamped in the glyph header (the cells
    /// themselves are written as-is).
    ///
    /// ## Layout written
    ///
    /// Fonts are written back to back. Every font except the last gets one
    /// extra `0x00` appended to its character data and counted in its block
    /// size, as TheDraw does; the last font is not terminated. Each glyph's
    /// lines are separated by `0x0D` and the glyph ends with a bare `0x00`
    /// directly after its last cell (an extra `0x0D` is written only when
    /// the last line is empty, so that it survives a round trip).
    ///
    /// ## Round-trip contract
    ///
    /// `TDFParser.parse(TDFWriter.encode(c)) == c` for any collection whose
    /// names, spacing and glyph sizes are within the format's limits, whose
    /// color-font cells all carry an attribute, and which does not use the
    /// reserved `&` code as the last cell of a non-descender line. A
    /// collection holding a single nameless, empty block font with zero
    /// spacing decodes as ``TDFFontCollection/empty``.
    ///
    /// ## Deduplication
    ///
    /// Glyphs within one font that encode to byte-identical data share a
    /// single offset, matching the TDFONTS.EXE "Copy character" behaviour.
    ///
    /// - Parameter collection: The collection to encode. An empty collection
    ///   is written as one nameless, empty block font (233 bytes), because
    ///   TheDraw cannot load a header-only file.
    /// - Returns: The complete file contents.
    /// - Throws: ``TDFError/tooManyFonts(count:)`` for more than 34 fonts,
    ///   ``TDFError/characterOutOfRange(font:ascii:)`` for glyphs keyed
    ///   outside `33...126`, ``TDFError/unencodableCell(font:ascii:code:)``
    ///   for cells whose code is `0x00` or `0x0D`, and
    ///   ``TDFError/characterDataTooLarge(font:size:)`` when a font's
    ///   character data does not fit the 16-bit block-size field.
    public static func encode(_ collection: TDFFontCollection) throws -> Data {
        if collection.fonts.count > TDFFontCollection.maxFontsPerCollection {
            throw TDFError.tooManyFonts(count: collection.fonts.count)
        }

        var output = Data()
        output.append(contentsOf: TDFFontCollection.fileSignature)

        let fontsToEmit: [TDFFont]
        if collection.fonts.isEmpty {
            fontsToEmit = [TDFFont(name: "", type: .block, letterSpacing: 0, characters: [:])]
        } else {
            fontsToEmit = collection.fonts
        }

        for (index, font) in fontsToEmit.enumerated() {
            try encodeFont(
                font,
                fontIndex: index,
                isLast: index == fontsToEmit.count - 1,
                into: &output
            )
        }

        return output
    }

    // MARK: - Per-font

    private static func encodeFont(
        _ font: TDFFont,
        fontIndex: Int,
        isLast: Bool,
        into output: inout Data
    ) throws {
        // Build the character-data block first so the header can be written
        // in one pass.
        var block = [UInt8]()
        var dedupCache: [[UInt8]: UInt16] = [:]
        var offsets = [UInt16](repeating: 0xFFFF, count: TDFFont.glyphCount)

        for ascii in font.characters.keys where !TDFFont.definedASCIIRange.contains(ascii) {
            throw TDFError.characterOutOfRange(font: fontIndex, ascii: ascii)
        }

        let asciiStart = TDFFont.definedASCIIRange.lowerBound
        for ascii in TDFFont.definedASCIIRange {
            guard let glyph = font.characters[ascii] else { continue }
            let encoded = try encodeGlyph(glyph, fontType: font.type, fontIndex: fontIndex, ascii: ascii)
            let tableIndex = Int(ascii - asciiStart)
            if let existing = dedupCache[encoded] {
                offsets[tableIndex] = existing
                continue
            }
            // 0xFFFF is the "undefined" sentinel, so the last usable start
            // offset is 0xFFFE.
            guard block.count < 0xFFFF else {
                throw TDFError.characterDataTooLarge(font: fontIndex, size: block.count + encoded.count)
            }
            let newOffset = UInt16(block.count)
            offsets[tableIndex] = newOffset
            dedupCache[encoded] = newOffset
            block.append(contentsOf: encoded)
        }

        // Every font but the last carries a trailing NUL inside its block.
        if !isLast {
            block.append(0x00)
        }

        guard block.count <= Int(UInt16.max) else {
            throw TDFError.characterDataTooLarge(font: fontIndex, size: block.count)
        }

        // (a) sentinel
        output.append(contentsOf: TDFFontCollection.fontStartSentinel)

        // (b) name length + 12-byte NUL-padded name buffer
        let nameBytes = asciiNameBytes(font.name)
        output.append(UInt8(nameBytes.count))
        output.append(contentsOf: nameBytes)
        output.append(contentsOf: [UInt8](repeating: 0x00, count: 12 - nameBytes.count))

        // (c) 4 reserved bytes (zero)
        output.append(contentsOf: [UInt8](repeating: 0x00, count: 4))

        // (d) font type
        output.append(font.type.rawValue)

        // (e) letter spacing — model 0...40 → file 0x01...0x29
        output.append(min(font.letterSpacing, 40) + 1)

        // (f) block size, (g) offset table — little-endian words
        appendUInt16LE(UInt16(block.count), to: &output)
        for value in offsets {
            appendUInt16LE(value, to: &output)
        }

        // (h) character data
        output.append(contentsOf: block)
    }

    private static func appendUInt16LE(_ value: UInt16, to output: inout Data) {
        output.append(UInt8(value & 0xFF))
        output.append(UInt8(value >> 8))
    }

    // MARK: - Glyph encoding

    private static func encodeGlyph(
        _ character: TDFCharacter,
        fontType: TDFFontType,
        fontIndex: Int,
        ascii: UInt8
    ) throws -> [UInt8] {
        var bytes: [UInt8] = []

        // Glyph header: width and height clamped to the editor's limits.
        bytes.append(min(character.maxWidth, 30))
        bytes.append(min(character.maxHeight, 12))

        for (lineIndex, line) in character.lines.enumerated() {
            for cell in line.cells {
                guard cell.code != 0x00, cell.code != 0x0D else {
                    throw TDFError.unencodableCell(font: fontIndex, ascii: ascii, code: cell.code)
                }
                bytes.append(cell.code)
                // `&` is a single-byte marker in every font type; any other
                // color cell is followed by its attribute byte. A missing
                // attribute is written as TheDraw's default, 0x07.
                if fontType == .color, cell.code != TDFCell.markerCode {
                    bytes.append((cell.attribute ?? TDFAttribute.defaultAttribute).rawByte)
                }
            }
            if line.isDescender {
                bytes.append(TDFCell.markerCode)
            }
            let isLastLine = lineIndex == character.lines.count - 1
            if !isLastLine || (line.cells.isEmpty && !line.isDescender) {
                bytes.append(0x0D)
            }
        }

        bytes.append(0x00)
        return bytes
    }

    // MARK: - Name encoding

    /// Encodes a font name as up to 12 printable-ASCII bytes. Other
    /// characters are dropped, mirroring the parser's filter on read.
    private static func asciiNameBytes(_ name: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(12)
        for scalar in name.unicodeScalars {
            let value = scalar.value
            guard value >= 0x20 && value <= 0x7E else { continue }
            out.append(UInt8(value))
            if out.count == 12 { break }
        }
        return out
    }
}
