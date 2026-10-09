class_name Genome
extends RefCounted
## Gene layout and body-type classification for Theroids.

enum { ZIP, HULK, SLUG, BEAST, TANK }

## Gene indices (the nine values the lab's View panel reports).
enum G { FIGHT, MATE, EAT, SPEED, STRENGTH, STAMINA, VISION, MOMENTUM, COUNT }

const TYPE_NAMES := ["Zip", "Hulk", "Slug", "Beast", "Tank"]
const GENE_NAMES := ["FIGHT", "MATE", "EAT", "SPEED", "STRENGTH", "STAMINA", "VISION", "MOMENTUM"]
const GENE_MAX := [255, 255, 255, 255, 255, 255, 31, 7]

## Virus bits.
const VIRUS_X := 1  # sexually transmitted, reduces stamina
const VIRUS_Y := 2  # reduces vision
const VIRUS_Z := 4  # sterility in offspring

## SNI: each bar is 16 ml; a creature may use at most 256 ml (16 bars).
const SNI_ML_PER_BAR := 16
const SNI_MAX_ML := 256


## Converts SNI bar counts (7 values: fight..vision) to gene values.
static func from_sni(bars: Array, momentum: int) -> PackedInt32Array:
	var g := PackedInt32Array()
	g.resize(G.COUNT)
	for i in 6:
		g[i] = mini(255, bars[i] * SNI_ML_PER_BAR)
	g[G.VISION] = mini(31, bars[6] * 2)
	g[G.MOMENTUM] = clampi(momentum, 0, 7)
	return g


## Body type from genes (manual p.31): Zips' speed >= strength + stamina,
## Hulks' strength outweighs speed + stamina, otherwise a Slug. A creature
## whose drives and physique are all very high is born a Beast (p.59).
static func classify(g: PackedInt32Array) -> int:
	if g[G.FIGHT] >= 48 and g[G.MATE] > 80 and g[G.EAT] > 80 \
			and g[G.SPEED] > 200 and g[G.STRENGTH] > 200 and g[G.STAMINA] > 200:
		return BEAST
	if g[G.SPEED] >= g[G.STRENGTH] + g[G.STAMINA]:
		return ZIP
	if g[G.STRENGTH] >= g[G.SPEED] + g[G.STAMINA]:
		return HULK
	return SLUG
