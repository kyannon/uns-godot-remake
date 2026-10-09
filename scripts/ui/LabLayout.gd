class_name LabLayout
extends RefCounted
## Screen positions on the original 320x200 DigiLife lab console (al1.bin #2).
## Sprite positions were found by template-matching each button sprite against
## the console background, so they line up pixel-exactly with the original.
## Press F3 in the lab to see every hit area outlined.

const AL1 := "data/al1.bin"
const AL3 := "data/al3.bin"
const BACK := "data/back.bin"

const BACKGROUND := 2                      # al1: full lab console, 320x200
const PEN := Rect2(141, 7, 170, 90)        # main view screen
const OVERVIEW := Rect2(8, 6, 85, 45)      # DigiLife label / Zoom-2 overview window

# Module buttons: al3 sprite index (off; on = +1) and position
const MODULES := [
	{"name": "HABITAT", "sprite": 0, "pos": Vector2(143, 101), "rect": Rect2(143, 101, 45, 13)},
	{"name": "VIEW", "sprite": 2, "pos": Vector2(188, 101), "rect": Rect2(188, 101, 34, 13)},
	{"name": "CENSUS", "sprite": 4, "pos": Vector2(222, 101), "rect": Rect2(222, 101, 42, 13)},
	{"name": "DATABASE", "sprite": 6, "pos": Vector2(264, 101), "rect": Rect2(264, 101, 48, 13)},
]

# FIGHT / MATE highlight buttons: lit-label sprite, dark (counter) sprite
const FIGHT_BTN := {"lit": 12, "dark": 13, "pos": Vector2(5, 85), "rect": Rect2(5, 85, 36, 15)}
const MATE_BTN := {"lit": 10, "dark": 11, "pos": Vector2(5, 99), "rect": Rect2(5, 99, 36, 15)}

const COMM := Rect2(7, 62, 32, 13)
const DISK_DRIVE := Rect2(286, 118, 32, 80)

# NPR "fuel tank": click the labels. Order: OFF, 25%, FULL, MAX
const NPR_LABELS := [Rect2(46, 100, 22, 8), Rect2(46, 92, 22, 8), Rect2(46, 76, 22, 8), Rect2(46, 66, 22, 8)]
const NPR_LEVEL_Y := [105, 96, 80, 70]
const NPR_TUBE := Rect2(70, 63, 8, 46)
const NPR_SCALE_X := 84

# Zoom buttons (al3 #79 panel at 99,65)
const ZOOM_PANEL := {"sprite": 79, "pos": Vector2(99, 65)}
const ZOOM_BUTTONS := [Rect2(99, 65, 34, 15), Rect2(99, 80, 34, 15), Rect2(99, 95, 34, 15)]
const ZOOM_ICONS := [Rect2(102, 67, 12, 12), Rect2(102, 82, 12, 12), Rect2(102, 97, 12, 12)]

# Clock
const CLOCK_CENTER := Vector2(113, 23)
const CLOCK_RADIUS := 16.0
const CLOCK_TIME := Vector2(104, 19)
const CLOCK_DATE := Vector2(106, 43)

# --- Habitat module: Synthetic Neural Injector (SNI) ---
const SNI_ROWS_Y := [127, 135, 143, 153, 161, 169, 177]   # bar rows, 5px tall
const SNI_ARROW_Y := [125, 133, 141, 151, 159, 167, 175]  # arrow buttons, 8px tall
const SNI_LEFT_X := 70
const SNI_RIGHT_X := 80
const SNI_NUM_X := 55
const SNI_BAR_X := 97
const SNI_ICON_POS := Vector2(138, 127)
const SNI_ICON_NUM := Vector2(144, 138)
const SNI_GRAPH := Rect2(135, 150, 32, 33)
const SNI_GRAPH_NUM := Vector2(139, 158)
const COUNT_BUTTONS := [  # value, off sprite (on = +1), pos
	{"n": 1, "sprite": 38, "pos": Vector2(23, 186)},
	{"n": 3, "sprite": 42, "pos": Vector2(41, 186)},
	{"n": 5, "sprite": 46, "pos": Vector2(59, 186)},
	{"n": 7, "sprite": 50, "pos": Vector2(77, 186)},
	{"n": 9, "sprite": 54, "pos": Vector2(95, 186)},
]
const INJECT_BTN := {"sprite": 56, "pos": Vector2(115, 186), "rect": Rect2(115, 186, 56, 12)}
const WALLS_BTN := {"sprite": 58, "pos": Vector2(183, 127), "rect": Rect2(183, 127, 37, 11)}
const FOOD_BTN := {"sprite": 60, "pos": Vector2(183, 138), "rect": Rect2(183, 138, 37, 12)}
const MUTATION_DIAL := {"sprite": 62, "pos": Vector2(190, 173)}  # 62..65 = settings 0..3
const MUTATION_LABELS := [Rect2(179, 160, 8, 9), Rect2(189, 160, 8, 9), Rect2(201, 160, 8, 9), Rect2(213, 160, 8, 9)]
const MUTATION_KNOB := Rect2(190, 173, 28, 22)
const FOOD_FLOW := [  # level, off sprite (on = +1), pos
	{"n": 0, "sprite": 66, "pos": Vector2(231, 169)},
	{"n": 1, "sprite": 68, "pos": Vector2(231, 158)},
	{"n": 2, "sprite": 70, "pos": Vector2(231, 147)},
	{"n": 3, "sprite": 72, "pos": Vector2(231, 136)},
]
const FOOD_TUBE := {"sprite": 126, "pos": Vector2(254, 145)}  # al1 126..129 = levels 0..3

# Creature type icons for the SNI (al1) and Zoom-3 portraits (back.bin)
const TYPE_ICON := [15, 16, 17, 84, 86]
const TYPE_PORTRAIT := [12, 13, 14, 15, 16]

# --- View module (al1 #39 panel) ---
const VIEW_PANEL := {"sprite": 39, "pos": Vector2(12, 116)}
const VIEW_SCAN_ORIGIN := Vector2(20, 121)   # 3x3 grid of scan buttons
const VIEW_SCAN_CELL := Vector2(41, 24)
const VIEW_SCAN_LABELS := ["FIGHT", "MATE", "EAT", "SPD", "STR", "STA", "VIS", "MOM", "VRS"]
const VIEW_BARS_X := 191                      # profile bars, 16 x 2px
const VIEW_ROWS_Y := [124, 134, 144, 154, 164, 174, 184]
const VIEW_ACTION := Vector2(240, 123)
const VIEW_ICON := Vector2(243, 134)
const VIEW_VIRUS := Vector2(261, 151)
const VIEW_PARTNER_ICON := Vector2(243, 169)
const VIEW_PARTNER_VIRUS := Vector2(261, 186)

# Lab palette indices used for drawing
const COL_ORANGE := 28
const COL_BAR_OFF := 18
const COL_TEXT := 6
const COL_WHITE := 1
const COL_YELLOW := 54
const COL_GREEN := 37
const COL_FOOD := 62
const COL_WALL := 13
const COL_TRENCH := 0
const TYPE_COLOR := [27, 37, 43, 34, 35]   # Zip, Hulk, Slug, Beast, Tank
