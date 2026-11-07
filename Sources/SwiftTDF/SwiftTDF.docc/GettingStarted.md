# Getting Started

Load a `.TDF` file, render a glyph, and save the collection again.

## Parse a file

``TDFParser/parse(_:)`` takes the complete file contents and returns a
``TDFFontCollection``. It throws ``TDFError`` for anything malformed.

```swift
import Foundation
import SwiftTDF

let data = try Data(contentsOf: url)
let collection = try TDFParser.parse(data)
for font in collection.fonts {
    print(font.name, font.type, font.characters.count)
}
```

Glyphs are keyed by ASCII code, `33...126` (`!` through `~`). The space
character is never stored.

## Render a glyph

``TDFRenderer/render(_:type:defaultAttribute:outlineStyle:)`` turns a
``TDFCharacter`` into rows of ``TDFRenderedCell``. Each cell holds a CP437
byte and foreground/background indices into ``TDFColor/rgb``.

```swift
if let font = collection.fonts.first, let glyph = font[0x41] {
    for row in TDFRenderer.render(glyph, type: font.type) {
        for cell in row where !cell.isFiller {
            draw(cell.code, fg: TDFColor.rgb[Int(cell.foreground)],
                 bg: TDFColor.rgb[Int(cell.background)])
        }
    }
}
```

- Block fonts use the `defaultAttribute` you pass (light gray on black by
  default).
- Color fonts use each cell's own ``TDFAttribute``.
- Outline fonts substitute placeholder letters through a
  ``TDFOutlineStyle``; pass `outlineStyle:` to pick one of TheDraw's 19.

Rows may be shorter than ``TDFCharacter/maxWidth``; the missing positions
are transparent. Lines flagged ``TDFLine/isDescender`` hang below the
baseline and are not counted in ``TDFCharacter/maxHeight``.

## Write a file

``TDFWriter/encode(_:)`` produces the bytes TDFONTS.EXE would save,
sharing storage between byte-identical glyphs.

```swift
let bytes = try TDFWriter.encode(collection)
try bytes.write(to: outputURL)
```

The writer clamps soft limits (names to 12 ASCII characters, spacing to 40,
glyph headers to 30 × 12) and throws for data the format cannot represent,
such as more than 34 fonts or more than 64 KiB of character data in one
font.
