extends Node2D
## The DigiLife AL-2000 lab console (Independent Research mode).
## Everything is drawn in the original 320x200 coordinate space; the project's
## stretch settings scale it up to the window (integer steps by default, F10
## toggles fractional, F11 fullscreen).

signal request_setup

const L = preload("res://scripts/ui/LabLayout.gd")

var sim: LabSim
var pal: UnsPalette

var module := "HABITAT"
var zoom := 1
var tool := ""            # "", "walls", "food"
var highlight := ""       # "", "fight", "mate"
var scan := -1            # View module scan button: gene index 0..7, 8 = virus
var _scan_max := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
var sni_bars := [1, 3, 3, 2, 2, 10, 2]   # the manual's standard Slug
var count_sel := 9
var inject_left := 0
var selected := -1
var zoom_center := Vector2(85, 45)
var debug_rects := false

var _pen_img: Image
var _pen_tex: ImageTexture
var _pen_bytes := PackedByteArray()
var _lut := PackedByteArray()
var _drag := {}            # active pen drag state
var _toast := ""
var _toast_t := 0.0
var _menu: PopupMenu
var _hover := Vector2.ZERO


func _ready() -> void:
	pal = Assets.lab_palette
	_lut.resize(256 * 4)
	for i in 256:
		var c := pal.colors[i]
		_lut[i * 4] = c.r8
		_lut[i * 4 + 1] = c.g8
		_lut[i * 4 + 2] = c.b8
		_lut[i * 4 + 3] = 255
	_pen_bytes.resize(LabSim.W * LabSim.H * 4)
	_pen_img = Image.create_from_data(LabSim.W, LabSim.H, false, Image.FORMAT_RGBA8, _pen_bytes)
	_pen_tex = ImageTexture.create_from_image(_pen_img)
	new_experiment()
	_build_menu()


func new_experiment() -> void:
	sim = LabSim.new()
	selected = -1
	inject_left = 0
	zoom = 1
	toast("NEW EXPERIMENT")


func _build_menu() -> void:
	_menu = PopupMenu.new()
	_menu.add_item("New experiment", 0)
	_menu.add_item("Load textbook pen layout (demo)", 1)
	_menu.add_separator()
	_menu.add_check_item("Integer scaling (F10)", 2)
	_menu.add_check_item("Fullscreen (F11)", 3)
	_menu.add_separator()
	_menu.add_item("Change game data folder...", 4)
	_menu.add_item("Quit", 5)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


func _on_menu(id: int) -> void:
	match id:
		0:
			new_experiment()
		1:
			_demo_layout()
		2:
			Settings.toggle_integer_scaling()
		3:
			Settings.toggle_fullscreen()
		4:
			request_setup.emit()
		5:
			get_tree().quit()


func _open_menu() -> void:
	_menu.set_item_checked(_menu.get_item_index(2), Settings.integer_scaling)
	_menu.set_item_checked(_menu.get_item_index(3), Settings.fullscreen)
	_menu.popup(Rect2i(get_viewport().get_mouse_position(), Vector2i.ZERO))


## Three pens like the tutorial, filled with food. Handy for testing.
func _demo_layout() -> void:
	new_experiment()
	sim.build_demo([[1, 3, 3, 2, 2, 10, 2], [1, 3, 3, 1, 8, 6, 1], [1, 3, 3, 8, 1, 6, 1]])
	sim.npr = 2
	for i in LabSim.CAPACITY:
		if sim.alive[i]:
			selected = i
			break
	toast("DEMO: SLUGS / HULKS / ZIPS")


func toast(msg: String) -> void:
	_toast = msg
	_toast_t = 3.0


func _process(delta: float) -> void:
	sim.update(delta)
	if selected >= 0 and not sim.alive[selected]:
		selected = -1
		if zoom == 3:
			zoom = 2
	if selected >= 0:
		zoom_center = Vector2(sim.cx[selected] + 1, sim.cy[selected] + 1)
	if _toast_t > 0.0:
		_toast_t -= delta
	_hover = get_local_mouse_position()
	_render_pen()
	queue_redraw()


