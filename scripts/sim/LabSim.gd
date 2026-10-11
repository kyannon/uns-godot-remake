class_name LabSim
extends RefCounted
## Theroid artificial-life simulation for the DigiLife lab pen.
##
## The pen is a 170x90 pixel world (the original's Zoom-1 view, one creature
## per 2x2 pixels: 170*90/4 = 3825 = the manual's lab population cap). It is
## divided into a 10x10 grid of 17x9 cells. Walls run along the grid lines
## ("trenches"); food grows inside the cells.
##
## This is a reimplementation from the manual's description ("The Ways of a
## Theroid", "Variables"), not a disassembly of the original code. Numbers that
## the manual doesn't give are marked TUNE and live in constants below.

const W := 170
const H := 90
const CELL_W := 17
const CELL_H := 9
const GRID_X := 10
const GRID_Y := 10
const CAPACITY := 3825

enum Mode { WANDER, EAT, SEARCH, SEEK, FIGHT, MATE, ESCAPE, DYING, JUST_BORN }
const MODE_NAMES := ["WANDER", "EAT", "SEARCH", "SEEK", "FIGHT", "MATE", "ESCAPE", "DYING", "BORN"]
enum Need { FIGHT, MATE, EAT }

# NPR settings OFF, 25%, FULL, MAX. Measured from the original running in
# DOSBox: the lab clock always runs (~5 game s per real s, i.e. one game
# minute per ~12 s) and the NPR scales how active the Theroids are; at MAX
# the frequency is off entirely and the clock runs ~35 game s per real s.
# FULL's clock rate was not measurable in the reference recording. TUNE
const NPR_RATE := [5.0, 5.0, 5.0, 35.0]          # game seconds per real second
const NPR_ACTIVITY := [0.0, 0.25, 1.0, 1.0]      # creature action-rate multiplier
const START_TIME := 12 * 3600                     # the lab clock starts at 12:00
const START_MONTH := 7                            # ...on 07/17
const START_DAY := 17
# Food flow resupply interval in game seconds (lab.def: 240/120/60)
var resupply_interval := [0, 240, 120, 60]
# Mutation dial: % chance per birth, % change per mutation (lab.def guesses)
var mutation_chance := [0, 10, 25, 60]
var mutation_amount := [0, 5, 15, 45]
var mutable := [true, true, true, true, true, true, true, true]
var nutrition := 80                     # food value per pixel (0..255)
var virus_occurrence := [10, 10, 10]    # % for X, Y, Z when a mutation happens
var virus_result := [50, 100, 50]       # % effect of X (stamina), Y (vision), Z (sterility). TUNE
var dominant_by_speed := false          # Dominant Encounter Trait: Need (default) or Speed

# TUNE: internal scales
const STAMINA_SCALE := 8.0      # stamina pool = stamina gene * 8
const NEED_RISE := 1.0 / 128.0  # need rises by gene/128 per action
const BASE_COST := 2.0          # stamina burned per action just by being alive
const MOVE_COST := 1.0          # extra stamina per step taken
const BODY_COST := 1.0 / 48.0   # extra per point of speed + strength (big, fast bodies burn more)
const STARVE_COST := 6.0        # extra per action while the Eat need is maxed out (starving)
const NUTRITION_REF := 80.0     # LAB.DEF default nutrition value
const MIN_BIRTH_STAMINA := 0.25 # a newborn needs at least this fraction of its max, paid by the parents
const MATE_COST := 0.2          # fraction of max stamina spent by each parent
const DAMAGE_SCALE := 4.0       # strength -> stamina damage
const MATE_ACTIONS := 3
const DYING_ACTIONS := 3
const NEED_THRESHOLD := 24.0    # below this nothing is urgent -> wander

const DX := [1, 1, 0, -1, -1, -1, 0, 1]
const DY := [0, 1, 1, 1, 0, -1, -1, -1]

# --- world state -----------------------------------------------------------
var solid := PackedByteArray()     # 1 = wall pixel / border
var food := PackedByteArray()      # 0 none, 1 food
var food_cells := PackedByteArray()  # 100 cells, 1 = player wants food here
var hwall := PackedByteArray()     # horizontal wall segments on line y=r*9, r=1..9, c=0..9
var vwall := PackedByteArray()     # vertical wall segments on line x=c*17, c=1..9, r=0..9
var occ := PackedInt32Array()      # creature slot + 1, 0 = empty

