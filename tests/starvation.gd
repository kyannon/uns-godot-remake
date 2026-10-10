extends SceneTree
## Measures time to extinction for 9 creatures of each standard type in an
## empty, foodless pen (the "9 in a pen with no food at MAX" test).
##   godot --headless --path . --script res://tests/starvation.gd

func _init() -> void:
	var designs := {"Slug": [1, 3, 3, 2, 2, 10, 2], "Hulk": [1, 3, 3, 1, 8, 6, 1], "Zip": [1, 3, 3, 8, 1, 6, 1]}
	for name in designs:
		var sim := LabSim.new()
		sim.rng.seed = 3
		var g := Genome.from_sni(designs[name], 3)
		for k in 9:
			sim.spawn(80 + (k % 3) * 3, 40 + (k / 3) * 3, g)
		var t := 0
		while sim.population > 0 and t < 20000:
			sim.step()
			t += 1
		print("%-5s 9 starving: extinct after %5d game s = %5.1f real s at MAX, %5.1f at FULL" % [
			name, t, t / LabSim.NPR_RATE[3], t / LabSim.NPR_RATE[2]])
	quit()