# ===========================================================================
# Pen rendering
# ===========================================================================

func _render_pen() -> void:
	var W := LabSim.W
	var H := LabSim.H
	var b := _pen_bytes
	var lut := _lut
	var food := sim.food
	var solid := sim.solid
	var cf := L.COL_FOOD * 4
	var cw := L.COL_WALL * 4
	var c0 := 0
	for y in H:
		var row := y * W
		var trench_row := y % LabSim.CELL_H == 0
		for x in W:
			var i := row + x
			var src := c0
			if solid[i]:
				src = c0 if (x == 0 or y == 0 or x == W - 1 or y == H - 1) else cw
			elif food[i]:
				src = cf
			elif trench_row or x % LabSim.CELL_W == 0:
				src = c0
			var o := i * 4
			b[o] = lut[src]
			b[o + 1] = lut[src + 1]
			b[o + 2] = lut[src + 2]
			b[o + 3] = 255
	# creatures
	var hl_mode := -1
	if highlight == "fight":
		hl_mode = LabSim.Mode.FIGHT
	elif highlight == "mate":
		hl_mode = LabSim.Mode.MATE
	var scanning := module == "VIEW" and scan >= 0
	for i in LabSim.CAPACITY:
		if not sim.alive[i]:
			continue
		var col: int = L.TYPE_COLOR[sim.ctype[i]]
		if hl_mode >= 0 and sim.mode[i] != hl_mode:
			col = 20  # ghosted
		elif scanning and not _scan_match(i):
			col = 20
		if sim.mode[i] == LabSim.Mode.DYING:
			col = 13
		var s := col * 4
		var x0 := sim.cx[i]
		var y0 := sim.cy[i]
		for oy in 2:
			for ox in 2:
				var o2 := ((y0 + oy) * W + x0 + ox) * 4
				b[o2] = lut[s]
				b[o2 + 1] = lut[s + 1]
				b[o2 + 2] = lut[s + 2]
	_pen_img.set_data(W, H, false, Image.FORMAT_RGBA8, b)
	_pen_tex.update(_pen_img)


func _zoom2_src() -> Rect2:
	var sz := Vector2(L.PEN.size.x / 4.0, L.PEN.size.y / 4.0)
	var pos := zoom_center - sz / 2.0
	pos.x = clampf(pos.x, 0, LabSim.W - sz.x)
	pos.y = clampf(pos.y, 0, LabSim.H - sz.y)
	return Rect2(pos, sz)


## Screen (logical) point -> pen pixel, or Vector2(-1,-1) outside the pen.
func _screen_to_pen(p: Vector2) -> Vector2:
	if not L.PEN.has_point(p):
		return Vector2(-1, -1)
	var local := p - L.PEN.position
	if zoom == 1:
		return local
	if zoom == 2:
		var src := _zoom2_src()
		return src.position + local / 4.0
	return Vector2(-1, -1)


func _pen_to_screen(p: Vector2) -> Vector2:
	if zoom == 1:
		return L.PEN.position + p
	var src := _zoom2_src()
	return L.PEN.position + (p - src.position) * 4.0


# ===========================================================================
# Drawing
# ===========================================================================

func _c(idx: int) -> Color:
	return pal.colors[idx]


func spr(rel: String, idx: int, pos: Vector2) -> void:
	var tex := Assets.texture(rel, idx)
	if tex == null:
		return
	var size := Assets.size_of(rel, idx)
	draw_texture_rect(tex, Rect2(pos, Vector2(size)), false)


