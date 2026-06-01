extends Control

## 휴식 화면 (여관/모닥불).
## cargo-and-mortality.md §5 — 쉼터에서 1유닛 풀 HP 회복 + 부상 → 전투가능.
## 이전 동작(RunState.health 회복)은 R4 합의에 의해 폐기됨 — 런 HP 시스템 없음.

const TARGETS_PER_REST: int = 1

var _healed_count: int = 0
var _unit_buttons: Dictionary = {}  ## OwnedUnit → Button


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_forest.jpg")
	# 기존 placeholder 버튼 숨김 — RunState.health 회복은 의미 없는 액션.
	_hide_legacy_buttons()
	_build_unit_list_ui()
	_refresh_unit_list()


func _hide_legacy_buttons() -> void:
	for nm in ["HealButton", "UpgradeButton"]:
		var b: Node = find_child(nm, true, false)
		if b is Button:
			b.visible = false


func _build_unit_list_ui() -> void:
	var stack: Node = find_child("Stack", true, false)
	if stack == null:
		return
	# Subtitle 갱신
	var sub: Node = stack.find_child("Subtitle", false, false)
	if sub is Label:
		sub.text = "회복할 유닛을 1명 선택하라."
	# 유닛 리스트 컨테이너 — Stack의 LeaveButton 위에 삽입
	var scroll := ScrollContainer.new()
	scroll.name = "UnitListScroll"
	scroll.custom_minimum_size = Vector2(420, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.name = "UnitList"
	vbox.add_theme_constant_override(&"separation", 6)
	scroll.add_child(vbox)
	stack.add_child(scroll)
	var leave_btn: Node = stack.find_child("LeaveButton", false, false)
	if leave_btn != null:
		stack.move_child(scroll, leave_btn.get_index())


func _refresh_unit_list() -> void:
	var vbox: Node = find_child("UnitList", true, false)
	if vbox == null:
		return
	for c in vbox.get_children():
		c.queue_free()
	_unit_buttons.clear()

	if GameState.run == null or GameState.run.owned_units.is_empty():
		var empty := Label.new()
		empty.text = "(영입된 유닛 없음)"
		empty.modulate = Color(1.0, 1.0, 1.0, 0.6)
		vbox.add_child(empty)
		return

	var done: bool = _healed_count >= TARGETS_PER_REST
	var header := Label.new()
	if done:
		header.text = "휴식 완료 — 더는 회복할 수 없다. (떠나기)"
	else:
		header.text = "회복 선택 (%d / %d)" % [_healed_count, TARGETS_PER_REST]
	header.add_theme_font_size_override(&"font_size", 14)
	vbox.add_child(header)

	for owned: OwnedUnit in GameState.run.owned_units:
		vbox.add_child(_build_unit_row(owned, done))


func _build_unit_row(owned: OwnedUnit, done: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override(&"font_size", 12)

	var name_str: String = owned.source.display_name if owned.source else "?"
	var max_hp: float = owned.source.max_hp if owned.source else 0.0
	var cur_hp: float = owned.get_starting_hp(max_hp)
	var badge: String = _status_badge(owned)

	var hp_text: String
	if owned.status == OwnedUnit.Status.DEAD:
		hp_text = "사망 — 도시에서 부활 필요"
	elif owned.status == OwnedUnit.Status.INJURED:
		hp_text = "부상 (%d 스테이지 남음)" % owned.injured_stages_left
	else:
		hp_text = "HP %.0f / %.0f" % [cur_hp, max_hp]
	label.text = "%s %s — %s" % [badge, name_str, hp_text]
	row.add_child(label)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(80, 36)
	btn.text = "회복"
	# 사망 유닛은 쉼터에서 회복 불가. 풀 HP 전투가능 유닛도 회복 불필요.
	var no_need: bool = owned.status == OwnedUnit.Status.READY \
			and (owned.current_hp < 0.0 or owned.current_hp >= max_hp)
	btn.disabled = done or owned.status == OwnedUnit.Status.DEAD or no_need
	btn.pressed.connect(_on_heal_unit_pressed.bind(owned))
	row.add_child(btn)
	_unit_buttons[owned] = btn
	return row


func _status_badge(owned: OwnedUnit) -> String:
	match owned.status:
		OwnedUnit.Status.INJURED:
			return "⚠"
		OwnedUnit.Status.DEAD:
			return "☠"
		_:
			return "✓"


func _on_heal_unit_pressed(owned: OwnedUnit) -> void:
	if _healed_count >= TARGETS_PER_REST:
		return
	if not owned.heal_full():
		# DEAD는 heal_full이 false 반환 — 쉼터에서 부활 불가.
		return
	_healed_count += 1
	var nm: String = owned.source.display_name if owned.source else "?"
	print("[Rest] 회복 — %s" % nm)
	_refresh_unit_list()


# --- 레거시 시그널 핸들러 (HealButton/UpgradeButton은 hidden이므로 호출 X) ---

func _on_heal_pressed() -> void:
	# 이전 동작(RunState.health 회복) 폐기. 노옵.
	pass


func _on_upgrade_pressed() -> void:
	print("[Rest] 카드 강화 — 미구현")


func _on_leave_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")