# --- creatures (structure of arrays) ---------------------------------------
var alive := PackedByteArray()
var cx := PackedInt32Array()
var cy := PackedInt32Array()
var cdir := PackedInt32Array()
var ctype := PackedInt32Array()
var genes := PackedInt32Array()    # CAPACITY * Genome.G.COUNT
var virus := PackedByteArray()
var sterile := PackedByteArray()
var needs := PackedFloat32Array()  # CAPACITY * 3
var stamina := PackedFloat32Array()
var mode := PackedInt32Array()
var partner := PackedInt32Array()
var timer := PackedInt32Array()
var acc := PackedFloat32Array()
var born_at := PackedFloat32Array()
var free_slots: Array[int] = []
var living := PackedInt32Array()      # slots of living creatures (iterate this, not CAPACITY)
var _living_pos := PackedInt32Array() # slot -> index in `living`
var population := 0

# --- settings / clock ------------------------------------------------------
var npr := 0
var food_flow := 0
var mutation_level := 0
var game_time := float(START_TIME)  # seconds since 00:00 on the start day
var _step_acc := 0.0
var _resupply_acc := 0.0
var body_vars: Array = []     # BodyVars per body type
var rng := RandomNumberGenerator.new()

# statistics
var births := 0
var deaths := 0


func _init() -> void:
	rng.randomize()
	solid.resize(W * H)
	food.resize(W * H)
	food_cells.resize(GRID_X * GRID_Y)
	hwall.resize(GRID_Y * GRID_X)
	vwall.resize(GRID_Y * GRID_X)
	occ.resize(W * H)
	for arr in [alive, virus, sterile]:
		arr.resize(CAPACITY)
	for arr in [cx, cy, cdir, ctype, mode, partner, timer]:
		arr.resize(CAPACITY)
	for arr in [stamina, acc, born_at]:
		arr.resize(CAPACITY)
	genes.resize(CAPACITY * Genome.G.COUNT)
	_living_pos.resize(CAPACITY)
	needs.resize(CAPACITY * 3)
	for i in range(CAPACITY - 1, -1, -1):
		free_slots.append(i)
	for t in 5:
		body_vars.append(BodyVars.defaults_for(t))
	_rebuild_solid()


# ===========================================================================
# Pen construction
# ===========================================================================

func _rebuild_solid() -> void:
	solid.fill(0)
	for x in W:
		solid[x] = 1
		solid[(H - 1) * W + x] = 1
	for y in H:
		solid[y * W] = 1
		solid[y * W + W - 1] = 1
	for r in range(1, GRID_Y):
		for c in GRID_X:
			if hwall[r * GRID_X + c]:
				var y := r * CELL_H
				for x in range(c * CELL_W, mini(W, c * CELL_W + CELL_W + 1)):
					solid[y * W + x] = 1
	for r in GRID_Y:
		for c in range(1, GRID_X):
			if vwall[r * GRID_X + c]:
				var x := c * CELL_W
				for y in range(r * CELL_H, mini(H, r * CELL_H + CELL_H + 1)):
					solid[y * W + x] = 1
	for i in W * H:
		if solid[i]:
			food[i] = 0


## Nearest wall slot to a pen pixel. Returns {kind:"h"/"v", r, c, dist} or {}.
func wall_slot_at(px: float, py: float, vertical: bool) -> Dictionary:
	if vertical:
		var c := int(round(px / CELL_W))
		var r := int(floor(py / CELL_H))
		if c < 1 or c > GRID_X - 1 or r < 0 or r >= GRID_Y:
			return {}
		return {"kind": "v", "r": r, "c": c, "dist": absf(px - c * CELL_W)}
	var r2 := int(round(py / CELL_H))
	var c2 := int(floor(px / CELL_W))
	if r2 < 1 or r2 > GRID_Y - 1 or c2 < 0 or c2 >= GRID_X:
		return {}
	return {"kind": "h", "r": r2, "c": c2, "dist": absf(py - r2 * CELL_H)}


func get_wall(slot: Dictionary) -> bool:
	if slot.is_empty():
		return false
	var arr := hwall if slot.kind == "h" else vwall
	return arr[slot.r * GRID_X + slot.c] == 1


