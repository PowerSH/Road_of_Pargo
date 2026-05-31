class_name CombatManager
extends Node2D

## Drives the auto-battle. Spawns CombatUnits for both sides at opposite ends
## of the arena, then ticks them every frame. Emits a BattleResult signal when
## one side is wiped out (or 120s cap reached).
##
## battle-flow.md §4 참조. Combat-time 시너지 룰(DEATH_TRIGGER, HP_THRESHOLD,
## NUMBER_ADVANTAGE)은 추후 hook으로 추가 — 현재는 코어 마이그레이션만.

signal battle_started
signal battle_ended(result: BattleResult)
signal unit_spawned(unit: CombatUnit)

## Arena layout. Player units spawn on the left, enemies on the right.
@export var arena_size: Vector2 = Vector2(1000, 400)
## Time cap (raised from 60 → 120 per battle-flow round 4); if neither side wipes by
## then both sides treat survivors as injured + half gold reward (caller computes gold).
@export var max_duration_sec: float = 120.0

## Caller가 start_battle 전에 설정. 챕터별 부상→사망 카운트다운 초기값.
## RunState.injury_threshold() 결과를 그대로 넘기면 됨.
@export var injury_threshold: int = 4

var _player_units: Array[CombatUnit] = []
var _enemy_units: Array[CombatUnit] = []
## _player_units[i] 의 원본 OwnedUnit (write-back 용). parallel array.
var _player_owned: Array[OwnedUnit] = []
var _running: bool = false
var _elapsed: float = 0.0


## 그리드 → 전장 좌표 매핑 상수.
## 전열(col 0)은 중앙에 가깝게, 후열(col 4)은 진영 끝으로.
const GRID_COL_STEP: float = 100.0
const GRID_ROW_STEP: float = 100.0
const GRID_FRONT_OFFSET: float = 60.0

## player_owned는 player_stats와 parallel — same index가 같은 유닛.
## player_grid / enemy_grid: BoardState의 Vector2i(row, col) 위치. 비어 있으면
## 기존 단순 세로 배치로 fallback (back-compat).
func start_battle(player_stats: Array[ComputedStats],
		player_owned: Array[OwnedUnit],
		enemy_stats: Array[ComputedStats],
		player_grid: Array[Vector2i] = [],
		enemy_grid: Array[Vector2i] = []) -> void:
	_clear_units()
	_elapsed = 0.0
	_spawn_player_side(player_stats, player_owned, player_grid)
	_spawn_enemy_side(enemy_stats, enemy_grid)
	_running = true
	battle_started.emit()


## Grid(row, col) → 아레나 좌표. is_player=true면 왼쪽 절반, 아니면 오른쪽 절반.
## col 0 = 전열(중앙 쪽), col 4 = 후열(진영 끝). row 0 = 위, row 2 = 아래.
func _grid_to_arena_pos(grid: Vector2i, is_player: bool) -> Vector2:
	var x_offset: float = GRID_FRONT_OFFSET + float(grid.y) * GRID_COL_STEP
	var x: float = -x_offset if is_player else x_offset
	var y: float = (float(grid.x) - 1.0) * GRID_ROW_STEP
	return Vector2(x, y)


func stop_battle() -> void:
	_running = false


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta

	for u in _player_units:
		u.tick(delta, _enemy_units, _player_units)
	for u in _enemy_units:
		u.tick(delta, _player_units, _enemy_units)

	var p_alive: bool = _any_alive(_player_units)
	var e_alive: bool = _any_alive(_enemy_units)

	if not p_alive and not e_alive:
		_finish(BattleResult.Outcome.DRAW)
	elif not e_alive:
		_finish(BattleResult.Outcome.PLAYER_WIN)
	elif not p_alive:
		_finish(BattleResult.Outcome.PLAYER_LOSS)
	elif _elapsed >= max_duration_sec:
		_finish(BattleResult.Outcome.DRAW)


func _spawn_player_side(stats_list: Array[ComputedStats],
		owned_list: Array[OwnedUnit],
		grid_list: Array[Vector2i]) -> void:
	if stats_list.is_empty():
		return
	var count: int = stats_list.size()
	for i in count:
		var u: CombatUnit = CombatUnit.new()
		add_child(u)
		var pos: Vector2 = _fallback_player_pos(i, count)
		if i < grid_list.size():
			pos = _grid_to_arena_pos(grid_list[i], true)
		var owned: OwnedUnit = owned_list[i] if i < owned_list.size() else null
		u.setup(stats_list[i], CombatUnit.Team.PLAYER, pos, owned)
		_player_units.append(u)
		_player_owned.append(owned)
		unit_spawned.emit(u)


func _spawn_enemy_side(stats_list: Array[ComputedStats],
		grid_list: Array[Vector2i]) -> void:
	if stats_list.is_empty():
		return
	var count: int = stats_list.size()
	for i in count:
		var u: CombatUnit = CombatUnit.new()
		add_child(u)
		var pos: Vector2 = _fallback_enemy_pos(i, count)
		if i < grid_list.size():
			pos = _grid_to_arena_pos(grid_list[i], false)
		u.setup(stats_list[i], CombatUnit.Team.ENEMY, pos)
		_enemy_units.append(u)
		unit_spawned.emit(u)


# grid 정보가 없을 때의 폴백 — 기존 세로 정렬 + 살짝 지그재그.
func _fallback_player_pos(i: int, count: int) -> Vector2:
	var spacing: float = arena_size.y / float(count + 1)
	var y: float = -arena_size.y * 0.5 + spacing * float(i + 1)
	var jitter: float = (i % 2) * 40.0
	return Vector2(-arena_size.x * 0.5 + jitter, y)


func _fallback_enemy_pos(i: int, count: int) -> Vector2:
	var spacing: float = arena_size.y / float(count + 1)
	var y: float = -arena_size.y * 0.5 + spacing * float(i + 1)
	var jitter: float = -(i % 2) * 40.0
	return Vector2(arena_size.x * 0.5 + jitter, y)


func _any_alive(units: Array[CombatUnit]) -> bool:
	for u in units:
		if u.is_alive():
			return true
	return false


func _clear_units() -> void:
	for u in _player_units:
		u.queue_free()
	for u in _enemy_units:
		u.queue_free()
	_player_units.clear()
	_enemy_units.clear()
	_player_owned.clear()


## 전투 종료: BattleResult 빌드 + OwnedUnit에 carry-over HP / 부상 마킹.
## 골드 보상은 caller가 결정 (적 power 정보를 CombatManager는 모름).
func _finish(outcome: BattleResult.Outcome) -> void:
	_running = false
	var result := BattleResult.new()
	result.outcome = outcome
	result.duration_sec = _elapsed
	# DRAW와 LOSS는 살아남은 유닛 포함 전부 부상 처리. WIN은 정상 carry-over.
	var injure_all: bool = outcome != BattleResult.Outcome.PLAYER_WIN
	for i in _player_units.size():
		var cu: CombatUnit = _player_units[i]
		var owned: OwnedUnit = _player_owned[i]
		if owned == null:
			continue
		if cu.is_alive() and not injure_all:
			owned.record_survived(cu.current_hp)
			result.survivor_hp[owned] = cu.current_hp
		else:
			owned.mark_injured(injury_threshold)
			result.newly_injured.append(owned)
	battle_ended.emit(result)
