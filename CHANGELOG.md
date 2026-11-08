# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - Unreleased (proposed initial release)

### Added
- `TDFParser`, `TDFWriter` and `TDFRenderer` for TheDraw `.TDF` font
  collections (outline, block and color fonts).
- `TDFOutlineStyle` with TheDraw's 19 outline styles; style 9 (Roy/SAC's
  table) is the default.
- `TDFAttribute.blink` (attribute bit 7).
- Typed errors for out-of-range glyph offsets, oversized glyphs and
  unencodable writer input.
- Format reference `Reference/TDF-Format.md` (byte layouts, outline
  placeholder roles and style table, algorithms, errata).
- DocC catalog, Swift Package Index configuration and CI workflow.
- Support for tvOS 17, watchOS 10 and visionOS 1 alongside iOS 17 and
  macOS 14.

### Fixed
- Multi-font files are read and written in TheDraw's layout (fonts back to
  back, the non-final font's NUL counted in its block size); a `0x00`
  font-list terminator and a trailing SAUCE record are recognised.
- `&` in color fonts is a one-byte marker; the parser no longer consumes
  the following line break as an attribute byte.
- The writer no longer traps when a font's character data exceeds 64 KiB.
- `TDFFontCollection.fontHeaderSize` is 213, not 212.
- Outline hard space `O` renders as a blank instead of `0xF7`.
- Build warnings in the test target.