## Places/removes a wall. If `crush` is false a wall can't be placed on top of
## creatures (left click); with `crush` true it kills them (right click).
func set_wall(slot: Dictionary, on: bool, crush: bool = false) -> bool:
	if slot.is_empty():
		return false
	var pixels := _wall_pixels(slot)
	if on:
		var victims := {}
		for i in pixels:
			if occ[i] != 0:
				victims[occ[i] - 1] = true
		if not victims.is_empty():
			if not crush:
				return false
			for v in victims:
				kill(v, false)
	if slot.kind == "h":
		hwall[slot.r * GRID_X + slot.c] = 1 if on else 0
	else:
		vwall[slot.r * GRID_X + slot.c] = 1 if on else 0
	_rebuild_solid()
	return true


func _wall_pixels(slot: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	if slot.kind == "h":
		var y: int = slot.r * CELL_H
		for x in range(slot.c * CELL_W, mini(W, slot.c * CELL_W + CELL_W + 1)):
			out.append(y * W + x)
	else:
		var x2: int = slot.c * CELL_W
		for y2 in range(slot.r * CELL_H, mini(H, slot.r * CELL_H + CELL_H + 1)):
			out.append(y2 * W + x2)
	return out


func cell_at(px: float, py: float) -> int:
	var c := int(px / CELL_W)
	var r := int(py / CELL_H)
	if c < 0 or c >= GRID_X or r < 0 or r >= GRID_Y:
		return -1
	return r * GRID_X + c


func set_food_cell(cell: int, on: bool) -> void:
	if cell < 0:
		return
	food_cells[cell] = 1 if on else 0
	if on:
		if food_flow > 0:
			_fill_cell(cell)
	else:
		_clear_cell(cell)


func _cell_pixels(cell: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c := cell % GRID_X
	var r := cell / GRID_X
	for y in range(r * CELL_H + 1, r * CELL_H + CELL_H):
		for x in range(c * CELL_W + 1, c * CELL_W + CELL_W):
			if x < W - 1 and y < H - 1:
				out.append(y * W + x)
	return out


## Food density by flow level: 0 none, 1 sparse, 2 half, 3 solid.
static func food_pattern(x: int, y: int, level: int) -> bool:
	match level:
		3:
			return true
		2:
			return (x + y) % 2 == 0
		1:
			return x % 2 == 0 and y % 2 == 0
	return false


func _fill_cell(cell: int) -> void:
	for i in _cell_pixels(cell):
		if not solid[i] and food_pattern(i % W, i / W, food_flow):
			food[i] = 1


## Changing the food flow re-seeds every food cell at the new density
## (0 removes all food from the pen).
func set_food_flow(level: int) -> void:
	food_flow = level
	_resupply_acc = 0.0
	for i in W * H:
		if food[i] and not food_pattern(i % W, i / W, level):
			food[i] = 0
	resupply_food()


func _clear_cell(cell: int) -> void:
	for i in _cell_pixels(cell):
		food[i] = 0


func resupply_food() -> void:
	for cell in GRID_X * GRID_Y:
		if food_cells[cell]:
			_fill_cell(cell)


# ===========================================================================
# Creatures
# ===========================================================================

func gene(i: int, g: int) -> int:
	return genes[i * Genome.G.COUNT + g]


func need(i: int, n: int) -> float:
	return needs[i * 3 + n]


## Expressed trait value: genes as modified by viruses (X lowers stamina,
## Y lowers vision). Genes themselves are passed on unmodified.
func expressed(i: int, g: int) -> int:
	var v := genes[i * Genome.G.COUNT + g]
	if g == Genome.G.STAMINA and virus[i] & Genome.VIRUS_X:
		v = maxi(8, v * (100 - virus_result[0]) / 100)
	elif g == Genome.G.VISION and virus[i] & Genome.VIRUS_Y:
		v = v * (100 - virus_result[1]) / 100
	return v


func max_stamina(i: int) -> float:
	return expressed(i, Genome.G.STAMINA) * STAMINA_SCALE


func can_place(x: int, y: int, ignore: int = -1) -> bool:
	if x < 1 or y < 1 or x > W - 3 or y > H - 3:
		return false
	for oy in 2:
		for ox in 2:
			var k := (y + oy) * W + x + ox
			if solid[k]:
				return false
			if occ[k] != 0 and occ[k] - 1 != ignore:
				return false
	return true


func _stamp(i: int, on: bool) -> void:
	var v := i + 1 if on else 0
	for oy in 2:
		for ox in 2:
			occ[(cy[i] + oy) * W + cx[i] + ox] = v


## Adds a creature; returns its slot or -1 if no room.
func spawn(x: int, y: int, g: PackedInt32Array, vir: int = 0, is_sterile: bool = false, start_stamina: float = -1.0) -> int:
	if free_slots.is_empty() or not can_place(x, y):
		return -1
	var i: int = free_slots.pop_back()
	alive[i] = 1
	cx[i] = x
	cy[i] = y
	cdir[i] = rng.randi_range(0, 7)
	for k in Genome.G.COUNT:
		genes[i * Genome.G.COUNT + k] = g[k]
	ctype[i] = Genome.classify(g)
	virus[i] = vir
	sterile[i] = 1 if is_sterile else 0
	needs[i * 3] = 0.0
	needs[i * 3 + 1] = 0.0
	needs[i * 3 + 2] = 0.0
	stamina[i] = max_stamina(i) if start_stamina < 0.0 else minf(start_stamina, max_stamina(i))
	mode[i] = Mode.JUST_BORN
	partner[i] = -1
	timer[i] = 2
	acc[i] = rng.randf()
	born_at[i] = game_time
	_stamp(i, true)
	_living_pos[i] = living.size()
	living.append(i)
	population += 1
	return i


func kill(i: int, leave_corpse: bool = true) -> void:
	if not alive[i]:
		return
	_stamp(i, false)
	if leave_corpse:
		var n: int = body_vars[ctype[i]].corpse_size
		var spots := [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 1)]
		for k in mini(n, 4):
			var p: Vector2i = spots[k]
			var idx := (cy[i] + p.y) * W + cx[i] + p.x
			if not solid[idx]:
				food[idx] = 1
	var p2 := partner[i]
	if p2 >= 0 and alive[p2] and partner[p2] == i:
		partner[p2] = -1
		if mode[p2] == Mode.FIGHT or mode[p2] == Mode.MATE:
			mode[p2] = Mode.WANDER
	alive[i] = 0
	var pos := _living_pos[i]
	var last := living[living.size() - 1]
	living[pos] = last
	_living_pos[last] = pos
	living.resize(living.size() - 1)
	free_slots.append(i)
	population -= 1
	deaths += 1


func creature_at(px: int, py: int, radius: int = 2) -> int:
	var best := -1
	var bd := 1e9
	for y in range(maxi(0, py - radius), mini(H, py + radius + 1)):
		for x in range(maxi(0, px - radius), mini(W, px + radius + 1)):
			var o := occ[y * W + x]
			if o != 0:
				var d := Vector2(x - px, y - py).length_squared()
				if d < bd:
					bd = d
					best = o - 1
	return best


## Most pressing need. Ties go to Eat, then Mate, then Fight.
func dominant_need(i: int) -> int:
	var f := needs[i * 3]
	var m := needs[i * 3 + 1]
	var e := needs[i * 3 + 2]
	if e >= m and e >= f:
		return Need.EAT
	if m >= f:
		return Need.MATE
	return Need.FIGHT


func count_mode(m: int) -> int:
	var n := 0
	for i in living:
		if mode[i] == m:
			n += 1
	return n


func count_types() -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0, 0, 0])
	for i in living:
		out[ctype[i]] += 1
	return out


