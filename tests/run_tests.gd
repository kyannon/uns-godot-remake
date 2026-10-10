extends SceneTree
## Headless test suite:
##   godot --headless --path . --script res://tests/run_tests.gd
## Decoder tests run only if UNS_GAME_DIR points at an original install.

var failures := 0
var passes := 0


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		printerr("FAIL: ", what)


func _init() -> void:
	test_classification()
	test_sni_limits()
	test_walls_contain()
	test_births_respect_walls()
	test_food_resupply()
	test_food_flow_density()
	test_starvation()
	test_decoder()
	print("%d passed, %d failed" % [passes, failures])
	quit(1 if failures > 0 else 0)


func test_classification() -> void:
	# The manual's "standard" Theroids (p.110), as SNI bar counts
	check(Genome.classify(Genome.from_sni([1, 3, 3, 1, 8, 6, 1], 3)) == Genome.HULK, "standard Hulk")
	check(Genome.classify(Genome.from_sni([1, 3, 3, 2, 2, 10, 2], 1)) == Genome.SLUG, "standard Slug")
	check(Genome.classify(Genome.from_sni([1, 3, 3, 8, 1, 6, 1], 5)) == Genome.ZIP, "standard Zip")
	var beast := PackedInt32Array([48, 90, 90, 210, 210, 210, 10, 3])
	check(Genome.classify(beast) == Genome.BEAST, "beast thresholds")


func test_sni_limits() -> void:
	# tutorial Slug: 16 clicks over the 1-bar baseline = exactly 256 ml
	var bars := [1, 3, 3, 2, 2, 10, 2]
	var used := 0
	for b in bars:
		used += b - 1
	check(used * Genome.SNI_ML_PER_BAR == Genome.SNI_MAX_ML, "tutorial slug uses 256 ml")


func _box(sim: LabSim, c0: int, r0: int, c1: int, r1: int) -> void:
	for c in range(c0, c1):
		if r0 > 0:
			sim.set_wall({"kind": "h", "r": r0, "c": c}, true)
		if r1 < LabSim.GRID_Y:
			sim.set_wall({"kind": "h", "r": r1, "c": c}, true)
	for r in range(r0, r1):
		if c0 > 0:
			sim.set_wall({"kind": "v", "r": r, "c": c0}, true)
		if c1 < LabSim.GRID_X:
			sim.set_wall({"kind": "v", "r": r, "c": c1}, true)


func test_walls_contain() -> void:
	var sim := LabSim.new()
	sim.rng.seed = 7
	_box(sim, 4, 4, 6, 6)
	var zip := Genome.from_sni([1, 1, 1, 12, 1, 4, 16], 7)
	for k in 12:
		sim.spawn(4 * 17 + 3 + (k % 4) * 6, 4 * 9 + 3 + (k / 4) * 4, zip)
	var escaped := false
	for s in 600:
		sim.step()
		for i in LabSim.CAPACITY:
			if sim.alive[i]:
				if sim.cx[i] < 4 * 17 or sim.cx[i] + 1 > 6 * 17 or sim.cy[i] < 4 * 9 or sim.cy[i] + 1 > 6 * 9:
					escaped = true
	check(not escaped, "walls keep creatures in their pen")


func test_births_respect_walls() -> void:
	var sim := LabSim.new()
	sim.rng.seed = 99
	_box(sim, 2, 2, 3, 3)  # one-cell "veal-calf" pen
	sim.food_cells[2 * 10 + 2] = 1
	sim.food_flow = 3
	sim.resupply_food()
	var breeder := Genome.from_sni([1, 16, 1, 1, 1, 12, 4], 1)
	sim.spawn(2 * 17 + 3, 2 * 9 + 2, breeder)
	sim.spawn(2 * 17 + 9, 2 * 9 + 4, breeder)
	var outside := false
	for s in 1200:
		sim.step()
		for i in LabSim.CAPACITY:
			if sim.alive[i] and (sim.cx[i] < 2 * 17 or sim.cx[i] + 1 > 3 * 17 or sim.cy[i] < 2 * 9 or sim.cy[i] + 1 > 3 * 9):
				outside = true
	check(sim.births > 0, "breeders in a small pen reproduce (births=%d)" % sim.births)
	check(not outside, "newborns appear inside the parents' pen")


