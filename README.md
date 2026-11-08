# SwiftTDF

Read, write and render TheDraw Font (`.TDF`) files in Swift.

SwiftTDF decodes the font collections used by TheDraw, the classic MS-DOS
ANSI art editor, into a value-type model, writes them back in the layout
TDFONTS.EXE produces, and rasterizes glyphs to a pure-data grid of CP437
cells your own UI layer can paint (SwiftUI, AppKit, UIKit, a terminal, an
HTML canvas — that part is up to you).

## Requirements

- iOS 17+, iPadOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+
- Swift 6.0+ / Xcode 16+
- No dependencies beyond Foundation

## Installation

Add SwiftTDF to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/JETSAMIC/SwiftTDF.git", from: "0.1.0"),
],
```

and to the targets that use it:

```swift
.target(
    name: "MyApp",
    dependencies: ["SwiftTDF"]
)
```

## Quick start

```swift
import Foundation
import SwiftTDF

let data = try Data(contentsOf: URL(fileURLWithPath: "ROY.TDF"))
let collection = try TDFParser.parse(data)

for font in collection.fonts {
    print("\(font.name) [\(font.type)] — \(font.characters.count) glyphs")
}

// Render 'A' from the first font.
if let font = collection.fonts.first, let glyph = font[0x41] {
    for row in TDFRenderer.render(glyph, type: font.type) {
        for cell in row where !cell.isFiller {
            // cell.code is a CP437 byte; colors index TDFColor.rgb.
            let fg = TDFColor.rgb[Int(cell.foreground)]
            let bg = TDFColor.rgb[Int(cell.background)]
            _ = (cell.code, fg, bg)
        }
    }
}

// Write the collection back out.
let bytes = try TDFWriter.encode(collection)
try bytes.write(to: URL(fileURLWithPath: "OUT.TDF"))
```

Outline fonts are drawn through one of TheDraw's 19 outline styles:

```swift
let style = TDFOutlineStyle(index: 15)!   // all double lines
let rows = TDFRenderer.render(glyph, type: .outline, outlineStyle: style)
```

All parsing errors are thrown as `TDFError`, with the font index, ASCII code
or byte offset involved. The parser never traps on malformed input.

## Format coverage

| Feature | Status |
|---|---|
| File signature `0x13 "TheDraw FONTS file" 0x1A` | Supported |
| Font sentinel `55 AA 00 FF` | Supported |
| Multiple fonts per file (back to back, in-block NUL) | Supported (read + write) |
| Font-list terminator `0x00`, trailing SAUCE after `0x1A` | Supported (read; SAUCE content ignored) |
| Separator NUL outside block size (non-TheDraw writers) | Supported (read) |
| Font name: length byte + 12-byte padded buffer | Supported (clamped to 12, printable ASCII) |
| Font types: outline / block / color | Supported |
| Letter spacing `0x01…0x29` | Supported (`0x00` read as 0) |
| Block size / 94-entry offset table, `0xFFFF` undefined | Supported, bounds-checked |
| Shared offsets ("Copy character") | Supported (decoded once; writer deduplicates) |
| Glyph width / height header | Supported (stored as declared; writer clamps to 30 × 12) |
| `0x0D` line break, `0x00` terminator (bare and after CR) | Supported |
| `&` descender marker (1 byte, no attribute in color fonts) | Supported |
| Color attribute: fg, bg, blink bit | Supported |
| `0xFF` hard blank (block/color) | Supported (flagged `isHardSpace`) |
| Outline placeholders `A`–`Q`, `O` hard space, `@` filler | Supported |
| TheDraw's 19 outline styles | Supported (`TDFOutlineStyle`, default style 9) |
| CP437 output | Supported (cells carry CP437 bytes; Unicode conversion is left to the caller) |
| Laying out a whole string (letter spacing, space width) | Not supported |
| Editor drawing-rule validation for outline fonts | Not supported (format does not enforce it) |
| SAUCE metadata | Not supported (skipped) |

## Limitations

- Rendering is per glyph. Composing a string (applying `letterSpacing`,
  choosing a width for the space character, baseline alignment with
  descenders) is left to the caller.
- Cells are CP437 bytes; map them to Unicode or a bitmap font yourself.
- The parser rejects glyphs with more than 255 cells per line, 255 lines or
  4,096 cells in total (`TDFParser.maxCellsPerLine` etc.); TheDraw's own
  limit is 30 × 12.
- More than 34 fonts in one file is rejected, matching TDFONTS.EXE.

## Specification

The format reference ships with the repository:
[Reference/TDF-Format.md](Reference/TDF-Format.md). It
covers every byte of the format, the outline placeholder roles and all 19
outline styles, documents where the published Roy/SAC write-up is wrong
(header sizes, multi-font layout, glyph terminator, `&` in color fonts) and
maps each feature to SwiftTDF's support.

## Credits

- Roy/SAC (Carsten Cumbrowski), "TheDraw Fonts File (.TDF) Specifications",
  2014: <https://www.roysac.com/blog/2014/04/thedraw-fonts-file-tdf-specifications/>
- The outline style table as extracted from TheDraw by Mike Krüger's
  icy_tools / `retrofont` project.

## License

MIT. See [LICENSE](LICENSE).
