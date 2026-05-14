class_name CombatManager
extends Node2D

## Drives the auto-battle. Spawns CombatUnits for both sides at opposite ends
## of the arena, then ticks them every frame. Emits a result signal when one
## side is wiped out.
##
## The UI layer attaches this node into a scene; sprite/animation children
## can be added to CombatUnit instances after spawn via spawn signals.

enum Result { PLAYER_WIN, ENEMY_WIN, DRAW }

signal battle_started
signal battle_ended(result: Result)
signal unit_spawned(unit: CombatUnit)

## Arena layout. Player units spawn on the left, enemies on the right.
@export var arena_size: Vector2 = Vector2(1000, 400)
## Time cap; if neither side wipes by then the battle is a draw.
@export var max_duration_sec: float = 60.0

var _player_units: Array[CombatUnit] = []
var _enemy_units: Array[CombatUnit] = []
var _running: bool = false
var _elapsed: float = 0.0


func start_battle(player_stats: Array[ComputedStats], enemy_stats: Array[ComputedStats]) -> void:
	_clear_units()
	_elapsed = 0.0
	_spawn_side(player_stats, CombatUnit.Team.PLAYER)
	_spawn_side(enemy_stats, CombatUnit.Team.ENEMY)
	_running = true
	battle_started.emit()


func stop_battle() -> void:
	_running = false


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta

	for u in _player_units:
		u.tick(delta, _enemy_units)
	for u in _enemy_units:
		u.tick(delta, _player_units)

	var p_alive: bool = _any_alive(_player_units)
	var e_alive: bool = _any_alive(_enemy_units)

	if not p_alive and not e_alive:
		_finish(Result.DRAW)
	elif not e_alive:
		_finish(Result.PLAYER_WIN)
	elif not p_alive:
		_finish(Result.ENEMY_WIN)
	elif _elapsed >= max_duration_sec:
		_finish(Result.DRAW)


func _spawn_side(stats_list: Array[ComputedStats], team: CombatUnit.Team) -> void:
	if stats_list.is_empty():
		return
	var is_player: bool = team == CombatUnit.Team.PLAYER
	var x_pos: float = -arena_size.x * 0.5 if is_player else arena_size.x * 0.5
	var count: int = stats_list.size()
	var spacing: float = arena_size.y / float(count + 1)

	for i in count:
		var u: CombatUnit = CombatUnit.new()
		add_child(u)
		var y: float = -arena_size.y * 0.5 + spacing * float(i + 1)
		# Slight x jitter so spawn doesn't collapse into a single line.
		var jitter: float = (i % 2) * 40.0 * (1.0 if is_player else -1.0)
		u.setup(stats_list[i], team, Vector2(x_pos + jitter, y))
		if is_player:
			_player_units.append(u)
		else:
			_enemy_units.append(u)
		unit_spawned.emit(u)


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


func _finish(r: Result) -> void:
	_running = false
	battle_ended.emit(r)
