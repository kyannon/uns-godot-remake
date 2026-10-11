# Design notes and roadmap

## Goals

1. **Faithful**: the original's rules and look, using the player's own copy
   of the 1993 game data (nothing copyrighted lives in this repository).
2. **Playable at modern resolutions**: everything is laid out in the original
   320x200 coordinate space and scaled to the window. Integer scaling by
   default (crisp pixels), F10 for fractional (fills the screen), F11 for
   fullscreen. Text and future hi-res art render at full window resolution
   (Godot's `canvas_items` stretch mode).
3. **Room to grow**: a drop-in high-resolution art pack (`Settings.hires_pack`)
   replaces any original image with a larger redraw/upscale of the same
   picture, drawn into the same logical rectangle.
4. **Platforms**: Windows first; Linux and mobile come from the same Godot
   project (renderer is GL Compatibility for broad hardware support).

## Architecture

```
scripts/uns/      file-format readers (UnsArchive, UnsPalette)
scripts/autoload/ Settings (user prefs), Assets (texture cache, fonts, hi-res hook)
scripts/sim/      LabSim (the artificial-life engine), Genome, BodyVars
scripts/ui/       Main (screen switching), Setup (pick game folder), Lab (console), LabLayout (coordinates)
tests/            headless test suite + simulation soak test
tools/            uns_extract.py: dump every image/text to PNG/JSON for study
```

The simulation knows nothing about rendering; the UI reads its arrays. This
keeps the sim testable headless and lets the battle mode reuse it (islands are
the same engine on a 260x100 map with terrain).

## How the lab simulation maps to the manual

| Manual | Implementation |
|---|---|
| Pen, Zoom 1 = 170x90 view; 3825 creature cap | 170x90 pixel world, creatures 2x2 (170·90/4 = 3825) |
| Walls on a grid of anchor points | 10x10 grid of 17x9 cells; walls on grid lines; Shift = vertical; right-click crushes |
| Food cells, flow 0-3, refill every 240/120/60 s | `food_cells` + per-pixel food. Flow sets density (0 none, 1 sparse, 2 half, 3 solid) and refill interval |
| SNI: 16 ml per bar, 256 ml limit | Every attribute starts at 1 free bar; 16 extra clicks max. Matches the manual's tutorial Slug and "standard" Theroids exactly |
| Body type: speed vs strength+stamina | `Genome.classify` |
| Beast: Fight ≥48, Mate & Eat >80, Spd/Str/Sta >200 | `Genome.classify` |
| Vision 0-31 = pixels seen ahead, ±2 sideways; also odds of going straight | `LabSim._look`, `_wander` |
| Engine cycle factored by Speed | actions per game-second = (16 + speed)/64 |
| Modes: Wander, Eat, Search, Seek, Fight, Mate, Escape, Dying, Just Born | `LabSim.Mode` |
| Dominant Encounter Trait (Need/Speed) decides the encounter | `_encounter` |
| Fight Same / Mate Others / Fight Until / Satisfaction / Damage Given & Taken / Corpse Size | `BodyVars` |
| Nutrition: subtracted from Eat, added to Stamina | `_try_graze`. Hunger rises as stamina is burned (one nutrition-worth of energy = full Eat need); a creature with Eat maxed out is starving and burns extra stamina. Newborns' stamina is paid by the parents, so a foodless pen dies out |
| Mutation chance & amount per dial level; mutable attributes | `_give_birth` |
| Viruses X (stamina, sexually transmitted), Y (vision), Z (sterility) | phenotype modifiers; inherited from either parent |
| NPR OFF/25%/FULL/MAX | Measured from the original in DOSBox: the clock always runs, ~5 game s per real s (12 real s per game minute) at OFF/25%, ~35 at MAX; FULL not yet measured. NPR scales creature activity 0 / 0.25 / 1 / 1. Knob beside the vial; red fluid rises ~20 px/s |

Numbers the manual doesn't give are tagged `TUNE` in `LabSim.gd`. The current
values give a stable population of ~1000 in the three demo pens with food flow
3; with mutation on, Slugs out-compete Zips and viruses spread, which is when
the Database cull becomes necessary.

## Roadmap

**Milestone 1: lab prototype (this commit)**
- [x] Decode containers, RLE/raw images, palettes, fonts, text
- [x] Lab console from original art, all Habitat controls, NPR, zoom 1/2/3, clock
- [x] Artificial-life sim: needs, vision, mating, fighting, food, mutation, viruses
- [x] View module (scan buttons, profile bars, partner)
- [x] Scalable window, hi-res override hook, headless tests

**Milestone 2: full lab**
- [ ] Census module (Genes/Needs tallies, type toggles)
- [ ] Database module (multi-key sort, Grab, Kill, re-place; Graph view)
- [ ] Body & Lab Variables panels (art is in AL1 #23 and #71)
- [ ] Decode BODY.DEF / LAB.DEF fully; load `.LAB` saves (Textbook Experiments)
- [ ] Save/load our own experiments
- [ ] Zoom-2 creature sprites (map the ~220 frames per type to headings/poses)
- [ ] Desktop / title screens (AL4)

**Milestone 3: battle**
- [ ] Decode `.ILN` terrain ('M' entry) and island body variables
- [ ] Battle console (AL2), SatCam, aircraft loading, cargo, C-130 drops
- [ ] Terrain effects (cliffs, bogs, ice, sand, trees), Friend/Enemy alignment
- [ ] SatBeam, Decoys, Noisemakers, Lust/Rage/Bran food, Evac, Score graph
- [ ] Top Secret campaign: 9 islands, module unlocks, serum limits, Griggs

**Milestone 4: presentation**
- [ ] Sound effects and voices (`.DSN` decoding)
- [ ] Zoom-3 animations ('F' frames) and story movies (S01-S25 stills + audio)
- [ ] Hi-res art pack pipeline (AI upscale and/or redraws)
- [ ] Mobile input (tap = left click, long-press = right click, pinch zoom)

## Open questions

- Exact meaning of each BODY.DEF byte, and LAB.DEF bytes 17-18.
- Palette load index for chunk flags 5, 7 and 8 (SNI animation looks wrong with
  every candidate; its palette probably comes from the body-type close-up).
- Original creature speed in pixels per second at each NPR setting. Comparing
  against DOSBox footage would let us tune `NPR_RATE` and `NEED_RISE`.
