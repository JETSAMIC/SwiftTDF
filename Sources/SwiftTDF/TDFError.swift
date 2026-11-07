// TDFError.swift
// SwiftTDF — errors thrown by the parser and the writer.

import Foundation

/// Errors produced while decoding a `.tdf` byte stream into a
/// ``TDFFontCollection`` (``TDFParser``) or encoding one back to bytes
/// (``TDFWriter``).
///
/// Values carry enough positional context (offset, font index, ASCII code)
/// for a caller to point at the offending byte without re-walking the
/// file. Conforms to `LocalizedError` so the descriptions surface usefully
/// when reported via `Error`-typed channels.
public enum TDFError: Error, Sendable, Equatable {
    /// The input buffer is smaller than the fixed 20-byte file header.
    case fileTooShort
    /// The 20-byte file header did not match `0x13 "TheDraw FONTS file" 0x1A`.
    case invalidSignature
    /// A per-font header did not begin with the `0x55 0xAA 0x00 0xFF`
    /// start-of-font sentinel. `at` is the absolute byte offset where the
    /// sentinel was expected.
    case invalidFontSentinel(at: Int)
    /// The font-type byte (offset 21 of the per-font header) was not one of
    /// the values defined by ``TDFFontType``.
    case invalidFontType(UInt8)
    /// The letter-spacing byte (offset 22 of the per-font header) was above
    /// the legal maximum `0x29` (decoded spacing 40).
    case invalidLetterSpacing(UInt8)
    /// The data ended inside a font header or inside a glyph. `font` is the
    /// zero-based font index; `ascii` is the glyph's ASCII code, or `0` when
    /// the truncation is inside the 213-byte font header or the font's
    /// character-data block as a whole.
    case characterDataTruncated(font: Int, ascii: UInt8)
    /// A glyph's entry in the character offset table points at or beyond the
    /// end of the font's character-data block (`offset >= blockSize`).
    case glyphOffsetOutOfRange(font: Int, ascii: UInt8, offset: Int)
    /// A glyph decoded to more lines, cells per line, or total cells than
    /// ``TDFParser/maxLinesPerGlyph``, ``TDFParser/maxCellsPerLine`` or
    /// ``TDFParser/maxCellsPerGlyph`` allow. TheDraw itself caps glyphs at
    /// 30 × 12 cells, so this only fires on corrupt or hostile input.
    case glyphTooLarge(font: Int, ascii: UInt8)
    /// The collection holds more than the spec maximum of 34 fonts.
    /// `count` is the number of fonts in the collection being encoded or,
    /// when parsing, the number of font headers seen before the parser
    /// stopped (always `maxFontsPerCollection + 1`).
    case tooManyFonts(count: Int)
    /// Writer only: a glyph's key in ``TDFFont/characters`` lies outside
    /// ``TDFFont/definedASCIIRange`` (`33...126`) and cannot be stored in
    /// the offset table.
    case characterOutOfRange(font: Int, ascii: UInt8)
    /// Writer only: a cell's ``TDFCell/code`` is `0x00` (glyph terminator)
    /// or `0x0D` (line break), which the format cannot store as content.
    case unencodableCell(font: Int, ascii: UInt8, code: UInt8)
    /// Writer only: the encoded character-data block of font `font` is
    /// `size` bytes, exceeding the 65,535 bytes addressable by the 16-bit
    /// block-size field (or a glyph would start at offset `0xFFFF`, which
    /// is reserved for "undefined").
    case characterDataTooLarge(font: Int, size: Int)
}

extension TDFError: LocalizedError {
    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .fileTooShort:
            return "TDF file is shorter than the required 20-byte file header."
        case .invalidSignature:
            return "TDF file header signature is invalid (expected 0x13 + \"TheDraw FONTS file\" + 0x1A)."
        case .invalidFontSentinel(let offset):
            return "Invalid font start-of-font sentinel at offset \(offset) (expected 55 AA 00 FF)."
        case .invalidFontType(let raw):
            return "Invalid TDF font-type byte \(hex(raw)) (expected 0x00 outline, 0x01 block, or 0x02 color)."
        case .invalidLetterSpacing(let raw):
            return "Invalid TDF letter-spacing byte \(hex(raw)) (expected 0x01..0x29)."
        case .characterDataTruncated(let font, let ascii):
            if ascii == 0 {
                return "Truncated header or character data in font \(font)."
            }
            return "Truncated character data in font \(font) at ASCII code \(ascii)."
        case .glyphOffsetOutOfRange(let font, let ascii, let offset):
            return "Glyph offset \(offset) for ASCII code \(ascii) in font \(font) lies outside the character-data block."
        case .glyphTooLarge(let font, let ascii):
            return "Glyph for ASCII code \(ascii) in font \(font) exceeds the decoder's size limits."
        case .tooManyFonts(let count):
            return "TDF collection holds \(count) fonts, exceeding the spec maximum of \(TDFFontCollection.maxFontsPerCollection)."
        case .characterOutOfRange(let font, let ascii):
            return "Font \(font) defines a glyph for ASCII code \(ascii), outside the storable range 33...126."
        case .unencodableCell(let font, let ascii, let code):
            return "Glyph \(ascii) in font \(font) contains cell code \(hex(code)), which TDF reserves as a control byte."
        case .characterDataTooLarge(let font, let size):
            return "Character data of font \(font) is \(size) bytes, exceeding the 16-bit TDF block-size limit."
        }
    }

    private func hex(_ byte: UInt8) -> String {
        let digits = String(byte, radix: 16, uppercase: true)
        return "0x" + (digits.count == 1 ? "0" + digits : digits)
    }
}