# ===========================================================================
# Time
# ===========================================================================

## Advances by `real_dt` seconds of wall-clock time at the current NPR level.
func update(real_dt: float) -> void:
	var rate: float = NPR_RATE[npr]
	_step_acc += real_dt * rate
	var budget := 64  # never spend more than 64 game-seconds per frame
	while _step_acc >= 1.0 and budget > 0:
		_step_acc -= 1.0
		budget -= 1
		step()
	if budget == 0:
		_step_acc = 0.0


## One game second.
func step() -> void:
	game_time += 1.0
	if food_flow > 0:
		_resupply_acc += 1.0
		if _resupply_acc >= resupply_interval[food_flow]:
			_resupply_acc = 0.0
			resupply_food()
	var activity: float = NPR_ACTIVITY[npr]
	if activity <= 0.0:
		return  # NPR off: Theroids are held in suspension
	var order := living.duplicate()  # births/deaths during the step change `living`
	var n := order.size()
	if n == 0:
		return
	var start := rng.randi_range(0, n - 1)
	for k in n:
		var i := order[(start + k) % n]
		if not alive[i]:
			continue
		# The Artificial Life engine's cycle is factored by Speed.
		acc[i] += activity * (16.0 + gene(i, Genome.G.SPEED)) / 64.0
		while acc[i] >= 1.0 and alive[i]:
			acc[i] -= 1.0
			_act(i)


