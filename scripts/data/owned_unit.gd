class_name OwnedUnit
extends Resource

## 플레이어가 영입한 유닛의 런타임 인스턴스. UnitData를 source로 두고
## 그 위에 상태(부상/사망) + HP carry over + 부상 카운트다운을 보관한다.
## 같은 UnitData를 두 OwnedUnit이 참조할 수 있다 (같은 종류 두 명 영입).

enum Status {
	READY,
	INJURED,
	DEAD,
}

@export var source: UnitData
@export var status: Status = Status.READY

## 전투 사이에 carry over되는 현재 HP. -1이면 "아직 한 번도 전투에 안 나간 상태"로
## 해석하여 전투 시작 시 max_hp를 사용한다. 부상 시 0으로 고정.
@export var current_hp: float = -1.0

## INJURED 상태에서만 의미 있는 카운트다운. 매 스테이지 진입 시 1씩 감소,
## 0 도달 시 status = DEAD로 자동 전환. 챕터별 초기값은 cargo-and-mortality.md §5 참조.
@export var injured_stages_left: int = 0

@export_group("Metadata")
@export var acquired_chapter: int = 1
@export var acquired_stage: int = 0


## 전투 시작 시점에 사용할 HP. 아직 한 번도 안 싸웠으면 max_hp.
func get_starting_hp(computed_max_hp: float) -> float:
	if source == null:
		return 0.0
	if current_hp < 0.0:
		return computed_max_hp
	return min(current_hp, computed_max_hp)


## 전투 종료 시 살아남은 유닛에 대해 호출. carry over 저장.
func record_survived(final_hp: float) -> void:
	current_hp = max(final_hp, 0.0)


## 전투 중 HP 0 도달한 유닛에 호출. 부상 전환 + 카운트다운 시작.
func mark_injured(stages_until_death: int) -> void:
	status = Status.INJURED
	current_hp = 0.0
	injured_stages_left = stages_until_death


## 부상 카운트다운 진행. 0 도달 시 사망 전환. 매 스테이지 진입 후 호출.
func tick_injury_countdown() -> void:
	if status != Status.INJURED:
		return
	injured_stages_left -= 1
	if injured_stages_left <= 0:
		status = Status.DEAD


## 사망 마킹. 부활 액션이나 자동 카운트다운 만료 시 호출.
func mark_dead() -> void:
	status = Status.DEAD


## 쉼터/의무실/치료 아이템에서 호출. HP 풀 회복 + 부상 해제.
## DEAD는 별도 부활 액션이 필요 — 이 함수로는 회복 안 됨.
func heal_full() -> bool:
	if status == Status.DEAD:
		return false
	if source != null:
		current_hp = source.max_hp
	if status == Status.INJURED:
		status = Status.READY
		injured_stages_left = 0
	return true


## 도시 신전 부활. 호출자가 비용 검증한 뒤 호출.
func revive() -> void:
	if source != null:
		current_hp = source.max_hp
	status = Status.READY
	injured_stages_left = 0


func is_deployable() -> bool:
	return status == Status.READY
