class_name BattleResult
extends RefCounted

## 한 전투의 결과 패키지. CombatManager가 battle_ended 시그널에 함께 emit.
## RESULT_SCREEN UI가 이 객체를 받아 화면 구성.

enum Outcome {
	PLAYER_WIN,
	PLAYER_LOSS,   ## 게임 오버
	DRAW,          ## 120초 캡 — 양쪽 부상, 보상 절반
}

var outcome: Outcome = Outcome.PLAYER_WIN

## 골드 보상. 공식: round(total_enemy_power * 0.25), 보스는 ×2, DRAW는 ×0.5.
var gold_reward: int = 0

## 이번 전투에서 부상(HP 0 도달)한 플레이어 OwnedUnit들.
var newly_injured: Array[OwnedUnit] = []

## 이번 전투에서 사망 전환된 OwnedUnit들 (부상 카운트다운 만료가 이번 스테이지에서 일어난 경우).
var died_this_battle: Array[OwnedUnit] = []

## 살아남은 유닛 → 전투 종료 시점 HP. RESULT_SCREEN 이후 OwnedUnit.current_hp에 반영.
var survivor_hp: Dictionary = {}  ## OwnedUnit → float

## 디버그/UI용 통계.
var duration_sec: float = 0.0
var enemy_power_total: float = 0.0
var encounter_id: StringName = &""


static func make_win(gold: int, survivors: Dictionary, injured: Array[OwnedUnit], power: float, dur: float, enc_id: StringName) -> BattleResult:
	var r := BattleResult.new()
	r.outcome = Outcome.PLAYER_WIN
	r.gold_reward = gold
	r.survivor_hp = survivors
	r.newly_injured = injured
	r.enemy_power_total = power
	r.duration_sec = dur
	r.encounter_id = enc_id
	return r


static func make_loss(power: float, dur: float, enc_id: StringName) -> BattleResult:
	var r := BattleResult.new()
	r.outcome = Outcome.PLAYER_LOSS
	r.enemy_power_total = power
	r.duration_sec = dur
	r.encounter_id = enc_id
	return r


static func make_draw(half_gold: int, injured: Array[OwnedUnit], power: float, dur: float, enc_id: StringName) -> BattleResult:
	var r := BattleResult.new()
	r.outcome = Outcome.DRAW
	r.gold_reward = half_gold
	r.newly_injured = injured
	r.enemy_power_total = power
	r.duration_sec = dur
	r.encounter_id = enc_id
	return r
