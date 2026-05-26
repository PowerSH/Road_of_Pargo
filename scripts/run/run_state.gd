class_name RunState
extends RefCounted

## Persistent state for a single roguelite run. Lives inside GameState while a
## run is active. Save/load is intentionally not wired here — once the data
## model stabilizes, ResourceSaver.save(self) on a serializable Resource form
## will be enough.

const STARTING_HEALTH: int = 80
const STARTING_GOLD: int = 50

var health: int = STARTING_HEALTH
var max_health: int = STARTING_HEALTH
var gold: int = STARTING_GOLD

## Units the player owns (the "deck"). 같은 UnitData를 두 번 영입하면 OwnedUnit이 2개.
## 배치된 일부 + 보관함의 나머지로 분류되며 battle-flow.md §2 참조.
var owned_units: Array[OwnedUnit] = []

## Synergy rules currently in effect. Events / relics can mutate this mid-run.
var active_rules: Array[SynergyRule] = []

## Current chapter (1=마을 / 2=도시 / 3=국가). progression.md §1 참조.
## 부상 카운트다운 초기값과 적군 power target 계산에 사용.
var chapter: int = 1

## The current run's node map.
var nodes: Array[MapNode] = []
## Index into `nodes` of the player's current position. -1 == not entered yet.
var current_node_index: int = -1
## Indices of nodes whose kind has been revealed to the player.
## Default Fog of War (progression.md §3, option A): revealed on arrival.
## Boss node is always revealed (목적지로 기능).
var revealed_nodes: Array[int] = []


## 새 OwnedUnit을 만들어 영입. 같은 UnitData를 또 영입하면 OwnedUnit 인스턴스 별개로 생성.
func add_unit_data(data: UnitData) -> OwnedUnit:
	var owned := OwnedUnit.new()
	owned.source = data
	owned.acquired_chapter = chapter
	owned.acquired_stage = max(current_node_index, 0)
	owned_units.append(owned)
	return owned


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