func text(pos: Vector2, s: String, col: Color, font := "4x6") -> void:
	Assets.draw_text(self, pos, s, col, font)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 200), Color.BLACK)
	spr(L.AL1, L.BACKGROUND, Vector2.ZERO)
	_draw_modules()
	_draw_fight_mate()
	_draw_npr()
	_draw_zoom_panel()
	_draw_clock()
	_draw_pen()
	match module:
		"HABITAT":
			_draw_habitat()
		"VIEW":
			_draw_view()
	_draw_cursor_overlay()
	if _toast_t > 0.0:
		var w := _toast.length() * 4 + 4
		var p := Vector2(L.PEN.position.x + (L.PEN.size.x - w) / 2.0, L.PEN.end.y - 9)
		draw_rect(Rect2(p, Vector2(w, 8)), Color(0, 0, 0, 0.75))
		text(p + Vector2(2, 1), _toast, _c(L.COL_GREEN))
	if debug_rects:
		_draw_debug()


func _draw_modules() -> void:
	for m in L.MODULES:
		spr(L.AL3, m.sprite + (1 if module == m.name else 0), m.pos)


func _draw_fight_mate() -> void:
	for pair in [["fight", L.FIGHT_BTN, LabSim.Mode.FIGHT], ["mate", L.MATE_BTN, LabSim.Mode.MATE]]:
		var btn: Dictionary = pair[1]
		if highlight == pair[0]:
			spr(L.AL3, btn.dark, btn.pos)
			var n := str(sim.count_mode(pair[2]))
			text(btn.pos + Vector2(18 - n.length() * 2, 5), n, _c(L.COL_GREEN))
		else:
			spr(L.AL3, btn.lit, btn.pos)


func _draw_npr() -> void:
	var tube := L.NPR_TUBE
	var top_y: float = L.NPR_LEVEL_Y[sim.npr]
	if sim.npr > 0:
		draw_rect(Rect2(tube.position.x, top_y, tube.size.x, tube.end.y - top_y), Color(_c(55), 0.65))
	draw_rect(Rect2(tube.position.x, top_y - 1, tube.size.x, 2), _c(34))
	draw_circle(Vector2(L.NPR_SCALE_X, top_y), 2.0, _c(35))


func _draw_zoom_panel() -> void:
	spr(L.AL3, L.ZOOM_PANEL.sprite, L.ZOOM_PANEL.pos)
	var r: Rect2 = L.ZOOM_ICONS[zoom - 1]
	draw_rect(r, Color(_c(37), 0.35))
	draw_rect(r, _c(37), false, 1.0)


func _draw_clock() -> void:
	var t := sim.clock_hms()
	text(L.CLOCK_TIME, "%02d:%02d" % [t.x, t.y], _c(L.COL_GREEN))
	var d := sim.day() - 1
	text(L.CLOCK_DATE, "%d/%02d" % [d / 30 + 1, d % 30 + 1], _c(L.COL_GREEN))
	var a := (t.z / 5) * TAU / 12.0 - PI / 2.0
	draw_rect(Rect2(L.CLOCK_CENTER + Vector2(cos(a), sin(a)) * L.CLOCK_RADIUS - Vector2(1, 1), Vector2(2, 2)), _c(L.COL_GREEN))


func _draw_pen() -> void:
	var pen := L.PEN
	match zoom:
		1:
			draw_texture_rect(_pen_tex, pen, false)
			_draw_grid_overlay(1.0, Vector2.ZERO)
		2:
			var src := _zoom2_src()
			draw_texture_rect_region(_pen_tex, pen, src)
			_draw_grid_overlay(4.0, src.position)
			# overview window replaces the DigiLife label
			draw_texture_rect(_pen_tex, L.OVERVIEW, false)
			var o := L.OVERVIEW
			var s := o.size.x / LabSim.W
			draw_rect(Rect2(o.position + src.position * s, src.size * s), Color.WHITE, false, 1.0)
		3:
			draw_rect(pen, Color.BLACK)
			if selected >= 0:
				var t := sim.ctype[selected]
				var tex := Assets.texture(L.BACK, L.TYPE_PORTRAIT[t])
				if tex:
					draw_texture_rect(tex, pen, false)
				var label := "%s  %s" % [Genome.TYPE_NAMES[t].to_upper(), LabSim.MODE_NAMES[sim.mode[selected]]]
				draw_rect(Rect2(pen.position.x, pen.position.y, label.length() * 4 + 4, 8), Color(0, 0, 0, 0.7))
				text(pen.position + Vector2(2, 1), label, _c(L.COL_GREEN))
	if zoom < 3 and selected >= 0:
		var p := _pen_to_screen(Vector2(sim.cx[selected], sim.cy[selected]))
		var sz := 2.0 if zoom == 1 else 8.0
		_bracket(Rect2(p - Vector2(2, 2), Vector2(sz + 4, sz + 4)))
	elif zoom < 3 and sim.population == 0:
		_bracket(Rect2(L.PEN.get_center() - Vector2(3, 3), Vector2(6, 6)))