func _act(i: int) -> void:
	var m := mode[i]
	if m == Mode.DYING:
		timer[i] -= 1
		if timer[i] <= 0:
			kill(i, true)
		return
	if m == Mode.JUST_BORN:
		timer[i] -= 1
		if timer[i] <= 0:
			mode[i] = Mode.WANDER
		return

	# Fight and Mate urges rise according to genetics; Eat rises as stamina
	# is burned (see _spend).
	var base := i * 3
	for n in [Need.FIGHT, Need.MATE]:
		var g := float(gene(i, n))
		needs[base + n] = minf(g, needs[base + n] + g * NEED_RISE)

	if m == Mode.MATE:
		_continue_mating(i)
		return
	if m == Mode.FIGHT:
		_continue_fight(i)
		return

	# opportunistic grazing: a hungry creature standing on food takes a bite
	if needs[base + Need.EAT] >= NEED_THRESHOLD * 0.5 and _try_graze(i):
		return
	var dn := dominant_need(i)
	var urgency := needs[base + dn]
	if urgency < NEED_THRESHOLD:
		_wander(i)
		return
	if dn == Need.EAT:
		if _try_graze(i):
			return
		var f := _look(i, true)
		if f.found == 1:
			mode[i] = Mode.SEARCH
			_move(i, cdir[i], true)
			return
		_wander(i, Mode.SEARCH)
	else:
		var seen := _look(i, false)
		if seen.found == 2:
			mode[i] = Mode.SEEK
			if seen.dist <= 1:
				_encounter(i, seen.who)
			else:
				_move(i, cdir[i], true)
			return
		_wander(i, Mode.SEARCH)


## Burns stamina. Spending about one food pixel's worth of energy
## (NUTRITION_REF) takes the Eat need from empty to its genetic maximum.
func _spend(i: int, amount: float) -> bool:
	stamina[i] -= amount
	var eg := float(gene(i, Genome.G.EAT))
	needs[i * 3 + Need.EAT] = minf(eg, needs[i * 3 + Need.EAT] + amount * eg / NUTRITION_REF)
	if stamina[i] <= 0.0:
		mode[i] = Mode.DYING
		timer[i] = DYING_ACTIONS
		var p := partner[i]
		if p >= 0 and alive[p] and partner[p] == i:
			partner[p] = -1
			if mode[p] == Mode.FIGHT or mode[p] == Mode.MATE:
				mode[p] = Mode.WANDER
		partner[i] = -1
		return false
	return true


## Stamina burned by one action. Bigger, faster bodies burn more, and a
## creature whose Eat need is maxed out is starving and burns much more.
func _cost(i: int, moving: bool) -> float:
	var c := BASE_COST + (gene(i, Genome.G.SPEED) + gene(i, Genome.G.STRENGTH)) * BODY_COST
	if moving:
		c += MOVE_COST
	var eat_max := gene(i, Genome.G.EAT)
	if eat_max > 0 and needs[i * 3 + Need.EAT] >= eat_max - 0.5:
		c += STARVE_COST
	return c


func _wander(i: int, as_mode: int = Mode.WANDER) -> void:
	mode[i] = as_mode
	# Vision is also the odds (0..31) of continuing straight; momentum adds to it.
	var keep := expressed(i, Genome.G.VISION) + gene(i, Genome.G.MOMENTUM) * 3
	if rng.randi_range(0, 40) > keep:
		cdir[i] = (cdir[i] + (1 if rng.randf() < 0.5 else 7)) % 8
	_move(i, cdir[i], false)


