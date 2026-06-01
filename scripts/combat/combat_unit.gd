class_name CombatUnit
extends Node2D

## Runtime unit during battle. No grid — units roam freely toward the nearest
## enemy. Sprites can be attached as a child node later by the UI layer.

enum Team { PLAYER, ENEMY }
enum State { SEARCH, MOVE, ATTACK, DEAD }

signal died(unit: CombatUnit)
signal damaged(unit: CombatUnit, amount: float)
## 바라보는 방향이 바뀔 때 emit. UI 레이어가 스프라이트 flip_h 갱신에 사용.
signal facing_changed(face_left: bool)

## 유닛 몸체 반경 — 겹침 방지의 기준. 두 유닛은 중심 간 거리가 2*BODY_RADIUS
## 이상이 되도록 떨어진다 (같은 팀 분리 + 적 근접 정지 모두에 사용).
## 스프라이트 표시 크기는 이 지름(72px)보다 작아야 시각적으로 안 겹친다.
const BODY_RADIUS: float = 36.0
## 동맹 분리 — 같은 팀 유닛끼리 너무 가까우면 밀어냄.
const SEPARATION_RADIUS: float = 76.0
const SEPARATION_STRENGTH: float = 120.0
## 공격 거리의 이 비율까지만 접근. 단, 몸체 지름(2*BODY_RADIUS)보다 가깝겐 안 감.
const APPROACH_RATIO: float = 0.9
## defense의 절대 상한 — 무적 방지. 1.0 이상이면 데미지 음수 가능.
const DEFENSE_CAP: float = 0.95

@export var team: Team = Team.PLAYER

var stats: ComputedStats
var current_hp: float = 0.0
var state: State = State.SEARCH
var target: CombatUnit = null
var _attack_cooldown: float = 0.0

## Player 측에만 의미 있는 OwnedUnit 역참조. carry-over HP 시작값 + 전투 종료 시
## write-back에 사용. enemy 측은 null.
var owned: OwnedUnit = null

## 전투 중 누적되는 % 보너스 (combat-time 시너지 hook + ItemEffect의 SHIELD 외 효과로 부여).
## stats는 pre-battle 스냅샷이라 불변; effective_*() 메서드가 동적으로 합성한다.
## hp_bonus는 의도적으로 제외 — 전투 중 HP 부스트는 다른 메카닉(heal)으로.
var bonus_attack_pct: float = 0.0
var bonus_attack_speed_pct: float = 0.0
var bonus_move_speed_pct: float = 0.0
var bonus_range_pct: float = 0.0

## ItemEffect.SHIELD에서 부여되는 절대값 보호막. 데미지를 먼저 흡수.
var shield: float = 0.0

## 현재 바라보는 방향 (true=왼쪽). target 방향으로 갱신, 바뀔 때만 facing_changed emit.
var _face_left: bool = false


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


