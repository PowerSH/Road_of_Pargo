extends Control

## 거점 (마을 광장). 용병 고용 / 아이템 상점 / NPC 조우 / 맵 진입.
## 챕터 시작 위치 + 챕터 사이 통과 도시 역할 둘 다.

## 한 번에 제시되는 용병 수.
const OFFER_COUNT: int = 5
## 고용가 = cost * 단가.
const HIRE_PRICE_PER_COST: int = 25

var _hire_overlay: Control
var _gold_label: Label
var _offers_box: VBoxContainer
## 현재 제시된 용병 (UnitData) + 고용 여부.
var _offers: Array[UnitData] = []


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_city.jpg")
	_build_hire_overlay()


# ─────────────────────────────────────────────────────────────
# 용병 고용
# ─────────────────────────────────────────────────────────────

func _on_hire_pressed() -> void:
	if GameState.run == null:
		GameState.start_new_run()
	_roll_offers()
	_populate_offers()
	_update_gold()
	_hire_overlay.visible = true


func _hire_price(unit: UnitData) -> int:
	return max(HIRE_PRICE_PER_COST, unit.cost * HIRE_PRICE_PER_COST)


## 카탈로그에서 OFFER_COUNT명을 무작위로 뽑는다 (중복 가능 — 같은 종류 두 번 영입 허용).
func _roll_offers() -> void:
	_offers.clear()
	var catalog: Array[UnitData] = GameState.load_unit_catalog()
	if catalog.is_empty():
		return
	for i in OFFER_COUNT:
		_offers.append(catalog[GameState.rng.randi() % catalog.size()])


func _populate_offers() -> void:
	for child in _offers_box.get_children():
		child.queue_free()

	if _offers.is_empty():
		var empty := Label.new()
		empty.text = "고용 가능한 용병이 없다."
		_offers_box.add_child(empty)
		return

	for i in _offers.size():
		var unit: UnitData = _offers[i]
		var price: int = _hire_price(unit)

		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)

		# 이름 — 남는 공간을 채우고, 긴 이름은 잘라서 행 폭이 흔들리지 않게.
		var name_label := Label.new()
		name_label.text = unit.display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)

		# 가격 — 고정 폭, 우측 정렬.
		var price_label := Label.new()
		price_label.text = "%d G" % price
		price_label.custom_minimum_size = Vector2(70, 0)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(price_label)

		# 고용 버튼 — 텍스트 길이와 무관하게 항상 같은 크기.
		# clip_text=true + 고정 min size + 확장 안 함 → "고용"/"고용됨" 모두 동일 폭.
		var hire_btn := Button.new()
		hire_btn.text = "고용"
		hire_btn.custom_minimum_size = Vector2(96, 38)
		hire_btn.clip_text = true
		hire_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		hire_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hire_btn.disabled = GameState.run.gold < price
		hire_btn.pressed.connect(_on_hire_confirm.bind(i, hire_btn))
		row.add_child(hire_btn)

		_offers_box.add_child(row)


func _on_hire_confirm(index: int, btn: Button) -> void:
	if index < 0 or index >= _offers.size():
		return
	var unit: UnitData = _offers[index]
	var price: int = _hire_price(unit)
	if not GameState.run.spend_gold(price):
		return  # 골드 부족 (버튼이 이미 disabled여야 정상)

	GameState.run.add_unit_data(unit)  # 보관함으로 영입 (미배치)
	print("[Hub] 용병 고용: %s (-%d G, 잔액 %d)" % [
		unit.display_name, price, GameState.run.gold
	])

	# 이 슬롯 고용 완료 표시 + 골드 갱신 후 다른 슬롯 구매 가능 여부 재평가.
	btn.text = "고용됨"
	btn.disabled = true
	_update_gold()
	_refresh_offer_affordability()


## 골드 변동 후 각 고용 버튼의 활성 상태 재평가 (이미 고용된 건 건드리지 않음).
func _refresh_offer_affordability() -> void:
	for i in _offers_box.get_child_count():
		var row: Node = _offers_box.get_child(i)
		if row.get_child_count() < 3:
			continue
		var btn: Button = row.get_child(2) as Button
		if btn == null or btn.text == "고용됨":
			continue
		btn.disabled = GameState.run.gold < _hire_price(_offers[i])


func _update_gold() -> void:
	if _gold_label != null and GameState.run != null:
		_gold_label.text = "보유 골드: %d G" % GameState.run.gold


func _on_hire_overlay_close() -> void:
	_hire_overlay.visible = false


## 고용 오버레이 UI를 만들고 숨겨둔다. _on_hire_pressed에서 visible 토글.
func _build_hire_overlay() -> void:
	_hire_overlay = Control.new()
	_hire_overlay.name = "HireOverlay"
	_hire_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hire_overlay.visible = false
	add_child(_hire_overlay)

	# 뒤 배경 어둡게 + 입력 차단
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_hire_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hire_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 14)
	panel.add_child(vbox)

	# 헤더
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "용병 고용"
	title.add_theme_font_size_override(&"font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_gold_label = Label.new()
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_gold_label)
	vbox.add_child(header)

	# 용병 목록
	_offers_box = VBoxContainer.new()
	_offers_box.add_theme_constant_override(&"separation", 8)
	vbox.add_child(_offers_box)

	# 닫기
	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_on_hire_overlay_close)
	vbox.add_child(close_btn)


# ─────────────────────────────────────────────────────────────
# 기타 거점 메뉴 (placeholder)
# ─────────────────────────────────────────────────────────────

func _on_shop_pressed() -> void:
	print("[Hub] 아이템 상점 — 미구현")


func _on_npc_pressed() -> void:
	print("[Hub] NPC 조우 — 미구현")


func _on_to_map_pressed() -> void:
	if GameState.run == null:
		GameState.start_new_run()
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


func _on_to_menu_pressed() -> void:
	GameState.end_run(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