## Scans `vision` pixels ahead (and 2 to each side). Returns
## {found: 0 nothing / 1 food / 2 creature / 3 wall, dist, who}.
func _look(i: int, want_food: bool) -> Dictionary:
	var vis := expressed(i, Genome.G.VISION)
	var d := cdir[i]
	var fx := float(DX[d])
	var fy := float(DY[d])
	var sx := -fy
	var sy := fx
	var ox := cx[i] + 0.5
	var oy := cy[i] + 0.5
	for dist in range(1, vis + 2):
		for lat in [0, -1, 1, -2, 2]:
			var x := int(round(ox + fx * (dist + 1) + sx * lat))
			var y := int(round(oy + fy * (dist + 1) + sy * lat))
			if x < 0 or y < 0 or x >= W or y >= H:
				return {"found": 3, "dist": dist, "who": -1}
			var k := y * W + x
			if solid[k] and lat == 0:
				return {"found": 3, "dist": dist, "who": -1}
			var o := occ[k]
			if o != 0 and o - 1 != i:
				if not want_food:
					if lat != 0:
						cdir[i] = _dir_towards(cx[i], cy[i], x, y)
					return {"found": 2, "dist": dist, "who": o - 1}
			elif want_food and food[k]:
				if lat != 0:
					cdir[i] = _dir_towards(cx[i], cy[i], x, y)
				return {"found": 1, "dist": dist, "who": -1}
	return {"found": 0, "dist": 0, "who": -1}


func _dir_towards(x0: int, y0: int, x1: int, y1: int) -> int:
	var a := atan2(float(y1 - y0), float(x1 - x0))
	return posmod(int(round(a / (PI / 4.0))), 8)


func _try_graze(i: int) -> bool:
	for oy in range(-1, 3):
		for ox in range(-1, 3):
			var x := cx[i] + ox
			var y := cy[i] + oy
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			var k := y * W + x
			if food[k]:
				food[k] = 0
				mode[i] = Mode.EAT
				needs[i * 3 + Need.EAT] = maxf(0.0, needs[i * 3 + Need.EAT] - nutrition * gene(i, Genome.G.EAT) / NUTRITION_REF)
				stamina[i] = minf(max_stamina(i), stamina[i] + nutrition)
				_spend(i, _cost(i, false))
				return true
	return false


func _move(i: int, d: int, seeking: bool) -> void:
	if not _spend(i, _cost(i, true)):
		return
	var nx: int = cx[i] + DX[d]
	var ny: int = cy[i] + DY[d]
	if can_place(nx, ny, i):
		_stamp(i, false)
		cx[i] = nx
		cy[i] = ny
		_stamp(i, true)
		return
	# blocked: by a creature?
	var other := _creature_in_footprint(nx, ny, i)
	if other >= 0 and seeking:
		_encounter(i, other)
		return
	# wall or uninterested: spin to a new heading
	var spin := rng.randi_range(1, 3)
	cdir[i] = (d + (spin if rng.randf() < 0.5 else 8 - spin)) % 8


func _creature_in_footprint(x: int, y: int, me: int) -> int:
	for oy in 2:
		for ox in 2:
			var xx := x + ox
			var yy := y + oy
			if xx < 0 or yy < 0 or xx >= W or yy >= H:
				continue
			var o := occ[yy * W + xx]
			if o != 0 and o - 1 != me:
				return o - 1
	return -1


func _rule_ok(rule: int, need_val: float, need_max: float) -> bool:
	match rule:
		BodyVars.Rule.ALWAYS:
			return true
		BodyVars.Rule.NEVER:
			return false
	return need_val >= need_max - 0.5


func _busy(j: int) -> bool:
	var m := mode[j]
	return m == Mode.MATE or m == Mode.FIGHT or m == Mode.DYING or m == Mode.JUST_BORN


