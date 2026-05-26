extends Node

## Autoloaded singleton. Holds the active run + the current board between
## scene changes. UI scenes read/write through this — the actual systems
## (SynergyEngine, CombatManager) take their inputs as parameters so they
## stay testable without the autoload.

signal run_started
signal run_ended(victory: bool)
signal node_entered(index: int)
signal board_changed

var run: RunState
var board: BoardState
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func start_new_run() -> void:
	run = RunState.new()
	run.nodes = MapGenerator.generate(rng)
	run.reveal_initial()
	board = BoardState.new()
	run_started.emit()


func end_run(victory: bool) -> void:
	run_ended.emit(victory)
	run = null
	board = null


func enter_node(index: int) -> bool:
	if run == null:
		return false
	if not run.enter_node(index):
		return false
	node_entered.emit(index)
	return true


## Convenience: compute synergies for the current board with current run rules.
func compute_current_synergies() -> Dictionary:
	if board == null or run == null:
		return {}
	return SynergyEngine.compute(board, run.active_rules)


## Helper to push a battle: builds parallel arrays of ComputedStats + OwnedUnit
## for CombatManager.start_battle. Index i in both arrays refers to the same
## placed unit on the board.
##
## Returns {"stats": Array[ComputedStats], "owned": Array[OwnedUnit]}.
func build_player_payload() -> Dictionary:
	var stats: Array[ComputedStats] = []
	var owned_list: Array[OwnedUnit] = []
	if board == null:
		return {"stats": stats, "owned": owned_list}
	var computed: Dictionary = compute_current_synergies()
	for entry in board.iter_placed():
		var owned: OwnedUnit = entry.unit
		if owned == null:
			continue
		var key := Vector2i(entry.col, entry.row)
		if computed.has(key):
			stats.append(computed[key])
			owned_list.append(owned)
	return {"stats": stats, "owned": owned_list}