func _draw_grid_overlay(scale: float, origin: Vector2) -> void:
	if tool == "":
		return
	var pen := L.PEN
	var col := Color(_c(34), 0.55) if tool == "walls" else Color(_c(37), 0.45)
	for c in range(0, LabSim.GRID_X + 1):
		var x := pen.position.x + (c * LabSim.CELL_W - origin.x) * scale
		if x >= pen.position.x and x <= pen.end.x:
			for r in range(0, LabSim.GRID_Y + 1):
				var y := pen.position.y + (r * LabSim.CELL_H - origin.y) * scale
				if y >= pen.position.y and y <= pen.end.y:
					draw_rect(Rect2(x, y, 1, 1), col)
	var pp := _screen_to_pen(_hover)
	if pp.x < 0:
		return
	if tool == "walls":
		var slot := sim.wall_slot_at(pp.x, pp.y, Input.is_key_pressed(KEY_SHIFT))
		if not slot.is_empty():
			var a: Vector2
			var b: Vector2
			if slot.kind == "h":
				a = Vector2(slot.c * LabSim.CELL_W, slot.r * LabSim.CELL_H)
				b = a + Vector2(LabSim.CELL_W, 0)
			else:
				a = Vector2(slot.c * LabSim.CELL_W, slot.r * LabSim.CELL_H)
				b = a + Vector2(0, LabSim.CELL_H)
			draw_line(_pen_to_screen(a), _pen_to_screen(b), Color.WHITE, 1.0)
	else:
		var cell := sim.cell_at(pp.x, pp.y)
		if cell >= 0:
			var a2 := Vector2((cell % LabSim.GRID_X) * LabSim.CELL_W, (cell / LabSim.GRID_X) * LabSim.CELL_H)
			var r2 := Rect2(_pen_to_screen(a2), Vector2(LabSim.CELL_W, LabSim.CELL_H) * scale)
			draw_rect(r2.intersection(pen), Color.WHITE, false, 1.0)


func _bracket(r: Rect2) -> void:
	var c := Color.WHITE
	var k := 2.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		draw_line(corner, corner + Vector2(k * sx, 0), c, 1.0)
		draw_line(corner, corner + Vector2(0, k * sy), c, 1.0)


func _draw_habitat() -> void:
	var design := _genes_from(sni_bars)
	var btype := Genome.classify(design)
	var body_col := _c(L.TYPE_COLOR[btype])
	# serum figures (only meaningful in Top Secret games, shown as in the original)
	for row in 7:
		text(Vector2(L.SNI_NUM_X, L.SNI_ROWS_Y[row] - 1), "900", _c(L.COL_ORANGE))
		for b in 16:
			var on: bool = b < sni_bars[row]
			draw_rect(Rect2(L.SNI_BAR_X + b * 2, L.SNI_ROWS_Y[row], 1, 5), body_col if on else _c(L.COL_BAR_OFF))
	# creature icon + neutral serum
	spr(L.AL1, L.TYPE_ICON[btype], L.SNI_ICON_POS)
	text(L.SNI_ICON_NUM, "500", _c(L.COL_TEXT))
	# fluid used graph
	var used := _sni_used()
	var g := L.SNI_GRAPH
	for i in 16:
		var h := 2.0 + i * 2.0
		var lit := i < used
		draw_rect(Rect2(g.position.x + i * 2, g.end.y - h, 1, h), body_col if lit else _c(L.COL_BAR_OFF))
	text(L.SNI_GRAPH_NUM, str(used * Genome.SNI_ML_PER_BAR), _c(L.COL_TEXT))
	# count buttons + inject
	for cb in L.COUNT_BUTTONS:
		spr(L.AL3, cb.sprite + (1 if count_sel == cb.n else 0), cb.pos)
	spr(L.AL3, L.INJECT_BTN.sprite + (1 if inject_left > 0 else 0), L.INJECT_BTN.pos)
	# habitat tools
	spr(L.AL3, L.WALLS_BTN.sprite + (1 if tool == "walls" else 0), L.WALLS_BTN.pos)
	spr(L.AL3, L.FOOD_BTN.sprite + (1 if tool == "food" else 0), L.FOOD_BTN.pos)
	spr(L.AL3, L.MUTATION_DIAL.sprite + sim.mutation_level, L.MUTATION_DIAL.pos)
	for ff in L.FOOD_FLOW:
		spr(L.AL3, ff.sprite + (1 if sim.food_flow == ff.n else 0), ff.pos)
	spr(L.AL1, L.FOOD_TUBE.sprite + sim.food_flow, L.FOOD_TUBE.pos)


