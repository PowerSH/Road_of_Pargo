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

const UNITS_DIR: String = "res://resource/units/"
const SYNERGIES_DIR: String = "res://resource/synergies/"

var run: RunState
var board: BoardState
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func start_new_run() -> void:
	run = RunState.new()
	# 챕터 1 패턴으로 초기 맵 생성 (RunState.chapter는 1로 기본 설정됨).
	run.nodes = MapGenerator.generate(rng, RunState.get_chapter_pattern(run.chapter))
	run.reveal_initial()
	board = BoardState.new()
	# 디스크 카탈로그 일괄 영입 + 활성 시너지 룰 셋업.
	# battle_screen 진입 시점이 아니라 런 시작 시점에 자동으로 채움.
	_load_initial_units_from_disk()
	_load_active_synergies_from_disk()
	run_started.emit()


## resource/units/*.tres → run.owned_units 일괄 영입.
func _load_initial_units_from_disk() -> int:
	if run == null:
		return 0
	var dir: DirAccess = DirAccess.open(UNITS_DIR)
	if dir == null:
		return 0
	var count: int = 0
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res: Resource = load(UNITS_DIR + fname)
			if res is UnitData:
				run.add_unit_data(res)
				count += 1
		fname = dir.get_next()
	if count > 0:
		print("[GameState] loaded %d UnitData → owned_units" % count)
	return count


## resource/synergies/*.tres → run.active_rules.
func _load_active_synergies_from_disk() -> int:
	if run == null:
		return 0
	var dir: DirAccess = DirAccess.open(SYNERGIES_DIR)
	if dir == null:
		return 0
	var rules: Array[SynergyRule] = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res: Resource = load(SYNERGIES_DIR + fname)
			if res is SynergyRule:
				rules.append(res)
		fname = dir.get_next()
	run.active_rules = rules
	if not rules.is_empty():
		print("[GameState] loaded %d SynergyRule → active_rules" % rules.size())
	return rules.size()


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
