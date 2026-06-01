class_name CombatManager
extends Node2D

## Drives the auto-battle. Spawns CombatUnits for both sides at opposite ends
## of the arena, then ticks them every frame. Emits a BattleResult signal when
## one side is wiped out (or 120s cap reached).
##
## battle-flow.md §4 참조. Combat-time 적 시너지 룰(DEATH_TRIGGER, HP_THRESHOLD,
## NUMBER_ADVANTAGE)은 enemy_combat_rules에 등록하면 자동 평가.

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

## Combat-time 적 시너지 룰 (DEATH_TRIGGER / HP_THRESHOLD / NUMBER_ADVANTAGE).
## caller가 start_battle 전에 채워 넣음. EnemySynergyRule.is_pre_battle()==false인 룰만 들어옴.
var _enemy_combat_rules: Array[EnemySynergyRule] = []

## DEATH_TRIGGER 룰 별 누적 stack 카운트 (caller-set 상한 기본 5).
const DEATH_TRIGGER_CAP: int = 5
var _death_trigger_stacks: Dictionary = {}  ## StringName rule_id -> int

## HP_THRESHOLD 룰 별 발동된 유닛 set — 1회만 발동.
var _hp_threshold_fired: Dictionary = {}  ## StringName rule_id -> Array[CombatUnit]

## NUMBER_ADVANTAGE 활성 상태 — toggle 가능.
var _number_advantage_active: Dictionary = {}  ## StringName rule_id -> bool


## 그리드 → 전장 좌표 매핑 상수.
## 전열(col 0)은 중앙에 가깝게, 후열(col 4)은 진영 끝으로.
const GRID_COL_STEP: float = 100.0
const GRID_ROW_STEP: float = 100.0
const GRID_FRONT_OFFSET: float = 60.0

## player_owned는 player_stats와 parallel — same index가 같은 유닛.
## player_grid / enemy_grid: BoardState의 Vector2i(row, col) 위치. 비어 있으면
## 기존 단순 세로 배치로 fallback (back-compat).
## combat_rules: combat-time 적 시너지 룰 — 비어 있어도 호환.
func start_battle(player_stats: Array[ComputedStats],
		player_owned: Array[OwnedUnit],
		enemy_stats: Array[ComputedStats],
		player_grid: Array[Vector2i] = [],
		enemy_grid: Array[Vector2i] = [],
		combat_rules: Array[EnemySynergyRule] = []) -> void:
	_clear_units()
	_elapsed = 0.0
	_enemy_combat_rules = combat_rules
	_death_trigger_stacks.clear()
	_hp_threshold_fired.clear()
	_number_advantage_active.clear()
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

	# NUMBER_ADVANTAGE 룰 매 틱 평가 (toggle 가능).
	_evaluate_number_advantage()

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


# ─────────────────────────────────────────────────────────────
# Combat-time enemy synergy hooks (B 라운드)
# ─────────────────────────────────────────────────────────────

## 적 유닛이 죽으면 DEATH_TRIGGER 룰을 생존 적에 누적 적용.
func _on_enemy_died(_unit: CombatUnit) -> void:
	for rule in _enemy_combat_rules:
		if rule.effect_type != EnemySynergyRule.EffectType.DEATH_TRIGGER:
			continue
		var current_stack: int = _death_trigger_stacks.get(rule.id, 0)
		if current_stack >= DEATH_TRIGGER_CAP:
			continue
		_death_trigger_stacks[rule.id] = current_stack + 1
		# 생존 적 중 진영 매칭되는 유닛에 보너스 1회 가산.
		for survivor in _enemy_units:
			if not survivor.is_alive():
				continue
			if not _enemy_matches_faction(survivor, rule.trigger_faction):
				continue
			_apply_bonus_to_unit(survivor, rule)


## 적 유닛이 데미지 받으면 HP_THRESHOLD 룰 체크. 임계 이하면 1회 자기 강화.
func _on_enemy_damaged(_amount: float, unit: CombatUnit) -> void:
	if not unit.is_alive():
		return
	for rule in _enemy_combat_rules:
		if rule.effect_type != EnemySynergyRule.EffectType.HP_THRESHOLD:
			continue
		# 진영 필터 (trigger_faction 비어 있으면 전 적 대상).
		if not _enemy_matches_faction(unit, rule.trigger_faction):
			continue
		# 이미 발동한 유닛은 스킵.
		var fired_list: Array = _hp_threshold_fired.get(rule.id, [])
		if fired_list.has(unit):
			continue
		if unit.hp_ratio() > rule.hp_threshold:
			continue
		fired_list.append(unit)
		_hp_threshold_fired[rule.id] = fired_list
		_apply_bonus_to_unit(unit, rule)


## NUMBER_ADVANTAGE: 적 생존 수 - 플레이어 생존 수 ≥ trigger_count 면 보너스 ON,
## 그 외면 OFF. toggle 시점만 적용 (중복 add/remove 방지).
func _evaluate_number_advantage() -> void:
	if _enemy_combat_rules.is_empty():
		return
	var p_alive: int = _count_alive(_player_units)
	var e_alive: int = _count_alive(_enemy_units)
	for rule in _enemy_combat_rules:
		if rule.effect_type != EnemySynergyRule.EffectType.NUMBER_ADVANTAGE:
			continue
		var should_active: bool = (e_alive - p_alive) >= rule.trigger_count
		var is_active: bool = _number_advantage_active.get(rule.id, false)
		if should_active and not is_active:
			_number_advantage_active[rule.id] = true
			_apply_bonus_to_all_matching_enemies(rule, +1.0)
		elif not should_active and is_active:
			_number_advantage_active[rule.id] = false
			_apply_bonus_to_all_matching_enemies(rule, -1.0)


func _apply_bonus_to_all_matching_enemies(rule: EnemySynergyRule, sign_: float) -> void:
	for survivor in _enemy_units:
		if not survivor.is_alive():
			continue
		if not _enemy_matches_faction(survivor, rule.trigger_faction):
			continue
		_apply_bonus_to_unit(survivor, rule, sign_)


func _apply_bonus_to_unit(unit: CombatUnit, rule: EnemySynergyRule, sign_: float = 1.0) -> void:
	unit.bonus_attack_pct += rule.attack_bonus_pct * sign_
	unit.bonus_attack_speed_pct += rule.attack_speed_bonus_pct * sign_
	unit.bonus_move_speed_pct += rule.move_speed_bonus_pct * sign_
	unit.bonus_range_pct += rule.range_bonus_pct * sign_


func _enemy_matches_faction(unit: CombatUnit, faction: StringName) -> bool:
	if faction == &"":
		return true
	var src: Resource = unit.stats.source if unit.stats != null else null
	if src is EnemyUnitData:
		return (src as EnemyUnitData).has_faction(faction)
	return false


func _count_alive(units: Array[CombatUnit]) -> int:
	var n: int = 0
	for u in units:
		if u.is_alive():
			n += 1
	return n


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
		# Combat-time hooks: 적 사망 시 DEATH_TRIGGER, 데미지 받을 시 HP_THRESHOLD.
		u.died.connect(_on_enemy_died)
		u.damaged.connect(_on_enemy_damaged.bind(u))
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
