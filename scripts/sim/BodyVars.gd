class_name BodyVars
extends RefCounted
## Per-body-type behaviour settings (the manual's "Body Variables" panel).
## Defaults are a first approximation; data/body.def holds the real ones and
## still needs to be decoded field-by-field (see docs/FORMATS.md).

enum Rule { ALWAYS, NEVER, AT_MAX }
enum Until { DEATH, NEED }

var fight_same: int = Rule.AT_MAX
var fight_until: int = Until.DEATH
var fight_satisfaction: float = 1.0    # 0..1
var damage_given: float = 1.0          # 0.5, 1, 2, 4
var damage_taken: float = 1.0          # 0.5, 1
var mate_others: int = Rule.ALWAYS
var mate_satisfaction: float = 1.0     # 0..1
var carnivorous: int = Rule.NEVER
var cannibalistic: int = Rule.NEVER
var corpse_size: int = 1               # food pixels left when it dies (0,1,2,4)
var default_momentum: int = 3          # 0..7


static func defaults_for(btype: int) -> BodyVars:
	var b := BodyVars.new()
	match btype:
		Genome.HULK:
			b.fight_same = Rule.NEVER  # manual: Hulks & Beasts don't fight each other by default
			b.default_momentum = 3
		Genome.ZIP:
			b.default_momentum = 5
		Genome.SLUG:
			b.default_momentum = 1
		Genome.BEAST:
			b.fight_same = Rule.NEVER
			b.damage_given = 2.0
			b.corpse_size = 4
		Genome.TANK:
			b.damage_given = 2.0
			b.damage_taken = 0.5
			b.corpse_size = 4
	return b
