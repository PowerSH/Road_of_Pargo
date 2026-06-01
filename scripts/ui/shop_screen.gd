extends Control

## 상점 노드. 골드로 CargoItem 매입. 챕터 사이 거점 상점과 동일 로직(CityActions) 사용.
## CargoItem .tres가 디스크에 등장하면 자동으로 매대에 노출됨 (현재 비어있으면 "재고 없음").

const ITEMS_DIR: String = "res://resource/items/"  ## CargoItem .tres 풀
const STOCK_SIZE: int = 4  ## 한 번에 매대에 노출할 아이템 수

var _stock: Array[CargoItem] = []
var _row_buttons: Dictionary = {}  ## CargoItem → Button


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_mercenary.jpg")
	_hide_legacy_buttons()
	_build_ui()
	_refresh_stock()
	_refresh_rows()


func _hide_legacy_buttons() -> void:
	for nm in ["BuyItemButton", "BuyUnitButton"]:
		var b: Node = find_child(nm, true, false)
		if b is Button:
			b.visible = false


func _build_ui() -> void:
	var stack: Node = find_child("Stack", true, false)
	if stack == null:
		return
	# 헤더 갱신 (Subtitle이 있으면 골드 표시)
	var sub: Node = stack.find_child("Subtitle", false, false)
	if sub is Label:
		_update_subtitle(sub)
	# 매대 컨테이너 — Leave 위
	var scroll := ScrollContainer.new()
	scroll.name = "StockScroll"
	scroll.custom_minimum_size = Vector2(460, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.name = "StockList"
	vbox.add_theme_constant_override(&"separation", 6)
	scroll.add_child(vbox)
	stack.add_child(scroll)
	var leave: Node = stack.find_child("LeaveButton", false, false)
	if leave != null:
		stack.move_child(scroll, leave.get_index())


## 챕터 tier 필터로 풀에서 STOCK_SIZE개 무작위 선택.
func _refresh_stock() -> void:
	_stock.clear()
	var pool: Array[CargoItem] = _load_pool()
	if pool.is_empty():
		return
	# 챕터 tier 이하의 아이템만
	var filtered: Array[CargoItem] = []
	for item in pool:
		if item.chapter_tier == 0 or item.chapter_tier <= GameState.run.chapter:
			filtered.append(item)
	if filtered.is_empty():
		return
	# 셔플 후 앞 N개
	filtered.shuffle()
	var n: int = min(STOCK_SIZE, filtered.size())
	for i in n:
		_stock.append(filtered[i])


func _load_pool() -> Array[CargoItem]:
	var out: Array[CargoItem] = []
	var dir: DirAccess = DirAccess.open(ITEMS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res: Resource = load(ITEMS_DIR + fname)
			if res is CargoItem:
				out.append(res)
		fname = dir.get_next()
	return out


func _refresh_rows() -> void:
	var vbox: Node = find_child("StockList", true, false)
	if vbox == null:
		return
	for c in vbox.get_children():
		c.queue_free()
	_row_buttons.clear()

	if _stock.is_empty():
		var empty := Label.new()
		empty.text = "(재고 없음 — 아이템 카탈로그가 비어있다)"
		empty.modulate = Color(1.0, 1.0, 1.0, 0.6)
		vbox.add_child(empty)
		return

	for item in _stock:
		vbox.add_child(_build_row(item))
	# subtitle 골드 갱신
	var sub: Node = find_child("Subtitle", true, false)
	if sub is Label:
		_update_subtitle(sub)


func _build_row(item: CargoItem) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override(&"font_size", 12)
	var shape_desc: String = "%d셀" % item.shape_cells.size()
	label.text = "%s — %s (%d g)" % [item.display_name, shape_desc, CityActions.buy_price(GameState.run, item)]
	row.add_child(label)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(80, 36)
	btn.text = "구매"
	var price: int = CityActions.buy_price(GameState.run, item)
	# 골드 부족 또는 카고 공간 부족 시 disable
	var space_ok: bool = not GameState.run.cargo.find_slot_for(item).is_empty()
	btn.disabled = GameState.run.gold < price or not space_ok
	if not space_ok:
		btn.tooltip_text = "카고 공간 부족"
	btn.pressed.connect(_on_buy_pressed.bind(item))
	row.add_child(btn)
	_row_buttons[item] = btn
	return row


func _on_buy_pressed(item: CargoItem) -> void:
	if not CityActions.buy(GameState.run, item):
		print("[Shop] 구매 실패 — %s" % item.display_name)
		return
	# 매대에서 제거 (한 번 산 건 다시 못 사도록)
	_stock.erase(item)
	_refresh_rows()


func _update_subtitle(sub: Label) -> void:
	sub.text = "Gold: %d   Cargo 빈 셀: %d" % [
		GameState.run.gold,
		GameState.run.cargo.empty_cells_count(),
	]


# 레거시 시그널 — 버튼 hidden이므로 호출 X
func _on_buy_item_pressed() -> void:
	pass


func _on_buy_unit_pressed() -> void:
	pass


func _on_leave_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")
