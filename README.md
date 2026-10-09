# Unnatural Selection: Remake

An open engine reimplementation of **Unnatural Selection** (Maxis, 1993), the
artificial-life breeding and island-warfare game, rebuilt in Godot 4 with a
scalable interface for modern displays.

> **You need your own copy of the original game.** This project contains no
> art, sound or text from Unnatural Selection. On first run it asks for the
> folder of your original install and reads the graphics straight from those
> files, the same approach as OpenRCT2 and OpenXcom.

![Status](https://img.shields.io/badge/status-milestone%201%20prototype-orange)

## What works today

- The DigiLife AL-2000 lab console, drawn pixel-exactly from the original data
  and scaled up to any window size (integer scaling by default).
- **Habitat module:** build pens with walls, paint food, set food flow and the
  mutation dial, design Theroids with the Synthetic Neural Injector, inject
  1-9 at a time.
- **NPR** speed control, FIGHT/MATE highlighting, game clock, Zoom 1/2/3
  (Zoom 3 shows the claymation close-up of the selected Theroid's type).
- **View module:** scan for the population's highest traits and inspect any
  Theroid's needs, stamina, action, partner and viruses.
- An artificial-life simulation built from the manual's rules: needs, vision,
  momentum, mating, fighting, eating, death, mutation, viruses, body-type
  emergence (including Beasts).

Census, Database, Variables panels, saving and the whole battle side are on the
roadmap; see [docs/DESIGN.md](docs/DESIGN.md).

## Running it

1. Install **Godot 4.3 or newer** (standard build, not .NET) from
   <https://godotengine.org/download>.
2. Clone this repository and open `project.godot` in Godot (Import → select the
   folder).
3. Press **F5** (Run Project). On first run, click **Choose game folder…** and
   pick the folder that contains `UNS.EXE` and `DATA`.

For a quick look with creatures already in pens, run with the demo flag:

```
godot --path . -- --demo
```

### Controls

| Input | Action |
|---|---|
| Click console buttons | Same as the original |
| Left click in pen | Select a Theroid / place a wall / toggle food / inject one |
| Right click in pen | Inject the whole batch / place a wall that crushes Theroids |
| Shift (with WALLS) | Vertical walls |
| Click and drag | Paint walls or food |
| `1` `2` `3` | Zoom levels |
| `Space` | NPR on/off |
| `Esc` | Cancel tool, or open the disk-drive menu |
| Disk drive (right edge) | Menu: new experiment, demo pens, display options, game folder |
| `F10` | Integer / fractional scaling |
| `F11` | Fullscreen |
| `F3` | Debug: show hit areas and population stats |

## Project layout

```
scripts/uns/       readers for the original file formats
scripts/autoload/  Settings and Assets (texture cache, hi-res override hook)
scripts/sim/       the Theroid artificial-life simulation
scripts/ui/        screens: setup, lab console
tests/             headless tests and a simulation soak test
tools/             uns_extract.py: dump all original images/text to PNG/JSON
docs/FORMATS.md    everything known about the file formats
docs/DESIGN.md     how the sim maps to the manual, roadmap, open questions
```

## Tests

```
# logic tests (no game data needed)
godot --headless --path . --script res://tests/run_tests.gd

# include decoder tests against your install
UNS_GAME_DIR=/path/to/UNS godot --headless --path . --script res://tests/run_tests.gd

# 30-minute population soak test
godot --headless --path . --script res://tests/sim_soak.gd
```

## Extracting the original art for study or redraws

```
python3 tools/uns_extract.py /path/to/UNS extracted/
```

This writes every image as PNG (named `<file>_<index>.png`) plus
`manifest.json`. To try higher-resolution art, put replacement PNGs with the
same names in a folder and set `hires_pack` in `user://settings.cfg`. They are
drawn into the original's logical rectangles at full window resolution.

## Legal

Unnatural Selection is © 1993 Maxis / Electronic Arts. This project is an
unofficial, non-commercial reimplementation and is not affiliated with or
endorsed by EA or Maxis. Do not commit original game files to this repository
(the `.gitignore` blocks the usual names).
