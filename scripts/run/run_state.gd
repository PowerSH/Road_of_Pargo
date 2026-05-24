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

## Units the player owns (the "deck"). Subset of these get placed on the board
## each battle.
var owned_units: Array[UnitData] = []

## Synergy rules currently in effect. Events / relics can mutate this mid-run.
var active_rules: Array[SynergyRule] = []

## The current run's node map.
var nodes: Array[MapNode] = []
## Index into `nodes` of the player's current position. -1 == not entered yet.
var current_node_index: int = -1
## Indices of nodes whose kind has been revealed to the player.
## Default Fog of War (progression.md §3, option A): revealed on arrival.
## Boss node is always revealed (목적지로 기능).
var revealed_nodes: Array[int] = []


func add_unit(u: UnitData) -> void:
	owned_units.append(u)


func remove_unit(u: UnitData) -> void:
	owned_units.erase(u)


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
