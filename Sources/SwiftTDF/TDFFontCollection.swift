// TDFFontCollection.swift
// SwiftTDF — file-level model: a collection of up to 34 TDF fonts.

/// A TheDraw font file: an ordered collection of ``TDFFont`` values plus the
/// on-disk constants used by the parser and writer.
///
/// ## On-disk layout (see `Reference/TDF-Format.md`)
///
/// ```
///   0     20 bytes   file header  0x13 "TheDraw FONTS file" 0x1A
///   20    213 bytes  font 1 header (sentinel … 94-entry offset table)
///   233   N1 bytes   font 1 character data (N1 = font 1 block size)
///   233+N1           font 2 header, and so on
/// ```
///
/// Each font header is **213 bytes**: 4 sentinel, 1 name length, 12 name,
/// 4 reserved, 1 type, 1 spacing, 2 block size and 188 offset-table bytes.
/// A file holding one empty font is therefore 233 bytes. Roy/SAC's write-up quotes 232
/// and 212; those figures are off by one against his own offset table.
///
/// Every font but the last carries one extra `0x00` at the end of its
/// character data, *counted in its block size*. A `0x00` byte where a font
/// header would start ends the font list.
public struct TDFFontCollection: Sendable, Hashable, Codable {
    /// Fonts in this collection, in file order. Spec maximum is 34
    /// (``maxFontsPerCollection``); not enforced at the type level so that
    /// editors can hold over-capacity collections during editing.
    public var fonts: [TDFFont]

    /// Memberwise initializer.
    ///
    /// - Parameter fonts: Fonts in file order.
    public init(fonts: [TDFFont] = []) {
        self.fonts = fonts
    }

    /// A collection with no fonts.
    public static let empty = TDFFontCollection(fonts: [])

    // MARK: - On-disk constants

    /// The 20-byte file header: `0x13 "TheDraw FONTS file" 0x1A`.
    public static let fileSignature: [UInt8] = {
        var bytes: [UInt8] = [0x13]
        bytes.append(contentsOf: Array("TheDraw FONTS file".utf8))
        bytes.append(0x1A)
        return bytes
    }()

    /// The 4-byte start-of-font sentinel: `0x55 0xAA 0x00 0xFF`.
    public static let fontStartSentinel: [UInt8] = [0x55, 0xAA, 0x00, 0xFF]

    /// Maximum fonts allowed per collection by the spec.
    public static let maxFontsPerCollection = 34

    /// Size of the file header in bytes (offsets 0..19).
    public static let fileHeaderSize = 20

    /// Size of one per-font header in bytes (213): sentinel through the
    /// end of the 94-entry offset table. See the type documentation.
    public static let fontHeaderSize = 213
}
