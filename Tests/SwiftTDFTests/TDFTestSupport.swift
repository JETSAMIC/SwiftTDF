// TDFTestSupport.swift
// SwiftTDF — hand-built byte fixtures shared by the spec and robustness
// tests. Everything here is derived from Reference/TDF_SPECIFICATION.md,
// not from the writer, so the parser is checked against the spec itself.

import Foundation
@testable import SwiftTDF

enum Fixture {
    /// 20-byte file header.
    static let fileHeader: [UInt8] = [0x13] + Array("TheDraw FONTS file".utf8) + [0x1A]

    /// One 213-byte font header followed by `block`.
    ///
    /// - Parameters:
    ///   - glyphs: ASCII code → offset into `block`.
    ///   - blockSize: Override for the block-size field (defaults to
    ///     `block.count`).
    static func font(
        name: String = "Test",
        nameLength: UInt8? = nil,
        type: UInt8 = 0x01,
        spacing: UInt8 = 0x01,
        block: [UInt8],
        glyphs: [UInt8: UInt16],
        blockSize: UInt16? = nil
    ) -> [UInt8] {
        var out: [UInt8] = [0x55, 0xAA, 0x00, 0xFF]
        let nameBytes = Array(name.utf8.prefix(12))
        out.append(nameLength ?? UInt8(nameBytes.count))
        out += nameBytes + [UInt8](repeating: 0, count: 12 - nameBytes.count)
        out += [0, 0, 0, 0]
        out.append(type)
        out.append(spacing)
        let size = blockSize ?? UInt16(block.count)
        out += [UInt8(size & 0xFF), UInt8(size >> 8)]
        var table = [UInt8](repeating: 0xFF, count: 188)
        for (ascii, offset) in glyphs {
            let i = Int(ascii - 33) * 2
            table[i] = UInt8(offset & 0xFF)
            table[i + 1] = UInt8(offset >> 8)
        }
        out += table
        out += block
        return out
    }

    /// A three-font file (block, color, outline) laid out exactly as
    /// TheDraw writes it: fonts back to back, every font but the last with
    /// a trailing NUL counted in its block size.
    static var multiFont: Data {
        // Block font: 'A' = 2x2, 'B' shares A's offset (Copy character).
        let blockData: [UInt8] = [0x02, 0x02, 0xDB, 0xDC, 0x0D, 0xDF, 0xDB, 0x00, 0x00]
        // Color font: 'A' = 2 lines; second line is a descender ('&' with
        // no attribute byte).
        let colorData: [UInt8] = [
            0x02, 0x01,
            0xDB, 0x0C, 0xDB, 0x00, 0x0D,
            0xDF, 0x8F, 0x26, 0x00,
            0x00,
        ]
        // Outline font: 'A' using placeholder letters, '@' and 'O'.
        let outlineData: [UInt8] = [0x03, 0x02, 0x45, 0x41, 0x46, 0x0D, 0x40, 0x4F, 0x44, 0x00]
        var bytes = fileHeader
        bytes += font(name: "Blocky", type: 0x01, spacing: 0x02, block: blockData, glyphs: [0x41: 0, 0x42: 0])
        bytes += font(name: "Colory", type: 0x02, spacing: 0x01, block: colorData, glyphs: [0x41: 0])
        bytes += font(name: "Outliny", type: 0x00, spacing: 0x03, block: outlineData, glyphs: [0x41: 0])
        return Data(bytes)
    }
}

/// Deterministic SplitMix64 generator so fuzz runs are reproducible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
