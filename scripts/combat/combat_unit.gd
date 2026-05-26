class_name CombatUnit
extends Node2D

## Runtime unit during battle. No grid — units roam freely toward the nearest
## enemy. Sprites can be attached as a child node later by the UI layer.

enum Team { PLAYER, ENEMY }
enum State { SEARCH, MOVE, ATTACK, DEAD }

signal died(unit: CombatUnit)
signal damaged(unit: CombatUnit, amount: float)

@export var team: Team = Team.PLAYER

var stats: ComputedStats
var current_hp: float = 0.0
var state: State = State.SEARCH
var target: CombatUnit = null
var _attack_cooldown: float = 0.0

## Player 측에만 의미 있는 OwnedUnit 역참조. carry-over HP 시작값 + 전투 종료 시
## write-back에 사용. enemy 측은 null.
var owned: OwnedUnit = null


func setup(stats_in: ComputedStats, team_in: Team, spawn_pos: Vector2, source_owned: OwnedUnit = null) -> void:
	stats = stats_in
	team = team_in
	owned = source_owned
	# Player 측은 OwnedUnit의 carry-over HP에서 시작. enemy 측은 풀 HP.
	if owned != null:
		current_hp = owned.get_starting_hp(stats.max_hp)
	else:
		current_hp = stats.max_hp
	state = State.SEARCH
	position = spawn_pos


func is_alive() -> bool:
	return state != State.DEAD and current_hp > 0.0


func take_damage(amount: float) -> void:
	if not is_alive():
		return
	current_hp -= amount
	damaged.emit(self, amount)
	if current_hp <= 0.0:
		_die()


func tick(delta: float, enemies: Array[CombatUnit]) -> void:
	if not is_alive():
		return
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	if target == null or not target.is_alive():
		target = _find_nearest(enemies)
		if target == null:
			state = State.SEARCH
			return

	var to_target: Vector2 = target.position - position
	var dist: float = to_target.length()

	if dist <= stats.attack_range:
		state = State.ATTACK
		if _attack_cooldown <= 0.0:
			target.take_damage(stats.attack)
			_attack_cooldown = 1.0 / max(stats.attack_speed, 0.001)
	else:
		state = State.MOVE
		var step: float = stats.move_speed * delta
		if step >= dist:
			position = target.position
		else:
			position += to_target / dist * step


func _find_nearest(enemies: Array[CombatUnit]) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist: float = INF
	for e in enemies:
		if not e.is_alive():
			continue
		var d: float = position.distance_squared_to(e.position)
		if d < best_dist:
			best_dist = d
			best = e
	return best


func _die() -> void:
	state = State.DEAD
	died.emit(self)
