class_name RunState
extends Resource

## Persistent state for a single roguelite run. Lives inside GameState while a
## run is active. Resource로 전환 — `ResourceSaver.save(run, "user://run.tres")`로
## 저장 가능 (Round 6).

const STARTING_HEALTH: int = 80
const STARTING_GOLD: int = 50

## RunState.health / max_health는 R4 합의로 폐기됨 (런 HP 시스템 없음). 호환을 위해 보관만.
@export var health: int = STARTING_HEALTH
@export var max_health: int = STARTING_HEALTH
@export var gold: int = STARTING_GOLD

## Units the player owns (the "deck"). 같은 UnitData를 두 번 영입하면 OwnedUnit이 2개.
## 배치된 일부 + 보관함의 나머지로 분류되며 battle-flow.md §2 참조.
@export var owned_units: Array[OwnedUnit] = []

## Synergy rules currently in effect. Events / relics can mutate this mid-run.
@export var active_rules: Array[SynergyRule] = []

## 상단의 적재함. cargo-and-mortality.md §1 — 초기 4×3, 도시에서 확장 구매 가능.
@export var cargo: CargoState = CargoState.new()

## Current chapter (1=마을 / 2=도시 / 3=국가). progression.md §1 참조.
## 부상 카운트다운 초기값과 적군 power target 계산에 사용.
@export var chapter: int = 1

## The current run's node map.
@export var nodes: Array[MapNode] = []
## Index into `nodes` of the player's current position. -1 == not entered yet.
@export var current_node_index: int = -1
## Indices of nodes whose kind has been revealed to the player.
## Default Fog of War (progression.md §3, option A): revealed on arrival.
## Boss node is always revealed (목적지로 기능).
@export var revealed_nodes: Array[int] = []

## 5×3 편성 보드. save 시점에 GameState.board를 여기에 스냅샷 → 같은 SubResource로 직렬화.
## 로드 시 GameState가 다시 GameState.board 변수에 꽂아 넣음.
@export var board: BoardState = BoardState.new()

## 진행 중인 퀘스트들. 한 role(길드장/조합장/상인/주민)당 최대 1개.
@export var active_quests: Array[Quest] = []
## 완료해서 보상 수령된 퀘스트 id 모음 (재시도 방지·통계).
@export var completed_quest_ids: Array[StringName] = []
## 트래킹용 누적 카운터.
@export var battles_won_total: int = 0
@export var units_hired_total: int = 0


## 새 OwnedUnit을 만들어 영입. 같은 UnitData를 또 영입하면 OwnedUnit 인스턴스 별개로 생성.
func add_unit_data(data: UnitData) -> OwnedUnit:
	var owned := OwnedUnit.new()
	owned.source = data
	owned.acquired_chapter = chapter
	owned.acquired_stage = max(current_node_index, 0)
	owned_units.append(owned)
	units_hired_total += 1
	QuestTracker.on_unit_hired(self)
	return owned


## 전투 종료(WIN) 시 호출. 카운터 증가 + 퀘스트 진행도 누적.
func note_battle_won(was_boss: bool) -> void:
	battles_won_total += 1
	QuestTracker.on_battle_won(self, was_boss)


## 특정 role의 active quest 1개 반환. 없으면 null.
func active_quest_from_role(role: String) -> Quest:
	for q in active_quests:
		if q.giver_role == role:
			return q
	return null


func has_active_quest_from(role: String) -> bool:
	return active_quest_from_role(role) != null


## 이미 만들어진 OwnedUnit을 추가 (예: 특수 이벤트로 NPC 합류).
func add_owned_unit(owned: OwnedUnit) -> void:
	owned_units.append(owned)


func remove_unit(owned: OwnedUnit) -> void:
	owned_units.erase(owned)


## 부상→사망 카운트다운 초기값. cargo-and-mortality.md §5.
func injury_threshold() -> int:
	match chapter:
		1: return 4
		2: return 3
		3: return 2
		_: return 4


## 매 스테이지 진입 후 호출 — 부상 유닛의 카운트다운 진행.
func tick_injury_countdowns() -> void:
	for u in owned_units:
		u.tick_injury_countdown()


## 챕터 보스 처치 후 호출. 마지막 챕터(3)였으면 run clear (false 반환).
## 그 외엔 chapter 증가 + 새 맵 + 노드 초기화 + boss 공개. true 반환.
const MAX_CHAPTER: int = 3

## 챕터별 lanes_per_depth 패턴. progression.md §5 — 후반일수록 길고 갈래 多.
## MapGenerator가 첫/마지막 lane을 1로 강제하므로 단일 시작·보스 보장.
const CHAPTER_PATTERNS: Dictionary = {
	1: [1, 2, 1, 3, 2, 1],
	2: [1, 2, 3, 2, 3, 2, 1],
	3: [1, 2, 3, 3, 2, 3, 2, 1],
}


static func get_chapter_pattern(c: int) -> Array[int]:
	var raw: Variant = CHAPTER_PATTERNS.get(c, CHAPTER_PATTERNS[1])
	var typed: Array[int] = []
	for v in raw:
		typed.append(int(v))
	return typed


func advance_chapter(rng: RandomNumberGenerator) -> bool:
	if chapter >= MAX_CHAPTER:
		return false
	chapter += 1
	nodes = MapGenerator.generate(rng, get_chapter_pattern(chapter))
	current_node_index = -1
	revealed_nodes.clear()
	# reveal_initial은 GameState에서 별도 호출. 여기서는 노드만 갈아치움.
	return true


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	return true


func take_damage(amount: int) -> bool:
	health = max(0, health - amount)
	return health <= 0


func heal(amount: int) -> void:
	health = min(max_health, health + amount)


func is_dead() -> bool:
	return health <= 0


func reachable_from_current() -> Array[int]:
	if current_node_index < 0:
		var out: Array[int] = []
		for i in nodes.size():
			if nodes[i].depth == 0:
				out.append(i)
		return out
	return nodes[current_node_index].next_indices.duplicate()


func enter_node(index: int) -> bool:
	if index < 0 or index >= nodes.size():
		return false
	if not reachable_from_current().has(index):
		return false
	current_node_index = index
	if not revealed_nodes.has(index):
		revealed_nodes.append(index)
	return true


func is_revealed(index: int) -> bool:
	return revealed_nodes.has(index)


## Called after `nodes` is populated. Reveals the boss as a known destination.
func reveal_initial() -> void:
	for i in nodes.size():
		if nodes[i].kind == MapNode.Kind.BOSS and not revealed_nodes.has(i):
			revealed_nodes.append(i)