func test_food_resupply() -> void:
	var sim := LabSim.new()
	sim.set_food_cell(55, true)
	var n := 0
	for f in sim.food:
		n += f
	check(n == 0, "no food grows while food flow is 0")
	sim.food_flow = 3
	for s in 61:
		sim.step()
	n = 0
	for f in sim.food:
		n += f
	check(n == (LabSim.CELL_W - 1) * (LabSim.CELL_H - 1), "flow 3 refills a cell within 60 s (got %d)" % n)


func test_food_flow_density() -> void:
	var sim := LabSim.new()
	sim.set_food_cell(55, true)
	sim.set_food_flow(3)
	var full := 0
	for f in sim.food: full += f
	sim.set_food_flow(1)
	var sparse := 0
	for f in sim.food: sparse += f
	sim.set_food_flow(0)
	var none := 0
	for f in sim.food: none += f
	check(full > 0 and sparse > 0 and sparse < full / 2, "flow 1 is sparser than flow 3 (%d vs %d)" % [sparse, full])
	check(none == 0, "flow 0 removes all food from the pen")


func test_starvation() -> void:
	# 9 Slugs, no food: must die out quickly and births must not create energy
	var sim := LabSim.new()
	sim.rng.seed = 5
	var g := Genome.from_sni([1, 3, 3, 2, 2, 10, 2], 1)
	for k in 9:
		sim.spawn(80 + (k % 3) * 3, 40 + (k / 3) * 3, g)
	var t := 0
	while sim.population > 0 and t < 3000:
		sim.step()
		t += 1
	check(sim.population == 0, "a foodless pen dies out (took %d game s)" % t)
	check(t < 600, "starvation takes under 10 game minutes (took %d s)" % t)


func test_decoder() -> void:
	var dir := OS.get_environment("UNS_GAME_DIR")
	if dir.is_empty():
		print("(decoder tests skipped: set UNS_GAME_DIR to an original install)")
		return
	var al1 := UnsArchive.open(UnsArchive.find_file(dir, "data/al1.bin"))
	check(al1 != null and al1.entries.size() == 133, "al1.bin has 133 entries")
	var bg := UnsArchive.decode_image(al1.get_entry(2))
	check(bg.w == 320 and bg.h == 200, "lab console is 320x200")
	check(al1.get_entry(2).palette.size() == 768, "lab console carries a full palette")
	var al5 := UnsArchive.open(UnsArchive.find_file(dir, "data/al5.bin"))
	check(UnsArchive.decode_text(al5.get_entry(0)) == "as we got closer, the nightmares got worse.", "intro subtitle text")
	var hulks := UnsArchive.open(UnsArchive.find_file(dir, "data/hulks.bin"))
	var h0 := UnsArchive.decode_image(hulks.get_entry(0))
	check(h0.w == 10 and h0.h == 6, "hulk sprite 0 is 10x6")
	# every R/N image in every container decodes to a sane size
	var bad := 0
	var total := 0
	var da := DirAccess.open(UnsArchive.find_file(dir, "data"))
	for f in da.get_files():
		if not f.to_lower().ends_with(".bin") or f.to_lower() == "isltiles.bin":
			continue
		var arc := UnsArchive.open(da.get_current_dir().path_join(f))
		for e in arc.entries:
			if e.type == "R" or e.type == "N":
				total += 1
				if UnsArchive.decode_image(e).is_empty():
					bad += 1
	check(bad == 0, "all %d still images decode (%d failed)" % [total, bad])
