class_name Quest
extends Resource

## NPC가 발주하는 퀘스트.
## 수락 시 RunState.active_quests에 추가, 게임 진행 중 자동 progress 누적,
## 완료 후 NPC를 다시 찾아가 보상 수령.
##
## 한 role(길드장/조합장/상인/주민)당 1개의 active quest만 허용 — 과도한 누적 방지.

enum Kind {
	WIN_BATTLES,    ## 전투 N승
	HIRE_UNITS,     ## 용병 N명 영입
	DEFEAT_BOSS,    ## 챕터 보스 처치
}

@export var id: StringName
## 발주자 역할 — "길드장" / "조합장" / "상인" / "주민". 같은 role의 NPC면 누구든 보상 지급.
@export var giver_role: String
## 발주 시점의 NPC 이름. UI 표시용 — 이름은 무작위라 매번 다를 수 있음.
@export var giver_name: String
## 한 줄 설명 (퀘스트 카드 헤더).
@export var description: String
## 상세 본문 (NPC 대사 풍).
@export_multiline var detail: String

@export var kind: Kind = Kind.WIN_BATTLES
## 달성 목표값 — 진행도가 이 값에 도달하면 완료.
@export var target_value: int = 1
## 보상 골드.
@export var reward_gold: int = 50
## 보상 표시 텍스트 (UI 라벨용).
@export var reward_text: String = ""

# ── Runtime ───────────────────────────────────────────────────
@export var progress: int = 0
@export var accepted_at_chapter: int = 1
@export var accepted_at_stage: int = 0


func is_complete() -> bool:
	return progress >= target_value


func progress_text() -> String:
	return "%d / %d" % [progress, target_value]


func kind_label() -> String:
	match kind:
		Kind.WIN_BATTLES:
			return "전투 승리"
		Kind.HIRE_UNITS:
			return "용병 영입"
		Kind.DEFEAT_BOSS:
			return "보스 처치"
	return "?"


## 디버그/툴팁용 한 줄 요약.
func summary() -> String:
	return "[%s] %s (%s)" % [kind_label(), description, progress_text()]