func _encounter(a: int, b: int) -> void:
	if not alive[b] or _busy(b):
		cdir[a] = (cdir[a] + 4) % 8
		return
	# Dominant Encounter Trait decides who chooses what happens.
	var decider := a
	var other := b
	if dominant_by_speed:
		if gene(b, Genome.G.SPEED) > gene(a, Genome.G.SPEED):
			decider = b
			other = a
	else:
		var na := needs[a * 3 + dominant_need(a)]
		var nb := needs[b * 3 + dominant_need(b)]
		if nb > na:
			decider = b
			other = a
	var dn := dominant_need(decider)
	var bv: BodyVars = body_vars[ctype[decider]]
	var same := ctype[decider] == ctype[other]
	if dn == Need.MATE:
		var ok := same or _rule_ok(bv.mate_others, needs[decider * 3 + 1], gene(decider, Genome.G.MATE))
		if ok:
			_start(decider, other, Mode.MATE, MATE_ACTIONS)
			return
	elif dn == Need.FIGHT:
		var ok2 := (not same) or _rule_ok(bv.fight_same, needs[decider * 3], gene(decider, Genome.G.FIGHT))
		if ok2:
			_start(decider, other, Mode.FIGHT, 0)
			return
	# ignore one another
	cdir[a] = (cdir[a] + rng.randi_range(2, 6)) % 8


func _start(a: int, b: int, m: int, t: int) -> void:
	mode[a] = m
	mode[b] = m
	partner[a] = b
	partner[b] = a
	timer[a] = t
	timer[b] = t


func _continue_mating(i: int) -> void:
	var p := partner[i]
	if p < 0 or not alive[p] or partner[p] != i:
		mode[i] = Mode.WANDER
		partner[i] = -1
		return
	if not _spend(i, _cost(i, false)):
		return
	timer[i] -= 1
	if timer[i] > 0:
		return
	# whichever partner finishes first completes the mating for both.
	# The newborn's stamina is paid for by its parents (no free energy).
	var paid := 0.0
	for k in [i, p]:
		var share := minf(stamina[k], max_stamina(k) * MATE_COST)
		paid += share
	for k in [i, p]:
		_spend(k, minf(stamina[k], max_stamina(k) * MATE_COST))
	_give_birth(i, p, paid)
	for k in [i, p]:
		if not alive[k]:
			continue
		var sat: float = body_vars[ctype[k]].mate_satisfaction
		needs[k * 3 + Need.MATE] *= (1.0 - sat)
		if mode[k] == Mode.MATE:
			mode[k] = Mode.WANDER
		partner[k] = -1
		cdir[k] = rng.randi_range(0, 7)


func _give_birth(a: int, b: int, energy: float) -> void:
	if sterile[a] or sterile[b]:
		return
	var g := PackedInt32Array()
	g.resize(Genome.G.COUNT)
	for k in Genome.G.COUNT:
		g[k] = gene(a, k) if rng.randf() < 0.5 else gene(b, k)
	var vir := virus[a] | virus[b]
	# mutation
	var lvl := mutation_level
	if lvl > 0 and rng.randi_range(1, 100) <= mutation_chance[lvl]:
		var amount: int = mutation_amount[lvl]
		var tries := rng.randi_range(1, 3)
		for _t in tries:
			var k2 := rng.randi_range(0, Genome.G.COUNT - 1)
			if not mutable[k2]:
				continue
			var mx: int = Genome.GENE_MAX[k2]
			if amount >= 255:
				g[k2] = rng.randi_range(0, mx)
			else:
				var delta := maxi(1, int(round(mx * amount / 100.0)))
				g[k2] = clampi(g[k2] + (delta if rng.randf() < 0.5 else -delta), 0, mx)
		for v in 3:
			if rng.randi_range(1, 100) <= virus_occurrence[v]:
				vir |= (1 << v)
	var is_sterile := false
	if vir & Genome.VIRUS_Z:
		is_sterile = rng.randi_range(1, 100) <= virus_result[2]
	# X is sexually transmitted to the partner as well
	if vir & Genome.VIRUS_X:
		virus[a] |= Genome.VIRUS_X
		virus[b] |= Genome.VIRUS_X
	if energy < Genome.classify_stamina_pool(g, STAMINA_SCALE) * MIN_BIRTH_STAMINA:
		return  # parents too exhausted to produce a viable offspring
	# find room near the parents, on the same side of any wall
	for r in range(2, 6):
		for _try in 8:
			var x := cx[a] + rng.randi_range(-r, r)
			var y := cy[a] + rng.randi_range(-r, r)
			if not _clear_path(cx[a], cy[a], x, y):
				continue
			if spawn(x, y, g, vir, is_sterile, energy) >= 0:
				births += 1
				return


