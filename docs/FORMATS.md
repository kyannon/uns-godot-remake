# Unnatural Selection file formats

Reverse-engineered from the 1993 DOS release (files dated 1996-12-24, the
re-release build). All integers are little-endian. Status: **✅ decoded**,
**🟡 partly understood**, **❌ not yet decoded**.

## Folder layout

| Path | Contents |
|---|---|
| `UNS.EXE`, `UNS_LAB.EXE`, `UNS_BAT.EXE`, `UNS_PLOT.EXE` | Launcher, lab, battle and story-movie programs |
| `DATA/*.BIN` | Resource containers (graphics, text) |
| `DATA/*.DSN` | Sound / voice containers |
| `DATA/*.PAL` | 256-colour palettes |
| `DATA/*.FNT` | Bitmap fonts |
| `DATA/BODY.DEF`, `DATA/LAB.DEF` | Default Body and Lab Variables |
| `ISLANDS/*.ILN` | Battle islands (same container format as `.BIN`) |
| `SAVE/*.LAB` | Textbook experiments and saved labs |
| `SAVE/*.BVA`, `SAVE/*.LVA` | Per-island Body / Lab Variables (369 / 32 bytes) |
| `A_SNDS/*.DSN` | Movie dialogue audio |

## Resource containers (`.BIN`, `.ILN`) ✅

```
header: N entries x 8 bytes, N = (offset field of entry 0) / 8
  u16 size        bytes of entry data (NOT counting a palette chunk)
  u16 group       animation/sequence group number (0 for most files)
  u16 offset_lo   entry start (palette chunk first, if any) modulo 65536
  u8  type        'R','N','T','F','A','B','M' (see below)
  u8  pal_flag    0 = none; otherwise a palette chunk precedes the data
```

Entries are stored back to back after the header. Empty slots have size 0.
Because `offset_lo` is only 16 bits, readers walk the entries sequentially and
re-sync to the nearest position congruent to `offset_lo`.

Palette chunk sizes by `pal_flag`: 1 → 768 bytes (colours 0-255),
3 → 576 bytes (192 colours, loaded at index **64**), 5 → 192, 7 → 285,
8 → 18 (🟡 load index for 5/7/8 not confirmed). Colour components are 6-bit
VGA values (0-63).

The lab UI uses palette indices 0-63 only (from `5X.PAL`); full-screen
pictures, island maps and Zoom-3 claymation close-ups swap in their own colours
at 64-255.

### Type 'R' – RLE image ✅
```
u16 width, u16 height, u8 key (transparent colour; 0xFF = opaque)
RLE stream: 0x89 n v  -> (n + 1) copies of v
            any other -> one literal pixel
u8 checksum (trailing)
```

### Type 'N' – raw image ✅
`u16 width, u16 height, width*height pixel bytes, u8 checksum`.
Creature sprites use index 0x54 (dark grey) or 0 as background.

### Type 'T' – text ✅
Bytes XOR `0x8A`; terminated by a raw `0x00`. After XOR, values below 0x20 are
punctuation shifted down by 0x20 (`0x00` space, `0x0C` comma, `0x0E` period,
`0x07` apostrophe, `0x1F` question mark …). `AL5.BIN` holds the intro-movie
subtitles.

### Types 'F' / 'A' – animation ❌
Zoom-3 creature animations (`CH`, `CM`, `DIE`, `ET`, `F1`, `FBM`, `KA`, `MD`,
`MT`, `RW`, `SR`.BIN). Each sequence begins with a 512-byte 'A' table and a
palette-flagged first frame; the following 'F' entries start with
`aa 00 5a 00` (170x90) and appear to be delta frames. Next step: decode the
delta scheme by diffing consecutive frames.

### Types 'B', 'M' (islands) 🟡
Each `.ILN` has: two 260x100 'R' images (terrain map + overlay), a 'T'
briefing text, a 'B' (369 bytes = body variables), an 'M' (probably the
terrain/food/creature map), and a palette-flagged 260x100 'R' image.
260x100 / 4 = 6500, the manual's island population cap.

## Known contents

| File | Contents |
|---|---|
| `AL1.BIN` | Lab console (#2, 320x200 + palette), Body/Lab Variables panels (#23, #71), View panel (#39), dialogs, menus, cursors (#0-1), type icons (#15-17), food-tube levels (#126-129) |
| `AL2.BIN` | Battle console (#0), aircraft, cargo panels, SatBeam panel |
| `AL3.BIN` | Lab button on/off sprites: modules (#0-7), FIGHT/MATE (#10-13), SNI count buttons (#38-55), INJECT (#56-57), WALLS/FOOD (#58-61), mutation dial (#62-65), food flow (#66-73), zoom panel (#79) |
| `AL4.BIN` | Title screen, Maxis logo, desktop (Top Secret / Independent Research), dialogs |
| `AL5.BIN` | Movie subtitle text |
| `BACK.BIN` | Zoom-2 floor backgrounds (#0-11, 170x90) and Zoom-3 close-up portraits (palette-flagged entries, e.g. #12-16) |
| `ZIPS/HULKS/SLUGS/BEASTS/TANKS.BIN` | Zoom-2 creature sprites (~10x6, many headings/poses) |
| `SNI.BIN` | 85x45 injection animation (🟡 palette source unknown) |
| `S01…S25.BIN` + `.DSN` | Story-movie stills and their audio |
| `ISLTILES.BIN` | 🟡 island tile table, different format |

## Fonts (`.FNT`) ✅
`u8 glyph_width, u8 glyph_height`, then 90 glyphs for ASCII 32-121, one byte
per row, MSB = leftmost pixel.

## Default variables 🟡

`LAB.DEF` (32 bytes), best current reading:

| Offset | Bytes | Meaning |
|---|---|---|
| 0 | 4 | % chance to mutate for dial 0-3: `0 10 25 60` |
| 4 | 4 | Amount of mutation % for dial 0-3: `0 5 15 45` |
| 8 | 9 | Mutable attributes (1 = yes) |
| 17 | 2 | Dominant encounter trait and ? |
| 19 | 1 | Nutritional value (80) |
| 20 | 3 | Virus occurrence % X/Y/Z (10 10 10) |
| 23 | 3 | Virus results % (80 100 100) |
| 26 | 6 | Resupply intervals u16 for flow 1-3 (240 120 60) |

`BODY.DEF` (369 bytes) has per-body-type entries for Friendly and Enemy
creatures; not yet mapped. The `.LAB` saves embed a copy at offset 0x5B
followed by a lab-variables block.

## Lab saves (`.LAB`) 🟡
Offset 0x14: experiment name (space padded). 0x5B: body variables (369 bytes),
then lab variables (32). Later: wall/food grids, creature records, and a
170x90 grid of u16 cells (`0x8001` = empty floor, `0x8008` food, …). Decoding
these would let the remake load the Textbook Experiments (31 files in `SAVE/`) directly.

## Sound (`.DSN`) ❌
Starts with a table of (offset, length) pairs; the payload looks like 4-bit
ADPCM (credits list an in-house "audio compression" driver). Not yet decoded.