func _scan_value(i: int, k: int) -> int:
	if k == 8:
		return 1 if sim.virus[i] else 0
	return sim.expressed(i, k) if k == Genome.G.VISION else sim.gene(i, k)


func _scan_match(i: int) -> bool:
	if scan == 8:
		return sim.virus[i] != 0
	return _scan_value(i, scan) >= _scan_max[scan] and _scan_max[scan] > 0


func _update_scan_max() -> void:
	_scan_max.fill(0)
	for i in LabSim.CAPACITY:
		if not sim.alive[i]:
			continue
		for k in 8:
			_scan_max[k] = maxi(_scan_max[k], _scan_value(i, k))
		if sim.virus[i]:
			_scan_max[8] += 1


func _scan_rect(k: int) -> Rect2:
	var cell := L.VIEW_SCAN_CELL
	return Rect2(L.VIEW_SCAN_ORIGIN + Vector2((k % 3) * cell.x, (k / 3) * cell.y), cell - Vector2(3, 3))


func _bar_row(y: float, total: int, level: int, col: Color, peak: bool, used_from: int = -1) -> void:
	for b in 16:
		var c := _c(L.COL_BAR_OFF)
		if b < total:
			c = _c(L.COL_WHITE)
		if b < level:
			c = col
		if used_from >= 0 and b >= used_from and b < total:
			c = _c(L.COL_YELLOW)
		if peak and b == total - 1:
			c = _c(L.COL_YELLOW)
		draw_rect(Rect2(L.VIEW_BARS_X + b * 2, y, 1, 6), c)


