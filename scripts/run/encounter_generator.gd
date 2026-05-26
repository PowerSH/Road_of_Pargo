class_name EncounterGenerator
extends RefCounted

## EncounterTemplate → 실제 적군 BoardState 변환기.
## 슬롯의 variation_pool 추첨 + optional 슬롯 skip을 처리한다.
## encounters.md §5 참조.


## Generates an enemy BoardState from a template. RNG is passed in for
## determinism (단위 테스트·리플레이 시 같은 seed로 같은 결과).
##
## 반환 형식:
##   {
##     "board": BoardState,        # 적군 보드
##     "units": Array[EnemyUnitData]  # 슬롯에 채워진 유닛 리스트 (rules 적용 순회용)
##   }
static func generate(template: EncounterTemplate, rng: RandomNumberGenerator) -> Dictionary:
	var board := BoardState.new()
	var units: Array[EnemyUnitData] = []
	if template == null:
		return {"board": board, "units": units}

	for slot in template.slots:
		if slot.optional and rng.randf() < slot.skip_chance:
			continue
		var unit: EnemyUnitData = _pick_unit(slot, rng)
		if unit == null:
			continue
		if not board.in_bounds(slot.row, slot.col):
			push_warning("[EncounterGenerator] slot out of bounds (%d, %d) in '%s'" % [slot.row, slot.col, template.id])
			continue
		board.place_unit(slot.row, slot.col, unit)
		units.append(unit)
	return {"board": board, "units": units}


static func _pick_unit(slot: EncounterSlot, rng: RandomNumberGenerator) -> EnemyUnitData:
	if slot.is_fixed():
		return slot.fixed_unit
	if slot.variation_pool.is_empty():
		return null
	return slot.variation_pool[rng.randi() % slot.variation_pool.size()]


## 골드 보상 계산 헬퍼 — battle-flow.md §5 공식.
## CombatManager가 enemy_power를 모르므로 caller가 generator 시점에 계산해두는 게 자연스러움.
static func compute_gold_reward(enemy_units: Array[EnemyUnitData], is_boss: bool, is_draw: bool) -> int:
	var total_power: float = 0.0
	for u in enemy_units:
		if u != null:
			total_power += u.compute_power_score()
	var gold: float = total_power * 0.25
	if is_boss:
		gold *= 2.0
	if is_draw:
		gold *= 0.5
	return int(round(gold))


## 총 power. 인카운터 난이도 검증 / 디버그용.
static func compute_total_power(enemy_units: Array[EnemyUnitData]) -> float:
	var total: float = 0.0
	for u in enemy_units:
		if u != null:
			total += u.compute_power_score()
	return total