## True if a 2x2 footprint can slide from (x0,y0) to (x1,y1) without crossing
## a wall (other creatures are ignored).
func _clear_path(x0: int, y0: int, x1: int, y1: int) -> bool:
	var n := maxi(absi(x1 - x0), absi(y1 - y0))
	for s in range(1, n + 1):
		var x := x0 + int(round(float(x1 - x0) * s / n))
		var y := y0 + int(round(float(y1 - y0) * s / n))
		if x < 1 or y < 1 or x > W - 3 or y > H - 3:
			return false
		for oy in 2:
			for ox in 2:
				if solid[(y + oy) * W + x + ox]:
					return false
	return true


func _continue_fight(i: int) -> void:
	var p := partner[i]
	if p < 0 or not alive[p] or partner[p] != i or mode[p] == Mode.DYING:
		mode[i] = Mode.WANDER
		partner[i] = -1
		return
	if not _spend(i, _cost(i, false)):
		return
	# faster creatures land more blows
	var si := float(gene(i, Genome.G.SPEED)) + 8.0
	var sp := float(gene(p, Genome.G.SPEED)) + 8.0
	if rng.randf() < si / (si + sp) * 1.5:
		var bvi: BodyVars = body_vars[ctype[i]]
		var bvp: BodyVars = body_vars[ctype[p]]
		var dmg := gene(i, Genome.G.STRENGTH) * bvi.damage_given * bvp.damage_taken * DAMAGE_SCALE
		var bv: BodyVars = bvi
		if bv.fight_until == BodyVars.Until.NEED:
			needs[i * 3 + Need.FIGHT] *= (1.0 - bv.fight_satisfaction * 0.25)
		if not _spend(p, dmg):
			# p is dying: i wins
			needs[i * 3 + Need.FIGHT] *= (1.0 - bv.fight_satisfaction)
			mode[i] = Mode.WANDER
			partner[i] = -1
			return
	if body_vars[ctype[i]].fight_until == BodyVars.Until.NEED and dominant_need(i) != Need.FIGHT:
		mode[i] = Mode.ESCAPE
		partner[i] = -1
		if partner[p] == i:
			partner[p] = -1
			mode[p] = Mode.WANDER


# ===========================================================================
# Demo / test setup
# ===========================================================================

## Three walled pens filled with food (like the manual's tutorial), each
## stocked with `per_pen` creatures of the given SNI designs.
func build_demo(designs: Array, per_pen: int = 30) -> void:
	var pens := [Rect2i(0, 0, 3, 4), Rect2i(3, 0, 4, 4), Rect2i(7, 0, 3, 4)]
	for p in pens:
		for r in range(p.position.y, p.end.y):
			for c in range(p.position.x, p.end.x):
				food_cells[r * GRID_X + c] = 1
		for c in range(p.position.x, p.end.x):
			if p.end.y < GRID_Y:
				hwall[p.end.y * GRID_X + c] = 1
		for r in range(p.position.y, p.end.y):
			for c in [p.position.x, p.end.x]:
				if c > 0 and c < GRID_X:
					vwall[r * GRID_X + c] = 1
	_rebuild_solid()
	set_food_flow(3)
	for k in mini(designs.size(), pens.size()):
		var pr: Rect2i = pens[k]
		var center := Vector2i(int((pr.position.x + pr.size.x / 2.0) * CELL_W), int((pr.position.y + pr.size.y / 2.0) * CELL_H))
		var g := Genome.from_sni(designs[k], 3)
		g[Genome.G.MOMENTUM] = body_vars[Genome.classify(g)].default_momentum
		var placed := 0
		var tries := 0
		while placed < per_pen and tries < per_pen * 20:
			tries += 1
			var x := center.x + rng.randi_range(-12, 12)
			var y := center.y + rng.randi_range(-12, 12)
			if spawn(x, y, g) >= 0:
				placed += 1


# ===========================================================================
# Clock helpers
# ===========================================================================

func clock_hms() -> Vector3i:
	var t := int(game_time) % 86400
	return Vector3i(t / 3600, (t / 60) % 60, t % 60)


func day() -> int:
	return int(game_time) / 86400 + 1


## Calendar date shown under the clock (starts 07/17).
func month_day() -> Vector2i:
	var lengths := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var m := START_MONTH
	var d := START_DAY + int(game_time) / 86400
	while d > lengths[m - 1]:
		d -= lengths[m - 1]
		m = m % 12 + 1
	return Vector2i(m, d)