func _draw_view() -> void:
	spr(L.AL1, L.VIEW_PANEL.sprite, L.VIEW_PANEL.pos)
	_update_scan_max()
	# scan buttons: highest value of each trait in the pen
	for k in 9:
		var r := _scan_rect(k)
		var active := scan == k
		draw_rect(Rect2(r.position + Vector2(0, 7), Vector2(r.size.x, r.size.y - 7)), _c(39) if active else Color.BLACK)
		draw_rect(Rect2(r.position + Vector2(0, 7), Vector2(r.size.x, r.size.y - 7)), _c(16), false, 1.0)
		text(r.position + Vector2(1, 0), L.VIEW_SCAN_LABELS[k], _c(L.COL_WHITE))
		var num := str(_scan_max[k])
		text(r.position + Vector2(r.size.x / 2.0 - num.length() * 2, 10), num, Color.BLACK if active else _c(L.COL_GREEN))
	if selected < 0:
		text(L.VIEW_ACTION, "NONE", _c(L.COL_GREEN))
		return
	var i := selected
	var t := sim.ctype[i]
	var body := _c(L.TYPE_COLOR[t])
	var dn := sim.dominant_need(i)
	# needs: white = potential, body colour = current level, yellow = maxed out
	for n in 3:
		var total := ceili(sim.gene(i, n) / 16.0)
		var level := ceili(sim.need(i, n) / 16.0)
		_bar_row(L.VIEW_ROWS_Y[n], total, level, body, sim.need(i, n) >= sim.gene(i, n) - 0.5)
	_bar_row(L.VIEW_ROWS_Y[3], ceili(sim.gene(i, 3) / 16.0), 0, body, false)
	_bar_row(L.VIEW_ROWS_Y[4], ceili(sim.gene(i, 4) / 16.0), 0, body, false)
	var st_total := ceili(sim.expressed(i, Genome.G.STAMINA) / 16.0)
	var st_left := ceili(st_total * sim.stamina[i] / maxf(1.0, sim.max_stamina(i)))
	_bar_row(L.VIEW_ROWS_Y[5], st_total, 0, body, false, st_left)
	_bar_row(L.VIEW_ROWS_Y[6], ceili(sim.expressed(i, Genome.G.VISION) / 2.0), 0, body, false)
	# most pressing urge is written in body colour next to the panel label
	var urge_names := ["FIGHT", "MATE", "EAT"]
	text(Vector2(L.VIEW_BARS_X - 1 - urge_names[dn].length() * 4 - 3, L.VIEW_ROWS_Y[dn]), "", body)
	draw_rect(Rect2(L.VIEW_BARS_X - 3, L.VIEW_ROWS_Y[dn], 1, 6), body)
	# current action, icon, viruses
	var action: String = LabSim.MODE_NAMES[sim.mode[i]]
	text(L.VIEW_ACTION + Vector2(16 - action.length() * 2, 0), action, _c(L.COL_GREEN))
	spr(L.AL1, L.TYPE_ICON[t], L.VIEW_ICON)
	text(L.VIEW_VIRUS, _virus_str(i), _c(L.COL_ORANGE))
	var p := sim.partner[i]
	if p >= 0 and sim.alive[p]:
		spr(L.AL1, L.TYPE_ICON[sim.ctype[p]], L.VIEW_PARTNER_ICON)
		text(L.VIEW_PARTNER_VIRUS, _virus_str(p), _c(L.COL_ORANGE))


func _virus_str(i: int) -> String:
	var v := sim.virus[i]
	return ("X" if v & 1 else "") + ("Y" if v & 2 else "") + ("Z" if v & 4 else "")


func _draw_cursor_overlay() -> void:
	if inject_left > 0 and L.PEN.has_point(_hover):
		var r := Rect2(_hover + Vector2(4, 4), Vector2(9, 8))
		draw_rect(r, Color.BLACK)
		draw_rect(r, _c(L.COL_ORANGE), false, 1.0)
		text(r.position + Vector2(3, 1), str(inject_left), _c(L.COL_ORANGE))


func _draw_debug() -> void:
	var rects: Array = [L.PEN, L.COMM, L.DISK_DRIVE, L.FIGHT_BTN.rect, L.MATE_BTN.rect,
		L.INJECT_BTN.rect, L.WALLS_BTN.rect, L.FOOD_BTN.rect, L.MUTATION_KNOB]
	for m in L.MODULES:
		rects.append(m.rect)
	rects += L.NPR_LABELS + L.ZOOM_BUTTONS + L.MUTATION_LABELS
	for row in 7:
		rects.append(Rect2(L.SNI_LEFT_X, L.SNI_ARROW_Y[row], 8, 8))
		rects.append(Rect2(L.SNI_RIGHT_X, L.SNI_ARROW_Y[row], 9, 8))
	for cb in L.COUNT_BUTTONS:
		rects.append(Rect2(cb.pos, Vector2(18, 12)))
	for ff in L.FOOD_FLOW:
		rects.append(Rect2(ff.pos, Vector2(20, 11)))
	for r in rects:
		draw_rect(r, Color(1, 0, 1, 0.8), false, 1.0)
	var pops := sim.count_types()
	text(Vector2(2, 192), "POP %d  Z%d H%d S%d B%d  BIRTHS %d DEATHS %d" % [sim.population, pops[0], pops[1], pops[2], pops[3], sim.births, sim.deaths], Color.WHITE)


