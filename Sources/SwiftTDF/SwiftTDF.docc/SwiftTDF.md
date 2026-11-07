# ``SwiftTDF``

Read, write and render TheDraw Font (`.TDF`) collections.

## Overview

TheDraw was the dominant MS-DOS ANSI art editor; its `.TDF` files hold up
to 34 fonts each, in one of three types: block fonts made of CP437
characters, color fonts that add a PC attribute byte to every cell, and
outline fonts that store placeholder letters substituted at display time
through one of 19 outline styles.

SwiftTDF parses these files into value types (``TDFFontCollection``,
``TDFFont``, ``TDFCharacter``), writes them back in the layout TDFONTS.EXE
produces, and renders glyphs to grids of ``TDFRenderedCell`` holding CP437
codes and palette indices. Every offset and size in a file is treated as
untrusted; malformed input throws ``TDFError``.

## Topics

### Essentials

- <doc:GettingStarted>
- ``TDFParser``
- ``TDFWriter``
- ``TDFRenderer``

### Font model

- ``TDFFontCollection``
- ``TDFFont``
- ``TDFFontType``
- ``TDFCharacter``
- ``TDFLine``
- ``TDFCell``
- ``TDFAttribute``

### Rendering

- ``TDFRenderedCell``
- ``TDFOutlineStyle``
- ``TDFOutlineGlyphs``
- ``TDFColor``

### Errors

- ``TDFError``

### Library information

- ``SwiftTDF/SwiftTDF``
