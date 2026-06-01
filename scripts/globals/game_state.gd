extends Node

## Autoloaded singleton. Holds the active run + the current board between
## scene changes. UI scenes read/write through this — the actual systems
## (SynergyEngine, CombatManager) take their inputs as parameters so they
## stay testable without the autoload.

signal run_started
signal run_ended(victory: bool)
signal node_entered(index: int)
signal board_changed
signal chapter_advanced(new_chapter: int)
signal run_cleared

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
	# 스테이지 진입 = 부상 카운트다운 1 tick. 누적 시 사망 전환.
	run.tick_injury_countdowns()
	node_entered.emit(index)
	return true


## 챕터 보스 처치 후 호출. 마지막 챕터(MAX_CHAPTER)면 run clear → end_run(true).
## 그 외엔 다음 챕터 맵으로 갱신 + chapter_advanced 시그널.
func advance_chapter() -> void:
	if run == null:
		return
	var advanced: bool = run.advance_chapter(rng)
	if not advanced:
		# 최종 챕터까지 클리어 — 게임 클리어
		run_cleared.emit()
		end_run(true)
		return
	run.reveal_initial()
	chapter_advanced.emit(run.chapter)


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
