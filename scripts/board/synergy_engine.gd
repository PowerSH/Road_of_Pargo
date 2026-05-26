class_name SynergyEngine
extends RefCounted

## Computes ComputedStats for every placed OwnedUnit on a BoardState by applying
## all matching SynergyRules. Stateless — pass rules in each call so the
## roguelite run can swap rulesets (e.g. event-modified rules).
##
## Bonuses are additive within a stat (rule A: +10% atk and rule B: +20% atk
## yields +30% atk total — final = base * 1.30). This keeps balance intuitive
## and lets the synergy axis count expand without re-tuning multipliers.
##
## board의 셀에는 OwnedUnit이 들어있다. 시너지 매칭은 UnitData(`owned.source`) 기준.


static func compute(board: BoardState, rules: Array[SynergyRule]) -> Dictionary:
	var result: Dictionary = {}  ## Vector2i(col, row) -> ComputedStats
	for entry in board.iter_placed():
		var row: int = entry.row
		var col: int = entry.col
		var owned: OwnedUnit = entry.unit
		var unit: UnitData = owned.source
		if unit == null:
			continue

		var neighbors_owned: Array = board.get_adjacent(row, col)
		var neighbors: Array[UnitData] = []
		for n in neighbors_owned:
			var n_owned: OwnedUnit = n
			if n_owned != null and n_owned.source != null:
				neighbors.append(n_owned.source)

		var atk_bonus: float = 0.0
		var hp_bonus: float = 0.0
		var atkspd_bonus: float = 0.0
		var movespd_bonus: float = 0.0
		var range_bonus: float = 0.0
		var applied: Array[StringName] = []

		for rule in rules:
			if not rule.matches_self(unit):
				continue
			if rule.count_qualifying(neighbors) < rule.min_adjacent:
				continue
			atk_bonus += rule.attack_bonus_pct
			hp_bonus += rule.hp_bonus_pct
			atkspd_bonus += rule.attack_speed_bonus_pct
			movespd_bonus += rule.move_speed_bonus_pct
			range_bonus += rule.range_bonus_pct
			applied.append(rule.id)

		var stats := ComputedStats.from_base(unit)
		stats.max_hp = unit.max_hp * (1.0 + hp_bonus)
		stats.attack = unit.attack * (1.0 + atk_bonus)
		stats.attack_speed = unit.attack_speed * (1.0 + atkspd_bonus)
		stats.attack_range = unit.attack_range * (1.0 + range_bonus)
		stats.move_speed = unit.move_speed * (1.0 + movespd_bonus)
		stats.applied_synergies = applied

		result[Vector2i(col, row)] = stats
	return result