## attacker가 자신의 stats(attack, crit, armor_pen, variance, accuracy)로 계산한
## final_damage를 흡수한다. defense는 attacker쪽에서 이미 곱해진 값이라 여기선 적용 X.
## SHIELD → HP 순으로 차감, lifesteal 처리는 attacker가 별도로 호출.
func take_damage(amount: float) -> void:
	if not is_alive():
		return
	# SHIELD가 먼저 흡수.
	var remaining: float = amount
	if shield > 0.0:
		var absorbed: float = min(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
	if remaining > 0.0:
		current_hp -= remaining
	damaged.emit(self, amount)
	if current_hp <= 0.0:
		_die()


## hp_regen, lifesteal, 치료 아이템 등에서 호출. max_hp까지 회복, 사망 유닛은 무시.
func heal(amount: float) -> void:
	if not is_alive() or amount <= 0.0:
		return
	current_hp = minf(stats.max_hp, current_hp + amount)


func effective_attack() -> float:
	return stats.attack * (1.0 + bonus_attack_pct)


func effective_attack_speed() -> float:
	return stats.attack_speed * (1.0 + bonus_attack_speed_pct)


func effective_move_speed() -> float:
	return stats.move_speed * (1.0 + bonus_move_speed_pct)


func effective_range() -> float:
	return stats.attack_range * (1.0 + bonus_range_pct)


## ratio = current_hp / stats.max_hp. HP_THRESHOLD 평가용.
func hp_ratio() -> float:
	if stats == null or stats.max_hp <= 0.0:
		return 0.0
	return current_hp / stats.max_hp


func tick(delta: float, enemies: Array[CombatUnit], allies: Array[CombatUnit] = []) -> void:
	if not is_alive():
		return

	# hp_regen은 살아있는 동안 매 틱 적용.
	if stats.hp_regen > 0.0:
		heal(stats.hp_regen * delta)

	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	if target == null or not target.is_alive():
		target = _find_nearest(enemies)
		if target == null:
			state = State.SEARCH
			return

	var to_target: Vector2 = target.position - position
	var dist: float = to_target.length()

	# 바라보는 방향 — target 쪽으로. 바뀔 때만 신호.
	var want_left: bool = to_target.x < 0.0
	if want_left != _face_left:
		_face_left = want_left
		facing_changed.emit(_face_left)

	var eff_range: float = effective_range()
	var eff_atkspd: float = effective_attack_speed()
	var eff_mvspd: float = effective_move_speed()

	if dist <= eff_range:
		# 공격 상태 — 완전 정지. 이동도, 동맹 분리 밀침도 적용하지 않는다.
		# "멈춰서 공격" — 움직이면서 공격하지 않는다.
		state = State.ATTACK
		if _attack_cooldown <= 0.0:
			_perform_attack(target)
			_attack_cooldown = 1.0 / max(eff_atkspd, 0.001)
	else:
		state = State.MOVE
		var step: float = eff_mvspd * delta
		# 정지 거리: 사정거리의 APPROACH_RATIO. 단 몸체가 겹치지 않게 2*BODY_RADIUS 이상 유지.
		# (근접 사정거리가 몸체 지름보다 작으면 사정거리 끝에서 멈춤 — 그래야 공격은 됨)
		var min_clear: float = minf(2.0 * BODY_RADIUS, eff_range)
		var stop_dist: float = maxf(eff_range * APPROACH_RATIO, min_clear)
		var travel: float = max(dist - stop_dist, 0.0)
		var actual_step: float = min(step, travel)
		if dist > 0.0:
			position += to_target / dist * actual_step
		# 동맹 분리는 이동 중(MOVE)에만 — 같은 적을 향해 다가가는 동맹들이 한 점에 안 모이게.
		# 공격 중인 유닛은 밀리지 않으므로, 이동 중인 동맹이 알아서 비켜간다.
		_apply_separation(allies, delta)


## 한 번의 공격 데미지 산출 + 적용 + lifesteal.
## 1. 기본 데미지 = effective_attack × random[1-spread, 1+spread] (분산)
## 2. 크리: 확률로 multiplier 곱
## 3. defense 적용 (attacker의 armor_penetration으로 감산 완화)
## 4. take_damage 호출
## 5. lifesteal로 자기 회복
func _perform_attack(t: CombatUnit) -> void:
	var raw: float = effective_attack()
	# 분산
	var spread: float = stats.attack_variance_pct * (1.0 - stats.accuracy)
	if spread > 0.0:
		raw *= randf_range(1.0 - spread, 1.0 + spread)
	# 크리
	if stats.crit_chance > 0.0 and randf() < stats.crit_chance:
		raw *= stats.crit_multiplier
	# 방어 적용
	var def: float = clampf(t.stats.defense, 0.0, DEFENSE_CAP)
	var pen: float = clampf(stats.armor_penetration, 0.0, 1.0)
	var effective_def: float = clampf(def * (1.0 - pen), 0.0, DEFENSE_CAP)
	var final_dmg: float = maxf(raw * (1.0 - effective_def), 0.0)
	t.take_damage(final_dmg)
	# 흡혈은 SHIELD에 흡수된 데미지엔 적용 X — 실제 HP 깎인 양 기준이면 정확하지만
	# 산식 복잡해지니 일단 final_dmg 기준으로 단순화.
	if stats.lifesteal > 0.0 and final_dmg > 0.0:
		heal(final_dmg * stats.lifesteal)


func _apply_separation(allies: Array[CombatUnit], delta: float) -> void:
	if allies.is_empty():
		return
	var push: Vector2 = Vector2.ZERO
	for ally in allies:
		if ally == self or not ally.is_alive():
			continue
		var diff: Vector2 = position - ally.position
		var d: float = diff.length()
		if d > 0.001 and d < SEPARATION_RADIUS:
			push += diff / d * (SEPARATION_RADIUS - d) / SEPARATION_RADIUS
	if push.length_squared() > 0.0:
		position += push * SEPARATION_STRENGTH * delta


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
