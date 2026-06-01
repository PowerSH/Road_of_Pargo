class_name SynergyEngine
extends RefCounted

## Computes ComputedStats for every placed OwnedUnit on a BoardState by applying
## matching SynergyRules. Stateless — pass rules in each call so the roguelite
## run can swap rulesets (e.g. event-modified rules).
##
## ⚙️ Tier 치환 (TFT-style): 같은 (applies_to_type, requires_adjacent_type) 쌍의
## 여러 룰(예: 벤+보병 min_adjacent 2/3/4/5)이 매칭되면 **가장 높은 min_adjacent
## 룰 1개만 적용**. 시트의 수치는 "이 티어에서의 총 보너스"로 읽음.
## 다른 (self, adj) 쌍 사이는 합산. 같은 스탯 % 보너스는 합산 후 곱.
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

		# Tier 치환: (applies_to_type, requires_adjacent_type) 그룹별로 매칭되는 룰 중
		# min_adjacent가 가장 큰 것 1개만 살린다.
		var best_per_group: Dictionary = {}  ## String key -> SynergyRule
		for rule in rules:
			if not rule.matches_self(unit):
				continue
			if rule.count_qualifying(neighbors) < rule.min_adjacent:
				continue
			var key: String = "%s|%s" % [rule.applies_to_type, rule.requires_adjacent_type]
			var prev: SynergyRule = best_per_group.get(key)
			if prev == null or rule.min_adjacent > prev.min_adjacent:
				best_per_group[key] = rule

		# v1 multiplicative bonuses
		var atk_bonus: float = 0.0
		var hp_bonus: float = 0.0
		var atkspd_bonus: float = 0.0
		var movespd_bonus: float = 0.0
		var range_bonus: float = 0.0
		# v2 additive bonuses
		var defense_bonus: float = 0.0
		var crit_chance_bonus: float = 0.0
		var crit_multiplier_bonus: float = 0.0
		var armor_pen_bonus: float = 0.0
		var lifesteal_bonus: float = 0.0
		var hp_regen_bonus: float = 0.0
		var accuracy_bonus: float = 0.0
		var attack_variance_bonus: float = 0.0
		var applied: Array[StringName] = []

		for rule: SynergyRule in best_per_group.values():
			atk_bonus += rule.attack_bonus_pct
			hp_bonus += rule.hp_bonus_pct
			atkspd_bonus += rule.attack_speed_bonus_pct
			movespd_bonus += rule.move_speed_bonus_pct
			range_bonus += rule.range_bonus_pct
			defense_bonus += rule.defense_bonus
			crit_chance_bonus += rule.crit_chance_bonus
			crit_multiplier_bonus += rule.crit_multiplier_bonus
			armor_pen_bonus += rule.armor_penetration_bonus
			lifesteal_bonus += rule.lifesteal_bonus
			hp_regen_bonus += rule.hp_regen_bonus
			accuracy_bonus += rule.accuracy_bonus
			attack_variance_bonus += rule.attack_variance_pct_bonus
			applied.append(rule.id)

		var stats := ComputedStats.from_base(unit)
		stats.max_hp = unit.max_hp * (1.0 + hp_bonus)
		stats.attack = unit.attack * (1.0 + atk_bonus)
		stats.attack_speed = unit.attack_speed * (1.0 + atkspd_bonus)
		stats.attack_range = unit.attack_range * (1.0 + range_bonus)
		stats.move_speed = unit.move_speed * (1.0 + movespd_bonus)
		# v2 additive
		stats.defense = clampf(unit.defense + defense_bonus, 0.0, 0.95)
		stats.crit_chance = clampf(unit.crit_chance + crit_chance_bonus, 0.0, 1.0)
		stats.crit_multiplier = maxf(unit.crit_multiplier + crit_multiplier_bonus, 1.0)
		stats.armor_penetration = clampf(unit.armor_penetration + armor_pen_bonus, 0.0, 1.0)
		stats.lifesteal = clampf(unit.lifesteal + lifesteal_bonus, 0.0, 1.0)
		stats.hp_regen = maxf(unit.hp_regen + hp_regen_bonus, 0.0)
		stats.accuracy = clampf(unit.accuracy + accuracy_bonus, 0.0, 1.0)
		stats.attack_variance_pct = clampf(unit.attack_variance_pct + attack_variance_bonus, 0.0, 1.0)
		stats.applied_synergies = applied

		result[Vector2i(col, row)] = stats
	return result
