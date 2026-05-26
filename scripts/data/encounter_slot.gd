class_name EncounterSlot
extends Resource

## EncounterTemplate의 한 칸. 고정 유닛이거나, 변동 풀에서 1마리 뽑는다.

@export_range(0, 2) var row: int = 0
@export_range(0, 4) var col: int = 0

## 항상 등장하는 유닛. 설정되어 있으면 variation_pool 무시.
@export var fixed_unit: EnemyUnitData

## fixed_unit이 null일 때 매 전투마다 무작위로 1개 선택.
## 최소 1개 이상 채워져 있어야 한다.
@export var variation_pool: Array[EnemyUnitData] = []

## true면 매 전투마다 일정 확률로 슬롯 자체가 비어있을 수 있음 (전투 규모 ±1 변동).
@export var optional: bool = false
@export_range(0.0, 1.0) var skip_chance: float = 0.0


func is_fixed() -> bool:
	return fixed_unit != null