# ===========================================================================
# SNI helpers
# ===========================================================================

func _sni_used() -> int:
	var n := 0
	for b in sni_bars:
		n += b - 1
	return n


func _genes_from(bars: Array) -> PackedInt32Array:
	var g := Genome.from_sni(bars, 3)
	var t := Genome.classify(g)
	g[Genome.G.MOMENTUM] = sim.body_vars[t].default_momentum
	return g


func _sni_adjust(row: int, delta: int) -> void:
	var v: int = sni_bars[row] + delta
	if v < 1 or v > 16:
		return
	if delta > 0 and _sni_used() >= Genome.SNI_MAX_ML / Genome.SNI_ML_PER_BAR:
		toast("SNI FLUID LIMIT 256 ML")
		return
	sni_bars[row] = v


func _inject_at(pp: Vector2, all: bool) -> void:
	var g := _genes_from(sni_bars)
	var n := inject_left if all else 1
	var placed := 0
	var side := int(ceil(sqrt(float(n))))
	for k in n:
		var ox := (k % side - side / 2) * 3
		var oy := (k / side - side / 2) * 3
		var ok := -1
		for attempt in 6:
			var jx := 0 if attempt == 0 else sim.rng.randi_range(-attempt, attempt)
			var jy := 0 if attempt == 0 else sim.rng.randi_range(-attempt, attempt)
			ok = sim.spawn(int(pp.x) + ox + jx, int(pp.y) + oy + jy, g)
			if ok >= 0:
				break
		if ok >= 0:
			placed += 1
			if selected < 0:
				selected = ok
	inject_left -= placed
	if placed < n:
		toast("NO ROOM - TRY A MORE OPEN AREA")


# ===========================================================================
# Input
# ===========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F3:
				debug_rects = not debug_rects
			KEY_1:
				zoom = 1
			KEY_2:
				zoom = 2
			KEY_3:
				if selected >= 0:
					zoom = 3
			KEY_SPACE:
				sim.npr = 0 if sim.npr > 0 else 2
			KEY_ESCAPE:
				if inject_left > 0 or tool != "":
					inject_left = 0
					tool = ""
				else:
					_open_menu()
		return
	if event is InputEventMouseButton:
		var p := get_local_mouse_position()
		if event.pressed:
			_on_press(p, event.button_index)
		else:
			_drag = {}
	elif event is InputEventMouseMotion and not _drag.is_empty():
		_on_drag(get_local_mouse_position())


