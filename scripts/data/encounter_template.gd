class_name EncounterTemplate
extends Resource

## 적군 라인업 청사진. EncounterGenerator(TBD)가 이 템플릿을 받아
## 실제 전투용 적 배치를 만들어낸다. ±20% 변동은 슬롯의 variation_pool과
## optional 조합으로 표현된다 (스탯 변동은 별도 — 추후 결정).

@export var id: StringName
@export var display_name: String

@export_group("Difficulty")
## 수동 오버라이드. -1이면 슬롯들의 compute_power_score() 합으로 자동 산정.
## 챕터·노드 종류별 target power를 맞추는지 검증할 때 사용.
@export var power_target_override: float = -1.0

@export_group("Lineup")
@export var slots: Array[EncounterSlot] = []

@export_group("Enemy-side Rules")
## 이 인카운터에만 적용되는 적 시너지 룰들. 챕터 전역 룰셋 위에 누적된다.
@export var rules: Array[EnemySynergyRule] = []


## 자동 산정 power. fixed/variation 모두 평균 잡아 계산할 수도 있지만
## 일단 단순화: fixed는 그대로, variation_pool은 풀 평균으로.
func compute_total_power() -> float:
	if power_target_override >= 0.0:
		return power_target_override
	var total: float = 0.0
	for slot in slots:
		if slot.fixed_unit != null:
			total += slot.fixed_unit.compute_power_score()
		elif not slot.variation_pool.is_empty():
			var sum: float = 0.0
			for u in slot.variation_pool:
				sum += u.compute_power_score()
			total += sum / float(slot.variation_pool.size())
	return total


func count_boss_slots() -> int:
	var n: int = 0
	for slot in slots:
		if slot.fixed_unit != null and slot.fixed_unit.is_boss:
			n += 1
	return n
