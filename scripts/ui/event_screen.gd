extends Control

## 특수 이벤트 노드. 텍스트 + 2~3개 선택지. 각 선택지의 outcome은 단순 효과
## (골드 ±, HP ±, 부상자 발생, 아이템 획득 등) — Tier2_sheet.events_special 후속 확장.
##
## 현재는 콘텐츠 풀이 비어 있어 placeholder 이벤트 1개를 노출한다.

var _current_event: Dictionary = {}  ## {title, body, choices: Array[Dictionary]}


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_tervan.jpg")
	_pick_event()
	_apply_to_ui()


## 콘텐츠 풀(추후 Tier2_sheet에서 로드)에서 1개 선택.
## 풀이 비어있으면 placeholder.
func _pick_event() -> void:
	_current_event = _placeholder_event()


func _placeholder_event() -> Dictionary:
	return {
		"title": "낯선 행상",
		"body": "길가에서 마주친 행상이 빛바랜 보따리를 내민다. 무엇을 할 것인가?",
		"choices": [
			{"label": "5골드를 준다", "gold": -5, "log": "행상의 축복: 골드 5 손실, 별일 없음"},
			{"label": "보따리를 살펴본다", "gold": +20, "log": "행상의 보물: 골드 20 획득"},
			{"label": "그냥 지나간다", "log": "지나간다"},
		],
	}


func _apply_to_ui() -> void:
	var title_node: Node = find_child("Title", true, false)
	if title_node is Label and _current_event.has("title"):
		title_node.text = _current_event["title"]
	var body_node: Node = find_child("Subtitle", true, false)
	if body_node is Label and _current_event.has("body"):
		body_node.text = _current_event["body"]
	# 선택지 버튼 — ChoiceAButton / ChoiceBButton / ChoiceCButton 가 있다고 가정.
	var choices: Array = _current_event.get("choices", [])
	for i in 3:
		var name_: String = ["ChoiceAButton", "ChoiceBButton", "ChoiceCButton"][i]
		var btn: Node = find_child(name_, true, false)
		if not (btn is Button):
			continue
		if i < choices.size():
			(btn as Button).text = choices[i].get("label", "?")
			(btn as Button).visible = true
		else:
			(btn as Button).visible = false


## 선택지 i 처리. 결과 적용 후 맵으로 복귀.
func _resolve_choice(i: int) -> void:
	var choices: Array = _current_event.get("choices", [])
	if i < 0 or i >= choices.size():
		_leave()
		return
	var ch: Dictionary = choices[i]
	if ch.has("gold"):
		GameState.run.gold = maxi(GameState.run.gold + int(ch["gold"]), 0)
	# 향후: hp_delta / item_id / unit_id / injury 등 확장.
	if ch.has("log"):
		print("[Event] %s" % ch["log"])
	_leave()


func _leave() -> void:
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 시그널 핸들러 — .tscn의 연결 보존
func _on_choice_a_pressed() -> void:
	_resolve_choice(0)


func _on_choice_b_pressed() -> void:
	_resolve_choice(1)


func _on_choice_c_pressed() -> void:
	_resolve_choice(2)


func _on_leave_pressed() -> void:
	_leave()