func _on_press(p: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
		return
	var right := button == MOUSE_BUTTON_RIGHT
	# pen
	if L.PEN.has_point(p):
		_on_pen_press(p, right)
		return
	if right:
		return
	# module buttons
	for m in L.MODULES:
		if m.rect.has_point(p):
			if m.name == "HABITAT" or m.name == "VIEW":
				module = m.name
			else:
				toast("%s MODULE: COMING IN MILESTONE 2" % m.name)
			return
	if L.FIGHT_BTN.rect.has_point(p):
		highlight = "" if highlight == "fight" else "fight"
		return
	if L.MATE_BTN.rect.has_point(p):
		highlight = "" if highlight == "mate" else "mate"
		return
	for lvl in 4:
		if L.NPR_LABELS[lvl].has_point(p):
			sim.npr = lvl
			return
	if L.NPR_TUBE.has_point(p):
		sim.npr = (sim.npr + 1) % 4
		return
	for z in 3:
		if L.ZOOM_BUTTONS[z].has_point(p):
			if z == 2 and selected < 0:
				toast("SELECT A THEROID FIRST")
			else:
				zoom = z + 1
			return
	if zoom == 2 and L.OVERVIEW.has_point(p):
		var local := (p - L.OVERVIEW.position) * (LabSim.W / L.OVERVIEW.size.x)
		var hit := sim.creature_at(int(local.x), int(local.y), 3)
		if hit >= 0:
			selected = hit
		else:
			zoom_center = local
		return
	if L.DISK_DRIVE.has_point(p):
		_open_menu()
		return
	if L.COMM.has_point(p):
		toast("COMM: TOP SECRET GAMES ONLY")
		return
	if module == "HABITAT":
		_habitat_press(p)
	elif module == "VIEW":
		for k in 9:
			if _scan_rect(k).has_point(p):
				scan = -1 if scan == k else k
				return


func _habitat_press(p: Vector2) -> void:
	for row in 7:
		if Rect2(L.SNI_LEFT_X, L.SNI_ARROW_Y[row], 8, 8).has_point(p):
			_sni_adjust(row, -1)
			return
		if Rect2(L.SNI_RIGHT_X, L.SNI_ARROW_Y[row], 9, 8).has_point(p):
			_sni_adjust(row, 1)
			return
	for cb in L.COUNT_BUTTONS:
		if Rect2(cb.pos, Vector2(18, 12)).has_point(p):
			count_sel = cb.n
			return
	if L.INJECT_BTN.rect.has_point(p):
		if inject_left > 0:
			inject_left = 0
		else:
			inject_left = count_sel
			tool = ""
			if sim.npr == 0:
				toast("TURN ON THE NPR TO ANIMATE THEM")
		return
	if L.WALLS_BTN.rect.has_point(p):
		tool = "" if tool == "walls" else "walls"
		inject_left = 0
		return
	if L.FOOD_BTN.rect.has_point(p):
		tool = "" if tool == "food" else "food"
		inject_left = 0
		return
	for lvl in 4:
		if L.MUTATION_LABELS[lvl].has_point(p):
			sim.mutation_level = lvl
			return
	if L.MUTATION_KNOB.has_point(p):
		sim.mutation_level = (sim.mutation_level + 1) % 4
		return
	for ff in L.FOOD_FLOW:
		if Rect2(ff.pos, Vector2(20, 11)).has_point(p):
			var was := sim.food_flow
			sim.food_flow = ff.n
			if was == 0 and ff.n > 0:
				sim.resupply_food()
			return


func _on_pen_press(p: Vector2, right: bool) -> void:
	var pp := _screen_to_pen(p)
	if pp.x < 0:
		return
	if inject_left > 0:
		_inject_at(pp, right)
		return
	if tool == "walls":
		var vertical := Input.is_key_pressed(KEY_SHIFT)
		var slot := sim.wall_slot_at(pp.x, pp.y, vertical)
		if slot.is_empty():
			return
		var target := not sim.get_wall(slot)
		_drag = {"kind": "walls", "on": target, "crush": right, "vertical": vertical}
		if not sim.set_wall(slot, target, right):
			toast("A THEROID IS IN THE WAY (RIGHT-CLICK CRUSHES)")
		return
	if tool == "food":
		var cell := sim.cell_at(pp.x, pp.y)
		if cell < 0:
			return
		if sim.food_flow == 0:
			toast("CHOOSE A FOOD FLOW LEVEL FIRST")
		var on := sim.food_cells[cell] == 0
		_drag = {"kind": "food", "on": on}
		sim.set_food_cell(cell, on)
		return
	var hit := sim.creature_at(int(pp.x), int(pp.y), 3 if zoom == 1 else 1)
	if hit >= 0:
		selected = hit
	elif zoom == 2:
		zoom_center = pp


func _on_drag(p: Vector2) -> void:
	var pp := _screen_to_pen(p)
	if pp.x < 0:
		return
	if _drag.kind == "walls":
		var slot := sim.wall_slot_at(pp.x, pp.y, _drag.vertical)
		if not slot.is_empty() and slot.dist < 2.5 and sim.get_wall(slot) != _drag.on:
			sim.set_wall(slot, _drag.on, _drag.crush)
	elif _drag.kind == "food":
		var cell := sim.cell_at(pp.x, pp.y)
		if cell >= 0 and (sim.food_cells[cell] == 1) != _drag.on:
			sim.set_food_cell(cell, _drag.on)
