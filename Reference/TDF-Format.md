# TheDraw Font (.TDF) File Format Specification

> Primary source: Roy/SAC (Carsten Cumbrowski), "TheDraw Fonts File (.TDF)
> Specifications", 2014-04-23,
> https://www.roysac.com/blog/2014/04/thedraw-fonts-file-tdf-specifications/
>
> Cross-checked against the JETSAMIC org spec (`specs/art/tdf.md`) and the
> de-facto reader/renderer in Mike Krüger's icy_tools / `retrofont` crate,
> whose outline-style table is taken from TheDraw itself.

TheDraw was the dominant MS-DOS ANSI/ASCII editor of the early 1990s. A
`.TDF` file is a **collection** of fonts. No official specification exists;
everything below was reverse-engineered. Where Roy/SAC's write-up contradicts
itself or de-facto behaviour, this document says so explicitly (see
[Errata](#errata-against-the-roysac-write-up)).

All multi-byte values are little-endian.

## File layout

```
offset 0      file header                20 bytes
offset 20     font 1 header              213 bytes
offset 233    font 1 character data      BlockSize(1) bytes
233+BS(1)     font 2 header              213 bytes
...           font 2 character data      BlockSize(2) bytes
...           (optional) 0x00 font-list terminator, SAUCE record, ...
```

A file holding one font with no glyphs is **233 bytes**.

### File header (20 bytes)

| Offset | Size | Value | Notes |
|---|---|---|---|
| 0 | 1 | `0x13` | Pascal-style length byte: 19 = the 18 signature characters + the EOF byte. |
| 1 | 18 | `"TheDraw FONTS file"` | ASCII. |
| 19 | 1 | `0x1A` | DOS EOF, so `TYPE FONT.TDF` stops here. |

### Font header (213 bytes, repeated per font)

| Rel. offset | Abs. (font 1) | Size | Field | Notes |
|---|---|---|---|---|
| 0 | 20 | 4 | Sentinel | `55 AA 00 FF` (the LE dword `0xFF00AA55`). |
| 4 | 24 | 1 | NameLen | `1..12`. Readers clamp larger values to 12. |
| 5 | 25 | 12 | Name | Only the first NameLen bytes are meaningful; the rest is NUL or garbage. |
| 17 | 37 | 4 | Reserved | Observed as zero. |
| 21 | 41 | 1 | FontType | `0x00` outline, `0x01` block, `0x02` color. |
| 22 | 42 | 1 | Spacing | Letter spacing stored offset by one: `0x01..0x29` = 0..40 cells. |
| 23 | 43 | 2 | BlockSize | Size in bytes of this font's character data (see below). |
| 25 | 45 | 188 | Offsets | 94 words, one per glyph for ASCII 33 `!` … 126 `~`. Each is an offset from the start of this font's character data; `0xFFFF` = glyph undefined. |

Space (32) and DEL (127) are never stored.

### Multiple fonts and the font-list terminator

Fonts are stored back to back: font *n+1*'s header starts exactly
`BlockSize(n)` bytes after font *n*'s character data starts.

```
font_1_header = 20
font_1_data   = 233
font_n_header = font_(n-1)_data + BlockSize(n-1)
font_n_data   = font_n_header + 213
```

Every font except the last ends its character data with one extra `0x00`,
and that byte **is counted in its BlockSize**. The last font is not
terminated this way. A `0x00` where a font header would begin therefore ends
the font list; some tools (e.g. retrofont when writing bundles) append one
after the last font. Distributed `.TDF` files frequently carry a SAUCE
record after the last font, introduced by `0x1A`.

The TDFONTS.EXE editor limits a collection to **34 fonts**; the format
itself does not.

## Character data

Each glyph starts with a two-byte header:

| Offset | Size | Field | Range |
|---|---|---|---|
| 0 | 1 | MaxWidth | `1..30` |
| 1 | 1 | MaxHeight | `1..12`, **excluding** descender lines (see `&`). Use it to advance the cursor, never to bound the read. |

The header is followed by a stream of cells. At every **cell boundary**
three byte values are control codes in *all* font types and occupy a
single byte:

| Byte | Meaning |
|---|---|
| `0x00` | End of glyph. TDFONTS.EXE writes it directly after the last cell (no trailing `0x0D`); `0x0D 0x00` is also seen and must be accepted. |
| `0x0D` | End of line. |
| `0x26` `&` | Marker. When it is the last cell of a line, the line is a *descender* (drawn, but not counted in MaxHeight). **In color fonts it has no attribute byte.** |

Any other byte starts a cell:

| Font type | Cell encoding |
|---|---|
| Block (`0x01`) | 1 byte: CP437 character. |
| Outline (`0x00`) | 1 byte: placeholder letter (see below) or literal character. |
| Color (`0x02`) | 2 bytes: CP437 character, then a PC text-mode attribute byte. |

The color attribute byte is: bits 0–3 foreground (0–15), bits 4–6
background (0–7), bit 7 blink (or bright background in iCE-color mode).
`0x00` is a legal attribute (black on black); it never sits at a cell
boundary, so it cannot be confused with the terminator.

In block and color fonts `0xFF` is the *hard blank*: an opaque blank cell.

If a line ends before MaxWidth, the remaining positions are transparent.

Glyphs may share data: TDFONTS.EXE's *Copy character* points several
offset-table entries at the same offset.

## Outline fonts

Outline glyphs store placeholder letters that are substituted at display
time through one of **19 outline styles** the user selects in TheDraw.
Placeholders `A`–`Q` index the style table; `O`, `P` and `Q` are blanks
in every style.

| Letter | Role (Roy/SAC) | Style 9 (Roy/SAC's table) |
|---|---|---|
| A | Horizontal beam, top (double in style 9) | `0xCD` ═ |
| B | Horizontal beam (single in style 9) | `0xC4` ─ |
| C | Vertical (single in style 9) | `0xB3` │ |
| D | Vertical, right side (double in style 9) | `0xBA` ║ |
| E | Upper-left outer corner (outside) / Up-to-right outer corner (inside) | `0xD5` ╒ |
| F | Upper-right outer corner (outside) / Right-to-down outer corner (inside) | `0xBB` ╗ |
| G | Up-to-right inner corner (outside) / Upper-left inner corner (inside) | `0xD6` ╓ |
| H | Right-to-down inner corner (outside) / Upper-right inner corner (inside) | `0xBF` ┐ |
| I | Lower-left inner corner (inside) | `0xC8` ╚ |
| J | Lower-right inner corner (inside) | `0xBE` ╛ |
| K | Lower-left outer corner (outside) | `0xC0` └ |
| L | Lower-right outer corner (outside) | `0xBD` ╜ |
| M | Not described by Roy/SAC (right-hand tee piece) | `0xB5` ╡ |
| N | Not described by Roy/SAC (left-hand tee piece) | `0xC7` ╟ |
| O | Hard space: opaque blank inside a glyph | blank (editor shows `0xF7` ≈) |
| `@` | Filler for leading spaces | blank / transparent |
| `&` | Descender marker | — |

### Outline style table

CP437 codes for placeholders `A`…`N` (`O`, `P`, `Q` = `0x20` in every
style). Styles 0–15 enumerate single/double lines: bit 0 makes `A` double,
bit 1 `B`, bit 2 `C`, bit 3 `D`. Styles 16–18 use block elements.

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

Style 9 is byte-for-byte Roy/SAC's letter table, which independently
confirms the table.

The editor's drawing rules (double lines form the outermost/right-hand edge
of a column and the top edge of a beam) are enforced by TDFONTS.EXE, not by
the file format.

## Palette

| Index | Color | Index | Color |
|---|---|---|---|
| 0 | Black | 8 | Dark Gray |
| 1 | Blue | 9 | Bright Blue |
| 2 | Green | 10 | Bright Green |
| 3 | Cyan | 11 | Bright Cyan |
| 4 | Red | 12 | Bright Red |
| 5 | Magenta | 13 | Bright Magenta |
| 6 | Brown | 14 | Yellow |
| 7 | Light Gray | 15 | White |

## Limits

- **65,535 bytes of character data per font** (16-bit BlockSize); glyph
  offsets can be at most `0xFFFE` because `0xFFFF` means "undefined". A full
  94-glyph color font at 30×12 does not fit; sharing offsets is the
  workaround.
- Glyphs: 30 wide, 12 high plus descender lines.
- 34 fonts per file (editor limit).

## Errata against the Roy/SAC write-up

1. **Header sizes.** Roy/SAC states an empty file is 232 bytes and that each
   font adds 212 bytes. His own offset table (bytes 20…232, data at 233)
   gives a **213-byte** font header and a **233-byte** single-font file.
2. **Next-font formula.** "Font 2 header = 232 + BlockSize + 1" equals
   `233 + BlockSize`: no separator byte exists outside the block. The NUL
   that "terminates" a non-final font is the last byte *inside* its block.
3. **Glyph terminator.** "Each line ends with 0Dh; the character ends with
   00h" suggests `… 0D 00`; TDFONTS.EXE writes the NUL directly after the
   last cell. Both must be accepted.
4. **`&` in color fonts** is a single byte (no attribute) — not stated by
   Roy/SAC; confirmed by de-facto readers.
5. **Hard space `O`** is listed as `0xF7`; that is only the editor's
   visualisation. TheDraw displays it as a blank in every outline style.
6. **Attribute bit 7** (blink) is not mentioned; Roy/SAC describes the high
   nibble as background `0..7`.

## SwiftTDF compliance posture

- Reads liberally: both terminator forms, a 0x00 spacing byte (as 0), name
  lengths above 12 (clamped), a missing final glyph terminator, a separator
  NUL outside the block size, a `0x00` font-list terminator and a trailing
  SAUCE record.
- Writes what TDFONTS.EXE writes: back-to-back fonts with the in-block NUL,
  bare-NUL glyph terminators, shared offsets for byte-identical glyphs.
- Treats every offset and size as untrusted and throws `TDFError` instead
  of trapping.
