extends SceneTree
## Headless soak test of the lab simulation:
##   godot --headless --path . --script res://tests/sim_soak.gd
## Runs the demo pens at each mutation level and prints population by type.

func run(level: int, minutes: int) -> void:
	var sim := LabSim.new()
	sim.npr = 2
	sim.rng.seed = 12345
	sim.build_demo([[1, 3, 3, 2, 2, 10, 2], [1, 3, 3, 1, 8, 6, 1], [1, 3, 3, 8, 1, 6, 1]])
	sim.mutation_level = level
	print("--- mutation level %d ---" % level)
	for minute in minutes + 1:
		if minute % 3 == 0:
			var c := sim.count_types()
			var vir := 0
			var ster := 0
			var food := 0
			for i in LabSim.CAPACITY:
				if sim.alive[i]:
					if sim.virus[i]: vir += 1
					if sim.sterile[i]: ster += 1
			for f in sim.food: food += f
			print("min %2d pop %4d  Z%4d H%4d S%4d B%3d  virus %4d sterile %4d food %5d births %5d deaths %5d" % [
				minute, sim.population, c[0], c[1], c[2], c[3], vir, ster, food, sim.births, sim.deaths])
		for s in 60:
			sim.step()

func _init() -> void:
	run(0, 30)
	run(2, 30)
	quit()
