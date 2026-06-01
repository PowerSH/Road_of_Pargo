class_name EnemySynergyEngine
extends RefCounted

## 적 진영 시너지의 pre-battle 평가. EnemySynergyRule 중
## is_pre_battle() == true 인 룰만 처리 (GLOBAL_TRAIT, BOSS_AURA).
## DEATH_TRIGGER / HP_THRESHOLD / NUMBER_ADVANTAGE 는 CombatManager의 combat-time hook에서.
##
## encounters.md §2 통합 포인트 참조.


## board: BoardState — 셀에 EnemyUnitData가 들어있음
## rules: Array[EnemySynergyRule] — encounter.rules + global_enemy_rules 누적
##
## 반환: Dictionary { Vector2i(col, row) -> ComputedStats }
static func compute_pre_battle(board: BoardState, rules: Array[EnemySynergyRule]) -> Dictionary:
	var result: Dictionary = {}
	if board == null:
		return result

	# 1) pre-battle 룰만 추려서 작업 — combat-time 룰은 무시
	var pre_rules: Array[EnemySynergyRule] = []
	for r in rules:
		if r != null and r.is_pre_battle():
			pre_rules.append(r)

	# 2) GLOBAL_TRAIT용 진영별 카운트 미리 계산
	var faction_counts: Dictionary = {}  ## StringName -> int
	var boss_positions: Array[Vector2i] = []  ## (col, row)
	for entry in board.iter_placed():
		var u: EnemyUnitData = entry.unit
		if u == null:
			continue
		for tag in u.faction_tags:
			faction_counts[tag] = faction_counts.get(tag, 0) + 1
		if u.is_boss:
			boss_positions.append(Vector2i(entry.col, entry.row))

	# 3) 각 셀별 ComputedStats 생성 + 매칭 룰 누적
	for entry in board.iter_placed():
		var row: int = entry.row
		var col: int = entry.col
		var unit: EnemyUnitData = entry.unit
		if unit == null:
			continue

		var atk_bonus: float = 0.0
		var hp_bonus: float = 0.0
		var atkspd_bonus: float = 0.0
		var movespd_bonus: float = 0.0
		var range_bonus: float = 0.0
		# v2 additive 누적
		var def_b: float = 0.0
		var cc_b: float = 0.0
		var cm_b: float = 0.0
		var ap_b: float = 0.0
		var ls_b: float = 0.0
		var hr_b: float = 0.0
		var ac_b: float = 0.0
		var av_b: float = 0.0
		var applied: Array[StringName] = []

		for rule in pre_rules:
			var fires: bool = false
			match rule.effect_type:
				EnemySynergyRule.EffectType.GLOBAL_TRAIT:
					if rule.trigger_faction == &"":
						# 빈 진영은 전 유닛에 적용; 카운트는 전체 placed 수
						fires = board.count_placed() >= rule.trigger_count
					else:
						if not unit.has_faction(rule.trigger_faction):
							fires = false
						else:
							fires = int(faction_counts.get(rule.trigger_faction, 0)) >= rule.trigger_count
				EnemySynergyRule.EffectType.BOSS_AURA:
					# 자신이 보스 어른 인접에 있고, 해당 진영 조건 만족 시 발동
					if unit.is_boss:
						fires = false  # 보스 자신은 BOSS_AURA 안 받음
					elif rule.trigger_faction != &"" and not unit.has_faction(rule.trigger_faction):
						fires = false
					else:
						fires = _is_adjacent_to_any(Vector2i(col, row), boss_positions)
			if fires:
				atk_bonus += rule.attack_bonus_pct
				hp_bonus += rule.hp_bonus_pct
				atkspd_bonus += rule.attack_speed_bonus_pct
				movespd_bonus += rule.move_speed_bonus_pct
				range_bonus += rule.range_bonus_pct
				# v2 additive (모두 누적, ComputedStats에 한 번에 합산)
				def_b += rule.defense_bonus
				cc_b += rule.crit_chance_bonus
				cm_b += rule.crit_multiplier_bonus
				ap_b += rule.armor_penetration_bonus
				ls_b += rule.lifesteal_bonus
				hr_b += rule.hp_regen_bonus
				ac_b += rule.accuracy_bonus
				av_b += rule.attack_variance_pct_bonus
				applied.append(rule.id)

		var stats := ComputedStats.from_enemy(unit)
		stats.max_hp = unit.max_hp * (1.0 + hp_bonus)
		stats.attack = unit.attack * (1.0 + atk_bonus)
		stats.attack_speed = unit.attack_speed * (1.0 + atkspd_bonus)
		stats.attack_range = unit.attack_range * (1.0 + range_bonus)
		stats.move_speed = unit.move_speed * (1.0 + movespd_bonus)
		stats.defense = clampf(unit.defense + def_b, 0.0, 0.95)
		stats.crit_chance = clampf(unit.crit_chance + cc_b, 0.0, 1.0)
		stats.crit_multiplier = maxf(unit.crit_multiplier + cm_b, 1.0)
		stats.armor_penetration = clampf(unit.armor_penetration + ap_b, 0.0, 1.0)
		stats.lifesteal = clampf(unit.lifesteal + ls_b, 0.0, 1.0)
		stats.hp_regen = maxf(unit.hp_regen + hr_b, 0.0)
		stats.accuracy = clampf(unit.accuracy + ac_b, 0.0, 1.0)
		stats.attack_variance_pct = clampf(unit.attack_variance_pct + av_b, 0.0, 1.0)
		stats.applied_synergies = applied

		result[Vector2i(col, row)] = stats

	return result


static func _is_adjacent_to_any(pos: Vector2i, others: Array[Vector2i]) -> bool:
	for o in others:
		if o == pos:
			continue
		if abs(o.x - pos.x) <= 1 and abs(o.y - pos.y) <= 1:
			return true
	return false


## board의 ComputedStats를 1D 배열로 — CombatManager.start_battle에 넘기기 위함.
## board.iter_placed() 순서대로 정렬.
static func payload_from(board: BoardState, computed: Dictionary) -> Array[ComputedStats]:
	var out: Array[ComputedStats] = []
	for entry in board.iter_placed():
		var key := Vector2i(entry.col, entry.row)
		if computed.has(key):
			out.append(computed[key])
	return out
