# TheDraw Font (.TDF) Format

This is SwiftTDF's authoritative description of the TheDraw font
collection format. It is written from the public documents listed in
[§10](#10-references-and-provenance) and from black-box observation of
real `.TDF` files; no third-party source code was copied. Every place
where the circulating write-ups are wrong or silent is called out, and
[§8](#8-errata) collects the corrections in one list.

Contents:

1. [Overview](#1-overview)
2. [Conventions](#2-conventions)
3. [Byte-level layout](#3-byte-level-layout)
4. [Enumerations and code values](#4-enumerations-and-code-values)
5. [Algorithms](#5-algorithms)
6. [Semantics and de-facto behaviour](#6-semantics-and-de-facto-behaviour)
7. [Robustness guidance for readers](#7-robustness-guidance-for-readers)
8. [Errata](#8-errata)
9. [Implementation status](#9-implementation-status)
10. [References and provenance](#10-references-and-provenance)

## 1. Overview

TheDraw, by Ian E. Davis (TheSoft Programming Services), was the dominant
MS-DOS ANSI/ASCII screen editor of the late 1980s and early 1990s; its
last release was 4.63. Besides drawing screens, TheDraw can stamp large
"font" letters into a drawing — the logos, headers and group greets of
BBS-era art. Those fonts live in `.TDF` files, which are edited with the
companion program TDFONTS.EXE.

A `.TDF` file is a **collection**: one 20-byte file header followed by one
or more fonts stored back to back. Each font has a fixed 213-byte header
(name, type, spacing, data size, a 94-entry glyph offset table) and a
variable-length block of glyph data.

There are three font types, distinguished per font (not per file):

| Type | Cell size | Content |
|---|---|---|
| Outline | 1 byte | Placeholder letters `A`–`Q` that are replaced by box-drawing or block characters when the font is stamped, using one of 19 *outline styles* the user picks at that moment. |
| Block | 1 byte | Literal CP437 characters, drawn in the current colour. |
| Color | 2 bytes | A CP437 character plus a PC text-mode attribute byte per cell. |

| Property | Value |
|---|---|
| File extension | `.TDF` (case-insensitive on DOS) |
| Signature | bytes 0–19: `13` `"TheDraw FONTS file"` `1A` |
| Version field | None. The format has a single version; no variants are distinguished on disk. |
| MIME type / UTI | None registered. `application/octet-stream` is appropriate. |
| Creating programs | TheDraw 4.x and TDFONTS.EXE; later third-party font editors and converters write the same layout. |

No official specification was ever published. The format was
reverse-engineered; the most widely cited write-up is Roy/SAC's (2014),
which this document corrects in several places.

## 2. Conventions

- **Byte order.** Every multi-byte integer is little-endian. The only
  multi-byte integers are 16-bit words (`u16`).
- **Types.** `u8` and `u16` are unsigned. There are no signed or
  fixed-point fields.
- **Text.** Font names are 8-bit bytes; in practice printable ASCII.
  Glyph cell characters are CP437 code points (the IBM PC ROM character
  set), not Unicode.
- **Alignment and padding.** None. Structures are packed and follow each
  other without gaps.
- **Offsets.** "Absolute" offsets are from the start of the file.
  Glyph offsets in the offset table are relative to the first byte of the
  owning font's character data block.
- **Terminology.**
  - *Glyph*: the stored drawing for one ASCII character.
  - *Cell*: one character position in a glyph — 1 byte (outline/block) or
    2 bytes (color).
  - *Cell boundary*: a position in the glyph stream where a new cell (or a
    control byte) may begin. In color fonts the second byte of a cell is
    never at a cell boundary.
  - *Line*: one row of a glyph, ended by `0x0D` or by the glyph terminator.
  - *Descender line*: a line flagged with a trailing `&`; drawn, but not
    counted in the glyph's declared height.

## 3. Byte-level layout

### 3.1 File structure

```
offset 0            file header                 20 bytes
offset 20           font 1 header               213 bytes
offset 233          font 1 character data       BlockSize(1) bytes
233 + BS(1)         font 2 header               213 bytes
233 + BS(1) + 213   font 2 character data       BlockSize(2) bytes
...
                    optional: 0x00 font-list terminator
                    optional: 0x1A + SAUCE record (often both: see §6.7)
```

A file holding one font with no glyphs is exactly **233 bytes**.

### 3.2 File header (20 bytes)

| Offset | Size | Type | Name | Value / meaning |
|---|---|---|---|---|
| 0 | 1 | u8 | IDLength | `0x13` (19). Pascal-style length of the 18 signature characters plus the following EOF byte. |
| 1 | 18 | char[18] | Signature | ASCII `TheDraw FONTS file` (`54 68 65 44 72 61 77 20 46 4F 4E 54 53 20 66 69 6C 65`). |
| 19 | 1 | u8 | EOF | `0x1A`, the DOS end-of-file character, so `TYPE FONT.TDF` stops before the binary data. |

All 20 bytes are fixed; they are the format's only signature.

### 3.3 Font header (213 bytes, one per font)

"Rel." is the offset within the font header; "Abs." is the file offset
for the first font.

| Rel. | Abs. | Size | Type | Name | Meaning / valid range | Notes |
|---|---|---|---|---|---|---|
| 0 | 20 | 4 | u8[4] | Sentinel | `55 AA 00 FF` | The little-endian dword `0xFF00AA55`. Marks the start of every font. |
| 4 | 24 | 1 | u8 | NameLen | `1…12` | Number of meaningful bytes in Name. |
| 5 | 25 | 12 | u8[12] | Name | first NameLen bytes | Bytes past NameLen are undefined (NUL, spaces or leftovers from an earlier, longer name). |
| 17 | 37 | 4 | u8[4] | Reserved | — | Observed as zero. Purpose unknown; preserve or write zero. |
| 21 | 41 | 1 | u8 | FontType | `0`, `1`, `2` | See [§4.1](#41-font-type). |
| 22 | 42 | 1 | u8 | Spacing | `0x01…0x29` | Stored value is spacing + 1, i.e. `0x01` = 0, `0x29` = 40. Semantics: [§6.3](#63-the-spacing-byte). |
| 23 | 43 | 2 | u16 | BlockSize | `0…65535` | Length in bytes of this font's character data block, including the in-block NUL of a non-final font ([§3.4](#34-locating-fonts)). |
| 25 | 45 | 188 | u16[94] | Offsets | `0…BlockSize-1`, or `0xFFFF` | One entry per ASCII code 33 (`!`) through 126 (`~`), in order. Entry *i* belongs to character `33 + i`. `0xFFFF` = glyph not defined. |
| 213 | 233 | BlockSize | u8[] | CharData | — | The glyph records ([§3.5](#35-glyph-record)). |

Space (32) and DEL (127) have no table entry; the format cannot store
a glyph for them.

### 3.4 Locating fonts

Fonts follow each other with no gap: the header of font *n*+1 starts
`BlockSize(n)` bytes after the start of font *n*'s character data.

```
header(1) = 20
data(n)   = header(n) + 213
header(n) = data(n-1) + BlockSize(n-1)
```

TDFONTS.EXE appends one `0x00` to the character data of every font
**except the last**, and that byte **is counted in the font's
BlockSize**. Nothing separates fonts outside their blocks. The last font
has no such byte.

A reader therefore walks the file like this: at each font boundary, if
the input has ended, or the next byte is `0x00` (a font-list terminator
some writers append after the last font), or `0x1A` (the start of a
trailing SAUCE record), the font list is over; otherwise a font header
must begin there. Pseudocode is in [§5.1](#51-reading-a-collection).

### 3.5 Glyph record

Each defined offset-table entry points at a glyph record inside the
character data block:

| Offset | Size | Type | Name | Meaning / valid range | Notes |
|---|---|---|---|---|---|
| 0 | 1 | u8 | MaxWidth | `1…30` (`0x1E`) | Width of the glyph's box in cells. |
| 1 | 1 | u8 | MaxHeight | `1…12` (`0x0C`) | Number of lines **excluding descender lines**. Used to advance to the next text row; never use it to bound the read. |
| 2 | … | — | Cells | — | Cell stream ([§3.6](#36-cell-stream)), ended by `0x00`. |

### 3.6 Cell stream

At every cell boundary, three byte values are control codes in **all**
font types. Each occupies exactly one byte — in color fonts none of them
is followed by an attribute byte.

| Byte | Name | Meaning |
|---|---|---|
| `0x00` | Terminator | End of glyph. TDFONTS.EXE writes it directly after the last cell (`… cell 00`); the form `… cell 0D 00` also occurs and is equivalent. |
| `0x0D` | Line end | Ends the current line and starts the next. |
| `0x26` `&` | Marker | When it is the last item of a line, that line is a descender line ([§6.2](#62-descender-lines)). It is not drawn. |

Any other byte starts a cell:

| FontType | Cell layout |
|---|---|
| Outline (`0`) | 1 byte: placeholder letter ([§4.4](#44-outline-placeholder-letters)) or literal character. |
| Block (`1`) | 1 byte: CP437 character. |
| Color (`2`) | 2 bytes: CP437 character, then attribute byte ([§4.3](#43-attribute-byte)). The attribute may be any value including `0x00`, `0x0D` and `0x26`; it is never interpreted as a control code. |

Lines may be shorter than MaxWidth; positions past the end of a line are
**transparent** (they do not overwrite what is underneath when stamped).
Glyphs are therefore not rectangular in storage.

Several offset-table entries may point at the **same** glyph record.
TDFONTS.EXE's *Copy character* command does this until the copy is
edited; it is the only way a large color font fits the 16-bit offset
space ([§6.8](#68-limits)).

## 4. Enumerations and code values

### 4.1 Font type

| Value | Name | Cell size |
|---|---|---|
| `0x00` | Outline | 1 |
| `0x01` | Block | 1 |
| `0x02` | Color | 2 |
| `0x03…0xFF` | undefined | — |

No program is known to write other values. Because the cell size depends
on the type, a reader cannot decode a font with an unknown type and
should reject it.

### 4.2 Special cell characters

| Byte | Font types | Meaning |
|---|---|---|
| `0xFF` | Block, Color | **Hard blank**: an opaque blank cell. It overwrites the destination with a space (in color fonts, in the cell's attribute) instead of leaving it transparent. In color fonts it is an ordinary 2-byte cell (character `0xFF` + attribute). CP437 `0xFF` is itself a blank glyph (non-breaking space), so drawing the byte literally is also correct. |
| `0x20` | all | Ordinary space: drawn as a space (opaque) when present in a line. |
| `@` `0x40` | Outline | Leading-space filler: a transparent position before the first visible cell of a line. |
| `O` `0x4F` | Outline | Hard space: an opaque blank inside the outline (fills a letter's interior so it covers the background). |

### 4.3 Attribute byte

Color-font cells use the standard IBM PC text-mode attribute:

| Bits | Mask | Meaning |
|---|---|---|
| 0–3 | `0x0F` | Foreground colour, palette index 0–15. |
| 4–6 | `0x70` | Background colour, palette index 0–7. |
| 7 | `0x80` | Blink. On displays in "iCE colour" (high-intensity background) mode, this bit instead selects background 8–15. |

Palette (standard IBM CGA/EGA/VGA text-mode colours; RGB as used by
SwiftTDF's `TDFColor`):

| Index | Name | RGB | Index | Name | RGB |
|---|---|---|---|---|---|
| 0 | Black | `00 00 00` | 8 | Dark Gray | `55 55 55` |
| 1 | Blue | `00 00 AA` | 9 | Bright Blue | `55 55 FF` |
| 2 | Green | `00 AA 00` | 10 | Bright Green | `55 FF 55` |
| 3 | Cyan | `00 AA AA` | 11 | Bright Cyan | `55 FF FF` |
| 4 | Red | `AA 00 00` | 12 | Bright Red | `FF 55 55` |
| 5 | Magenta | `AA 00 AA` | 13 | Bright Magenta | `FF 55 FF` |
| 6 | Brown | `AA 55 00` | 14 | Yellow | `FF FF 55` |
| 7 | Light Gray | `AA AA AA` | 15 | White | `FF FF FF` |

TheDraw's default attribute for new cells is `0x07` (light gray on
black). Block and outline fonts carry no colour; they are drawn in
whatever colour is current when stamped.

### 4.4 Outline placeholder letters

Outline glyphs describe the *edges* of a letter shape. Each placeholder
names a kind of edge or corner; the outline style chosen at stamping
time decides which CP437 character draws it. The roles below are
derived from the style table ([§4.5](#45-outline-styles)): in styles 0–15
every corner and tee is exactly the box-drawing join of the two edge
letters listed, which pins down what each letter means.

"Outer" corners are convex corners of the letter's outline; "inner"
corners are concave ones, which includes every corner of an enclosed
counter (the hole in `O`, `A`, `B`…). Roy/SAC's "(outside)" and
"(inside)" annotations refer to the outer contour and to counters
respectively.

| Letter | Role | Joins | Shape | Style 9 |
|---|---|---|---|---|
| `A` | Top edge (solid below) | — | horizontal | `CD` ═ |
| `B` | Bottom edge (solid above) | — | horizontal | `C4` ─ |
| `C` | Left edge (solid to the right) | — | vertical | `B3` │ |
| `D` | Right edge (solid to the left) | — | vertical | `BA` ║ |
| `E` | Outer corner, top-left | A + C | ┌ | `D5` ╒ |
| `F` | Outer corner, top-right | A + D | ┐ | `BB` ╗ |
| `G` | Inner corner, ┌-shaped (top-left of a counter) | B + D | ┌ | `D6` ╓ |
| `H` | Inner corner, ┐-shaped (top-right of a counter) | B + C | ┐ | `BF` ┐ |
| `I` | Inner corner, └-shaped (bottom-left of a counter) | A + D | └ | `C8` ╚ |
| `J` | Inner corner, ┘-shaped (bottom-right of a counter) | A + C | ┘ | `BE` ╛ |
| `K` | Outer corner, bottom-left | B + C | └ | `C0` └ |
| `L` | Outer corner, bottom-right | B + D | ┘ | `BD` ╜ |
| `M` | Tee: left-edge vertical with a top edge joining from the left | A + C | ┤ | `B5` ╡ |
| `N` | Tee: right-edge vertical with a bottom edge leaving to the right | B + D | ├ | `C7` ╟ |
| `O` | Hard space (opaque blank inside the letter) | — | — | blank |
| `P` | Blank in every style | — | — | blank |
| `Q` | Blank in every style | — | — | blank |
| `@` | Leading-space filler (transparent) | — | — | transparent |
| `&` | Descender marker (control code, [§3.6](#36-cell-stream)) | — | — | — |

Any other byte in an outline glyph is drawn as the literal CP437
character.

The TDFONTS.EXE editor shows `O` as `≈` (`0xF7`) while editing so the
designer can see it; that is a display aid only. When text is stamped
`O` is a blank in every style.

### 4.5 Outline styles

TheDraw offers 19 outline styles, numbered here 0–18 in the order the
program lists them. The table gives the CP437 byte for placeholders
`A`…`N`; `O`, `P` and `Q` are `0x20` in every style.

Styles 0–15 enumerate single/double lines: **bit 0** of the style number
doubles `A` (top edges), **bit 1** `B` (bottom edges), **bit 2** `C` (left
edges), **bit 3** `D` (right edges), and every corner/tee is the matching
mixed single/double join. Styles 16–18 use half and full blocks.

| Style | A | B | C | D | E | F | G | H | I | J | K | L | M | N |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | C4 | C4 | B3 | B3 | DA | BF | DA | BF | C0 | D9 | C0 | D9 | B4 | C3 |
| 1 | CD | C4 | B3 | B3 | D5 | B8 | DA | BF | D4 | BE | C0 | D9 | B5 | C3 |
| 2 | C4 | CD | B3 | B3 | DA | BF | D5 | B8 | C0 | D9 | D4 | BE | B4 | C6 |
| 3 | CD | CD | B3 | B3 | D5 | B8 | D5 | B8 | D4 | BE | D4 | BE | B5 | C6 |
| 4 | C4 | C4 | BA | B3 | D6 | BF | DA | B7 | C0 | BD | D3 | D9 | B6 | C3 |
| 5 | CD | C4 | BA | B3 | C9 | B8 | DA | B7 | D4 | BC | D3 | D9 | B9 | C3 |
| 6 | C4 | CD | BA | B3 | D6 | BF | D5 | BB | C0 | BD | C8 | BE | B6 | C6 |
| 7 | CD | CD | BA | B3 | C9 | B8 | D5 | BB | D4 | BC | C8 | BE | B9 | C6 |
| 8 | C4 | C4 | B3 | BA | DA | B7 | D6 | BF | D3 | D9 | C0 | BD | B4 | C7 |
| 9 | CD | C4 | B3 | BA | D5 | BB | D6 | BF | C8 | BE | C0 | BD | B5 | C7 |
| 10 | C4 | CD | B3 | BA | DA | B7 | C9 | B8 | D3 | D9 | D4 | BC | B4 | CC |
| 11 | CD | CD | B3 | BA | D5 | BB | C9 | B8 | C8 | BE | D4 | BC | B5 | CC |
| 12 | C4 | C4 | BA | BA | D6 | B7 | D6 | B7 | D3 | BD | D3 | BD | B6 | C7 |
| 13 | CD | C4 | BA | BA | C9 | BB | D6 | B7 | C8 | BC | D3 | BD | B9 | C7 |
| 14 | C4 | CD | BA | BA | D6 | B7 | C9 | BB | D3 | BD | C8 | BC | B6 | CC |
| 15 | CD | CD | BA | BA | C9 | BB | C9 | BB | C8 | BC | C8 | BC | B9 | CC |
| 16 | DC | DC | DB | DB | DC | DC | DC | DC | DB | DB | DB | DB | DB | DB |
| 17 | DF | DF | DB | DB | DB | DB | DB | DB | DF | DF | DF | DF | DB | DB |
| 18 | DF | DC | DE | DD | DE | DD | DC | DC | DF | DF | DE | DD | DB | DB |

The same rows as characters, for the four corner styles and the block
styles:

| Style | A B C D E F G H I J K L M N |
|---|---|
| 0 | `─ ─ │ │ ┌ ┐ ┌ ┐ └ ┘ └ ┘ ┤ ├` |
| 9 | `═ ─ │ ║ ╒ ╗ ╓ ┐ ╚ ╛ └ ╜ ╡ ╟` |
| 15 | `═ ═ ║ ║ ╔ ╗ ╔ ╗ ╚ ╝ ╚ ╝ ╣ ╠` |
| 16 | `▄ ▄ █ █ ▄ ▄ ▄ ▄ █ █ █ █ █ █` |
| 17 | `▀ ▀ █ █ █ █ █ █ ▀ ▀ ▀ ▀ █ █` |
| 18 | `▀ ▄ ▐ ▌ ▐ ▌ ▄ ▄ ▀ ▀ ▐ ▌ █ █` |

Evidence: the table is the one TheDraw uses as extracted by the
icy_tools/retrofont project; style 9 matches Roy/SAC's independently
published letter table byte for byte, and styles 0–15 satisfy the
bit-composition rule above for every cell (checked mechanically).

Style 9 (double top edges and double right edges, single elsewhere)
is the mapping Roy/SAC publishes as *the* outline table. TheDraw's
documentation, as quoted by Roy/SAC, gives the drawing rules for
designers: double lines are always the **rightmost** side of a column
and the **topmost** side of a beam. That is exactly what makes `A` a
top edge and `D` a right edge. The rules are a design convention; the
file format does not enforce them, and a glyph that breaks them loads
fine but joins wrongly in other styles.

## 5. Algorithms

### 5.1 Reading a collection

```
read_collection(file):
    require len(file) >= 20 and file[0..20] == 13 "TheDraw FONTS file" 1A
    pos = 20
    fonts = []
    loop:
        if pos == len(file):            break      # no terminator: fine
        if file[pos] == 0x1A:           break      # SAUCE follows
        if file[pos] == 0x00:
            if file[pos+1..pos+5] == 55 AA 00 FF:
                pos += 1                            # stray separator (non-TheDraw writer)
            else:
                break                               # font-list terminator
        require file[pos..pos+4] == 55 AA 00 FF
        require pos + 213 <= len(file)
        nameLen   = min(file[pos+4], 12)
        name      = file[pos+5 .. pos+5+nameLen]
        type      = file[pos+21]                   # 0, 1 or 2, else reject
        spacing   = file[pos+22] - 1               # see §6.3
        blockSize = u16le(file, pos+23)
        offsets   = 94 × u16le starting at pos+25
        data      = pos + 213
        require data + blockSize <= len(file)
        block     = file[data .. data+blockSize]
        for i in 0..<94 where offsets[i] != 0xFFFF:
            require offsets[i] < blockSize
            glyph[33+i] = decode_glyph(block, offsets[i], type)   # cache by offset
        fonts.append(...)
        pos = data + blockSize
    return fonts
```

### 5.2 Decoding a glyph

```
decode_glyph(block, start, type):
    require start + 2 <= len(block)
    width  = block[start];  height = block[start+1]
    p = start + 2
    lines = [];  cells = []
    while p < len(block):
        b = block[p]
        if b == 0x00:                    # terminator
            if cells not empty: finish_line()
            return (width, height, lines)
        if b == 0x0D:                    # line end
            finish_line();  p += 1;  continue
        if b == 0x26:                    # '&' marker: 1 byte in every type
            cells.append(MARKER);  p += 1;  continue
        if type == COLOR:
            require p + 1 < len(block)
            cells.append(cell(b, attr = block[p+1]));  p += 2
        else:
            cells.append(cell(b));  p += 1
    # ran off the block without a terminator (non-TheDraw writers)
    if cells not empty: finish_line()
    return (width, height, lines)

finish_line():
    descender = cells not empty and last(cells) == MARKER
    if descender: drop last(cells)
    lines.append(cells, descender);  cells = []
```

`… cell 0D 00` and `… cell 00` decode identically: the `0x0D` finishes
the last line, and the `0x00` then finds no pending cells.

### 5.3 Writing a collection (what TDFONTS.EXE produces)

```
write_collection(fonts):
    emit 13 "TheDraw FONTS file" 1A
    for each font f (index n, last = n == count-1):
        block = []; seen = {}                         # encoded glyph -> offset
        offsets = [0xFFFF] × 94
        for c in 33...126 where f defines c:
            g = encode_glyph(f[c])
            if g in seen: offsets[c-33] = seen[g]; continue
            require len(block) <= 0xFFFE               # 0xFFFF means "undefined"
            offsets[c-33] = seen[g] = len(block); block += g
        if not last: block += 00                      # in-block terminator
        require len(block) <= 0xFFFF
        emit 55 AA 00 FF, len(name), name padded to 12 with 00, 00 00 00 00,
             type, spacing + 1, u16le(len(block)), offsets as u16le, block

encode_glyph(g):
    out = [min(width,30), min(height,12)]
    for each line L (index k):
        for each cell: out += code; if COLOR and code != '&': out += attr
        if L.descender: out += '&'
        if k is not the last line, or L is empty and not a descender: out += 0D
    out += 00
```

The extra `0x0D` for an empty final line is needed only so that the
empty line survives a round trip; TDFONTS.EXE never stores one.

### 5.4 Stamping a glyph (rendering)

```
stamp(glyph, type, x, y, style, currentAttr):
    row = y
    for each line L in glyph.lines (descenders included, in order):
        col = x
        for each cell in L:
            case type:
              OUTLINE:
                if code == '@':           leave destination untouched
                elif 'A' <= code <= 'Q':  put(style[code - 'A'], currentAttr)  # O,P,Q -> blank
                else:                     put(code, currentAttr)
              BLOCK:                      put(code, currentAttr)       # 0xFF = opaque blank
              COLOR:                      put(code, cell.attr)         # 0xFF = opaque blank
            col += 1
        # positions col ..< x + width are transparent
        row += 1
```

Text layout across several glyphs is not stored in the file;
[§6.4](#64-laying-out-text) describes the de-facto conventions.

## 6. Semantics and de-facto behaviour

### 6.1 MaxWidth and MaxHeight

The glyph header values are the glyph's box as recorded by
TDFONTS.EXE. MaxWidth is the advance width of the glyph; lines shorter
than it are padded with transparency. MaxHeight counts only the
non-descender lines. Neither is a reliable bound on the data: a glyph
may store fewer lines than MaxHeight (the rest are transparent) and,
with descenders, more. Readers must always read to the terminator.

### 6.2 Descender lines

A line whose last item is `&` is a descender line: it is drawn below the
glyph's body but excluded from MaxHeight, so that a run like `Aa Qq Pp`
keeps a common baseline and the next text row starts MaxHeight rows
below the current one. Descender lines are, in practice, the final lines
of a glyph. Characters that commonly carry them: `$ , ; _ Q g j p q y`.
Example: a glyph with six lines, the last two ending in `&`, declares
MaxHeight = 4.

An `&` that is *not* the last item of its line has no documented
meaning. It is still a one-byte control code. De-facto readers differ in
how they draw it: retrofont skips it without advancing the column;
SwiftTDF keeps it as a transparent cell that occupies one column. A
writer should never produce one.

### 6.3 The Spacing byte

Roy/SAC calls byte 42 "letter spacing" and documents the stored range
`0x01…0x29` as 0–40. How the value is applied is not documented by any
primary source, and de-facto programs disagree:

| Program | Interpretation |
|---|---|
| tdfiglet | Inserts *raw byte value* blank columns after every glyph (no −1 adjustment), so a stored `0x01` gives one column. |
| retrofont | Uses the value only as the width of the space character (which the font cannot define). |
| SwiftTDF | Exposes the decoded value (stored − 1) as `letterSpacing` and leaves layout to the caller. |

Readers should accept `0x00` (seen in files from some converters) and
treat it as zero spacing.

### 6.4 Laying out text

The file stores glyphs only; no primary source describes how TheDraw
composes a string. Recommended conventions, consistent with de-facto
renderers:

- Advance by MaxWidth after each glyph, plus any letter spacing
  ([§6.3](#63-the-spacing-byte)).
- Characters with no glyph (including space, which can never have one)
  are either skipped or rendered as a blank of some width; there is no
  stored width for them.
- Characters are looked up as-is: lower-case letters are distinct
  glyphs. Many fonts define only one case; a renderer may fall back to
  the other case.
- A new text row starts the largest MaxHeight of the row below the
  current one (descender lines hang into the gap).

### 6.5 Opaque versus transparent

Blank cells come from several sources, and renderers must keep them apart:

| Source | Effect when stamped |
|---|---|
| Past the end of a line | transparent |
| `@` in an outline glyph | transparent |
| `0x20` in any glyph | opaque space |
| `O` in an outline glyph | opaque space |
| `0xFF` in a block or color glyph | opaque space (hard blank) |

### 6.6 Name field

TDFONTS.EXE accepts up to 12 characters. Files written by other tools
sometimes store a NameLen above 12 (readers clamp to 12), a NameLen of 0,
or NUL bytes inside the declared length (readers drop them). Bytes past
NameLen are undefined and must be ignored.

### 6.7 Trailers after the last font

Distributed `.TDF` files often carry a SAUCE record (128 bytes, optionally
preceded by a COMNT block) appended by archivers, introduced by a `0x1A`
byte. Some writers append a `0x00` after the last font (a font-list
terminator), sometimes followed by SAUCE as well. Readers stop at either
byte at a font boundary. The leading `0x1A` of the SAUCE convention
cannot be confused with a font header, which always starts with `0x55`.

### 6.8 Limits

| Limit | Value | Source |
|---|---|---|
| Fonts per file | 34 | TDFONTS.EXE; not a format limit. |
| Glyph width | 30 | TDFONTS.EXE. |
| Glyph height | 12 body lines, plus descenders | TDFONTS.EXE. |
| Character data per font | 65,535 bytes | 16-bit BlockSize. |
| Glyph start offset | `0xFFFE` | `0xFFFF` is reserved for "undefined". |

A fully populated color font does not fit: 94 glyphs × (2 + 30×12×2 +
11 line ends + 1 terminator) is 68,996 bytes. Sharing identical glyphs
via the offset table is the designer's workaround.

### 6.9 Reserved bytes

The four bytes at font-header offset 17 have never been observed
non-zero in TheDraw output. Writers should store zero.

## 7. Robustness guidance for readers

Every field after the signature is untrusted.

| Field | Hazard | Guidance |
|---|---|---|
| File length | shorter than 20 or 233 bytes | Reject as truncated; a bare 20-byte header may be treated as an empty collection. |
| Sentinel | missing at a font boundary | Reject the file (or stop, keeping earlier fonts); do not scan for the next sentinel. |
| NameLen | > 12 | Clamp to 12. |
| FontType | > 2 | Reject: the cell size is unknown. |
| Spacing | > `0x29` | Out of the documented range; either reject or clamp. |
| BlockSize | larger than the remaining input | Reject as truncated. |
| Offsets | `>= BlockSize` (but not `0xFFFF`) | Reject (or drop that glyph). |
| Shared offsets | many entries → one record | Decode once and reuse; never decode the same bytes 94 times. |
| Glyph stream | no terminator before the block end | Accept what was decoded; TheDraw always terminates, other writers sometimes do not. |
| Color cell | character byte is the last byte of the block | Reject as truncated. |
| Glyph size | thousands of cells in one glyph | Cap per-line cells, lines and total cells well above TheDraw's 30×12 and reject beyond. |
| Font count | > 34 | Format allows it; a reader may cap it to bound work. |
| Trailing data | bytes after the last font that are neither `00`, `1A` nor a sentinel | Treat as corruption, or ignore if a lenient mode is wanted. |

Arithmetic on offsets is at most 16-bit plus a file position; use
checked or wide integers so a hostile BlockSize cannot overflow.

## 8. Errata

### 8.1 Roy/SAC, "TheDraw Fonts File (.TDF) Specifications" (2014)

1. **Empty-file and header sizes.** The write-up says an empty fonts file
   is 232 bytes and each further font adds 212 bytes. Its own offset
   table (font header at bytes 20–232, character data at 233) gives a
   **213-byte** font header and a **233-byte** single-font file, which is
   also what every de-facto reader and distributed files agree on.
2. **Next-font formulas.** "Font 2 header = 232 + Font 1 BlockSize + 1"
   is numerically right (= 233 + BlockSize) but the explanation implies
   a separator byte outside the block. "Font 3 header = Font 2 data +
   Font 2 BlockSize + 1" is **off by one**: the correct value is
   Font 2 data + Font 2 BlockSize, because the NUL ending a non-final
   font is the last byte *inside* its BlockSize.
3. **Glyph terminator.** "Each line ends with 0Dh; the character ends with
   00h" suggests `… 0D 00`; TDFONTS.EXE writes the NUL directly after the
   last cell. Both forms occur and must be accepted.
4. **`&` in color fonts** occupies one byte with no attribute byte. Not
   stated in the write-up; following it literally (two bytes per cell)
   swallows the next line break as an attribute.
5. **Hard space `O`** is listed with code `0xF7` (≈). That is only how
   the editor visualises it; TheDraw stamps it as a blank in every
   outline style.
6. **Attribute bit 7.** The colour byte is described as background
   = value ÷ 16 with range 0–7, which is contradictory for values
   ≥ `0x80`. Bits 4–6 are the background and bit 7 is blink / iCE
   high-intensity background.
7. **Hard blank `0xFF`** in block and color glyphs is not mentioned.
8. **Maximum offset** is given as "65534 (FEh)"; the value is `0xFFFE`.
9. **Letters A–D, M, N** are listed without a description. Their roles
   follow from the style table ([§4.4](#44-outline-placeholder-letters)).
10. **Outline styles.** Only one mapping (style 9) is given; TheDraw has
    19 and the file does not record which one a font was designed for.
11. **Spacing** semantics are not described ([§6.3](#63-the-spacing-byte)).

### 8.2 JETSAMIC `specs/art/tdf.md` (before its 2026 revision)

1. The `+1` in "font_2_header = 232 + font_1_blocksize + 1" was explained
   as the NUL terminator living between fonts; it is inside BlockSize.
2. The character-data ceiling was given as 65,534 bytes; BlockSize
   allows 65,535 bytes, while the last glyph must *start* at or below
   `0xFFFE`.
3. `A` was labelled "horizontal double" and `M`/`N` "right/left tee" as
   though fixed; whether a letter is single or double depends on the
   outline style. Roles are now given as edge/corner semantics.
4. TheDraw's drawing rule was quoted as "double lines are the outermost
   edge of a column"; the rule (as quoted by Roy/SAC) says **rightmost**.
5. The colour byte was described as nibbles with background 0–7,
   omitting bit 7.

### 8.3 Earlier SwiftTDF documentation and behaviour (before 0.1.0)

1. The font header was taken to be 212 bytes (`fontHeaderSize`).
2. `&` in color fonts consumed an attribute byte.
3. Multi-font files were walked with a separator byte outside the block.
4. Outline `O` was rendered as `0xF7` instead of a blank.
5. The previous reference (`TDF_SPECIFICATION.md`) attributed role
   descriptions for `A`–`D` to Roy/SAC, who does not describe them.

## 9. Implementation status

| Section | Feature | SwiftTDF |
|---|---|---|
| 3.2 | File signature | Supported |
| 3.3 | Font sentinel `55 AA 00 FF` | Supported |
| 3.3 | Name: NameLen + 12-byte buffer | Supported (NameLen clamped to 12; decoded as printable ASCII, other bytes dropped) |
| 3.3 | Reserved bytes | Read and ignored; written as zero |
| 3.3, 4.1 | Font types 0, 1, 2 | Supported; other values throw `invalidFontType` |
| 3.3, 6.3 | Spacing `0x01…0x29` | Supported as decoded `letterSpacing`; `0x00` read as 0; values above `0x29` throw `invalidLetterSpacing` |
| 3.3 | BlockSize, offset table, `0xFFFF` | Supported, bounds-checked |
| 3.4 | Back-to-back fonts with in-block NUL | Supported (read and write) |
| 3.4, 6.7 | `0x00` font-list terminator, `0x1A` + SAUCE | Supported (read); SAUCE content is not decoded |
| 3.4 | Stray NUL outside BlockSize before a sentinel | Supported (read) |
| 3.5 | MaxWidth / MaxHeight | Stored as declared; writer clamps to 30 × 12 |
| 3.6 | `0x0D`, `0x00` (bare and after `0x0D`) | Supported |
| 3.6, 6.2 | `&` descender marker, 1 byte in all types | Supported (`TDFLine.isDescender`); mid-line `&` kept as a transparent cell |
| 3.6 | Shared offsets | Supported (decoded once; writer deduplicates identical glyphs) |
| 4.2 | `0xFF` hard blank (block/color) | Supported (`TDFRenderedCell.isHardSpace`) |
| 4.2, 4.4 | `O` hard space, `@` filler | Supported |
| 4.3 | Attribute fg/bg/blink | Supported (`TDFAttribute`) |
| 4.3 | Palette | Supported (`TDFColor`) |
| 4.5 | 19 outline styles | Supported (`TDFOutlineStyle`, default style 9) |
| 5.3 | Writer layout as TDFONTS.EXE | Supported |
| 5.4 | Per-glyph stamping | Supported (`TDFRenderer`, pure data) |
| 6.4 | Laying out a whole string | Not supported (left to the caller) |
| 6.8 | 34-font limit | Enforced on read and write (`tooManyFonts`) |
| 7 | Glyph work caps | 255 cells per line, 255 lines, 4,096 cells per glyph |
| — | CP437 → Unicode | Not supported (cells are CP437 bytes) |
| — | Editor drawing-rule validation | Not supported (not part of the format) |

## 10. References and provenance

- Carsten "Roy/SAC" Cumbrowski, "TheDraw Fonts File (.TDF)
  Specifications", 23 April 2014,
  <https://www.roysac.com/blog/2014/04/thedraw-fonts-file-tdf-specifications/>.
  The primary public write-up; corrected in [§8.1](#81-roysac-thedraw-fonts-file-tdf-specifications-2014).
- Ian E. Davis, TheDraw 4.x and TDFONTS.EXE, with their on-line help.
- JETSAMIC specs collection, `art/tdf.md`, which carries the same
  content in the collection's own format.
- Mike Krüger, icy_tools and the `retrofont` crate: de-facto reader and
  renderer, and the source of the outline style table as extracted from
  TheDraw.
- tat3r, `tdfiglet`: de-facto color-font renderer (spacing behaviour in
  [§6.3](#63-the-spacing-byte)).

Provenance: this document was written from the public documents listed
above and black-box observation of `.TDF` files and of program output.
No third-party source code was copied; numeric tables (offsets, the
outline style table, the palette) are facts of the format.
