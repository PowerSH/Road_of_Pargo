extends Control

## 거점 (마을 광장). 용병 고용 / 아이템 상점 / NPC 조우 / 맵 진입.
## 챕터 시작 위치 + 챕터 사이 통과 도시 역할 둘 다.
##
## 4개 메뉴 = 4개 오버레이 (Hire / Shop / NpcList / NpcMeet). 메인 hub UI는 .tscn,
## 오버레이는 _ready에서 프로그래매틱 생성 후 visible 토글.

# ── 용병 고용 ─────────────────────────────────────────────────
const OFFER_COUNT: int = 5
const HIRE_PRICE_PER_COST: int = 25

# ── 아이템 상점 ───────────────────────────────────────────────
const ITEMS_DIR: String = "res://resource/items/"
const SHOP_ROWS: int = 2
const SHOP_COLS: int = 4
const PLAYER_ROWS: int = 4
const PLAYER_COLS: int = 4
const SLOT_SIZE: Vector2 = Vector2(90, 52)

# ── NPC ───────────────────────────────────────────────────────
const FIXED_NPCS: Array = [
	{"role": "길드장", "name": "그리젤다"},
	{"role": "조합장", "name": "발렌틴"},
]
const MERCHANT_NAMES: Array[String] = ["카르토", "베른", "토마스", "안나", "헬가", "일리아"]
const RESIDENT_NAMES: Array[String] = ["그레타", "루드비크", "미라", "페테", "한나", "욘"]

const QUESTS_BY_ROLE: Dictionary = {
	"길드장": [
		{"text": "다음 챕터로 가는 산길에 도적단이 출몰한다는 보고가 있다. 정리해주면 길드 측에서 사례하겠다.", "reward": 80},
		{"text": "용병단 결원이 생겼네. 모험가를 만나거든 합류 제안을 전해주게.", "reward": 60},
	],
	"조합장": [
		{"text": "이웃 상단과의 보호 계약 의뢰일세. 다음 전투에서 살아남는다면 보상금을 보장하지.", "reward": 80},
		{"text": "조합 평판을 회복할 필요가 있어. 도시에서 좋은 인상을 남겨주게.", "reward": 50},
	],
	"상인": [
		{"text": "새 물건이 들어왔소. 길에서 만나는 이들에게 알려주면 작은 답례를 드리리다.", "reward": 30},
		{"text": "행상길에 위협이 있소. 호위를 맡아 준다면 사례하지.", "reward": 50},
	],
	"주민": [
		{"text": "잃어버린 양 한 마리를 찾아 주시면 감사하겠어요. 보답은 약소하지만요.", "reward": 25},
		{"text": "회의소 앞 청소를 도와주실래요? 작은 보답을 드릴게요.", "reward": 20},
	],
}

# ── 오버레이 / 상태 ────────────────────────────────────────────
var _hire_overlay: Control
var _gold_label: Label
var _offers_box: VBoxContainer
var _offers: Array[UnitData] = []

var _shop_overlay: Control
var _shop_gold_label: Label
var _shop_stock_grid: GridContainer
var _player_cargo_grid: GridContainer
var _shop_stock: Array[CargoItem] = []  ## 매대 8칸 (없으면 null)

var _npc_list_overlay: Control
var _npc_list_grid: GridContainer
var _current_npcs: Array = []  ## [{role, name}, ...]

var _npc_meet_overlay: Control
var _npc_meet_title_label: Label
var _npc_meet_body_label: Label
var _npc_meet_current: Dictionary = {}
var _npc_meet_quest: Dictionary = {}


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_city.jpg")
	_build_hire_overlay()
	_build_shop_overlay()
	_build_npc_list_overlay()
	_build_npc_meet_overlay()


# ─────────────────────────────────────────────────────────────
# 공통 — 오버레이 셸 생성 (어두운 배경 + 가운데 패널)
# ─────────────────────────────────────────────────────────────
func _make_overlay_shell(min_panel_width: int) -> Dictionary:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(float(min_panel_width), 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 14)
	panel.add_child(vbox)

	return {"overlay": overlay, "vbox": vbox}


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

		var name_label := Label.new()
		name_label.text = unit.display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)

		var price_label := Label.new()
		price_label.text = "%d G" % price
		price_label.custom_minimum_size = Vector2(70, 0)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(price_label)

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
		return

	GameState.run.add_unit_data(unit)
	print("[Hub] 용병 고용: %s (-%d G, 잔액 %d)" % [
		unit.display_name, price, GameState.run.gold
	])

	btn.text = "고용됨"
	btn.disabled = true
	_update_gold()
	_refresh_offer_affordability()


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


func _build_hire_overlay() -> void:
	var shell: Dictionary = _make_overlay_shell(460)
	_hire_overlay = shell["overlay"]
	var vbox: VBoxContainer = shell["vbox"]

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

	_offers_box = VBoxContainer.new()
	_offers_box.add_theme_constant_override(&"separation", 8)
	vbox.add_child(_offers_box)

	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_on_hire_overlay_close)
	vbox.add_child(close_btn)


# ─────────────────────────────────────────────────────────────
# 아이템 상점
# ─────────────────────────────────────────────────────────────

func _on_shop_pressed() -> void:
	if GameState.run == null:
		GameState.start_new_run()
	_roll_shop_stock()
	_refresh_shop()
	_shop_overlay.visible = true


## 디스크의 CargoItem 풀에서 SHOP_ROWS*SHOP_COLS = 8개를 뽑음. 챕터 tier 필터 적용.
## 풀이 비어 있으면 모두 null (재고 없음 표시).
func _roll_shop_stock() -> void:
	_shop_stock.clear()
	var pool: Array[CargoItem] = _load_item_pool()
	# 챕터 tier 필터
	var filtered: Array[CargoItem] = []
	for item in pool:
		if item.chapter_tier == 0 or item.chapter_tier <= GameState.run.chapter:
			filtered.append(item)
	# 8개 뽑되 풀이 작으면 풀 크기만큼
	if filtered.is_empty():
		for i in SHOP_ROWS * SHOP_COLS:
			_shop_stock.append(null)
		return
	filtered.shuffle()
	var stock_size: int = SHOP_ROWS * SHOP_COLS
	for i in stock_size:
		_shop_stock.append(filtered[i % filtered.size()])


func _load_item_pool() -> Array[CargoItem]:
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


## 매대 + 플레이어 카고 동시 갱신.
func _refresh_shop() -> void:
	_update_shop_gold()
	_refresh_shop_stock()
	_refresh_player_cargo()


func _update_shop_gold() -> void:
	if _shop_gold_label != null and GameState.run != null:
		_shop_gold_label.text = "보유 골드: %d G   카고: %d/%d 셀" % [
			GameState.run.gold,
			GameState.run.cargo.width * GameState.run.cargo.height - GameState.run.cargo.empty_cells_count(),
			GameState.run.cargo.width * GameState.run.cargo.height,
		]


func _refresh_shop_stock() -> void:
	for child in _shop_stock_grid.get_children():
		child.queue_free()
	for i in SHOP_ROWS * SHOP_COLS:
		var item: CargoItem = _shop_stock[i] if i < _shop_stock.size() else null
		var btn := Button.new()
		btn.custom_minimum_size = SLOT_SIZE
		btn.clip_text = true
		btn.add_theme_font_size_override(&"font_size", 10)
		if item == null:
			btn.text = "(빈 칸)"
			btn.disabled = true
			btn.modulate = Color(1, 1, 1, 0.4)
		else:
			var price: int = CityActions.buy_price(GameState.run, item)
			btn.text = "%s\n%d G" % [item.display_name, price]
			var can_afford: bool = GameState.run.gold >= price
			var has_space: bool = not GameState.run.cargo.find_slot_for(item).is_empty()
			btn.disabled = not (can_afford and has_space)
			if not has_space:
				btn.tooltip_text = "카고 공간 부족"
			elif not can_afford:
				btn.tooltip_text = "골드 부족"
			btn.pressed.connect(_on_shop_buy.bind(i))
		_shop_stock_grid.add_child(btn)


func _refresh_player_cargo() -> void:
	for child in _player_cargo_grid.get_children():
		child.queue_free()
	var cargo: CargoState = GameState.run.cargo
	var occupancy: Array = cargo.occupancy_grid()
	for r in PLAYER_ROWS:
		for c in PLAYER_COLS:
			var btn := Button.new()
			btn.custom_minimum_size = SLOT_SIZE
			btn.clip_text = true
			btn.add_theme_font_size_override(&"font_size", 10)
			# cargo 영역 바깥은 잠긴 슬롯 표시 (도시에서 확장).
			if r >= cargo.height or c >= cargo.width:
				btn.text = "🔒"
				btn.disabled = true
				btn.modulate = Color(0.5, 0.5, 0.5, 0.5)
				_player_cargo_grid.add_child(btn)
				continue
			var occupant: CargoItem = occupancy[r][c]
			if occupant == null:
				btn.text = ""
				btn.disabled = true
				btn.modulate = Color(1, 1, 1, 0.3)
			else:
				var sell: int = CityActions.sell_price(GameState.run, occupant)
				btn.text = "%s\n+%d G" % [occupant.display_name, sell]
				btn.pressed.connect(_on_shop_sell.bind(occupant))
			_player_cargo_grid.add_child(btn)


func _on_shop_buy(stock_idx: int) -> void:
	if stock_idx < 0 or stock_idx >= _shop_stock.size():
		return
	var item: CargoItem = _shop_stock[stock_idx]
	if item == null:
		return
	if not CityActions.buy(GameState.run, item):
		print("[Hub Shop] 구매 실패 — %s" % item.display_name)
		return
	# 매대에서 제거 (한 번 산 건 다시 못 사도록)
	_shop_stock[stock_idx] = null
	print("[Hub Shop] 구매: %s" % item.display_name)
	_refresh_shop()


func _on_shop_sell(item: CargoItem) -> void:
	if item == null:
		return
	if not CityActions.sell(GameState.run, item):
		print("[Hub Shop] 판매 실패 — %s" % item.display_name)
		return
	print("[Hub Shop] 판매: %s" % item.display_name)
	_refresh_shop()


func _on_shop_overlay_close() -> void:
	_shop_overlay.visible = false


func _build_shop_overlay() -> void:
	var shell: Dictionary = _make_overlay_shell(520)
	_shop_overlay = shell["overlay"]
	var vbox: VBoxContainer = shell["vbox"]

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "아이템 상점"
	title.add_theme_font_size_override(&"font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_shop_gold_label = Label.new()
	_shop_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_shop_gold_label)
	vbox.add_child(header)

	# 매대 헤더
	var stock_title := Label.new()
	stock_title.text = "매대 (구매)"
	stock_title.add_theme_font_size_override(&"font_size", 16)
	vbox.add_child(stock_title)

	# 매대 그리드 2×4
	_shop_stock_grid = GridContainer.new()
	_shop_stock_grid.columns = SHOP_COLS
	_shop_stock_grid.add_theme_constant_override(&"h_separation", 4)
	_shop_stock_grid.add_theme_constant_override(&"v_separation", 4)
	vbox.add_child(_shop_stock_grid)

	# 구분선
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 카고 헤더
	var cargo_title := Label.new()
	cargo_title.text = "내 카고 (판매)"
	cargo_title.add_theme_font_size_override(&"font_size", 16)
	vbox.add_child(cargo_title)

	# 플레이어 카고 그리드 4×4
	_player_cargo_grid = GridContainer.new()
	_player_cargo_grid.columns = PLAYER_COLS
	_player_cargo_grid.add_theme_constant_override(&"h_separation", 4)
	_player_cargo_grid.add_theme_constant_override(&"v_separation", 4)
	vbox.add_child(_player_cargo_grid)

	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_on_shop_overlay_close)
	vbox.add_child(close_btn)


# ─────────────────────────────────────────────────────────────
# NPC 리스트 (화면 1)
# ─────────────────────────────────────────────────────────────

func _on_npc_pressed() -> void:
	if GameState.run == null:
		GameState.start_new_run()
	_roll_npcs()
	_populate_npc_list()
	_npc_list_overlay.visible = true


## 6 NPC = 고정 2명(길드장·조합장) + 상인 2명 + 주민 2명 (무작위 이름).
func _roll_npcs() -> void:
	_current_npcs.clear()
	for fx in FIXED_NPCS:
		_current_npcs.append({"role": fx["role"], "name": fx["name"]})
	# 상인 2명
	var merchants: Array[String] = MERCHANT_NAMES.duplicate()
	merchants.shuffle()
	for i in 2:
		_current_npcs.append({"role": "상인", "name": merchants[i]})
	# 주민 2명
	var residents: Array[String] = RESIDENT_NAMES.duplicate()
	residents.shuffle()
	for i in 2:
		_current_npcs.append({"role": "주민", "name": residents[i]})


func _populate_npc_list() -> void:
	for child in _npc_list_grid.get_children():
		child.queue_free()
	for i in _current_npcs.size():
		var npc: Dictionary = _current_npcs[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(180, 56)
		btn.text = "%s\n%s" % [npc["name"], npc["role"]]
		btn.add_theme_font_size_override(&"font_size", 14)
		btn.pressed.connect(_on_npc_select.bind(i))
		_npc_list_grid.add_child(btn)


func _on_npc_select(idx: int) -> void:
	if idx < 0 or idx >= _current_npcs.size():
		return
	_npc_meet_current = _current_npcs[idx]
	_pick_quest_for_meet()
	_apply_meet_to_ui()
	_npc_list_overlay.visible = false
	_npc_meet_overlay.visible = true


func _pick_quest_for_meet() -> void:
	var role: String = _npc_meet_current.get("role", "주민")
	var pool: Array = QUESTS_BY_ROLE.get(role, [])
	if pool.is_empty():
		_npc_meet_quest = {"text": "별다른 용건은 없는 모양이다.", "reward": 0}
		return
	_npc_meet_quest = pool[GameState.rng.randi() % pool.size()]


func _apply_meet_to_ui() -> void:
	if _npc_meet_title_label != null:
		_npc_meet_title_label.text = "%s — %s" % [
			_npc_meet_current.get("name", "?"),
			_npc_meet_current.get("role", "?"),
		]
	if _npc_meet_body_label != null:
		var body: String = _npc_meet_quest.get("text", "")
		var reward: int = int(_npc_meet_quest.get("reward", 0))
		if reward > 0:
			body += "\n\n[보상: %d G]" % reward
		_npc_meet_body_label.text = body


func _on_npc_list_close() -> void:
	_npc_list_overlay.visible = false


func _build_npc_list_overlay() -> void:
	var shell: Dictionary = _make_overlay_shell(440)
	_npc_list_overlay = shell["overlay"]
	var vbox: VBoxContainer = shell["vbox"]

	var title := Label.new()
	title.text = "마을 사람들"
	title.add_theme_font_size_override(&"font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_npc_list_grid = GridContainer.new()
	_npc_list_grid.columns = 2
	_npc_list_grid.add_theme_constant_override(&"h_separation", 8)
	_npc_list_grid.add_theme_constant_override(&"v_separation", 8)
	vbox.add_child(_npc_list_grid)

	var close_btn := Button.new()
	close_btn.text = "광장으로 돌아가기"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_on_npc_list_close)
	vbox.add_child(close_btn)


# ─────────────────────────────────────────────────────────────
# NPC 조우 (화면 2)
# ─────────────────────────────────────────────────────────────

func _on_npc_accept_pressed() -> void:
	var reward: int = int(_npc_meet_quest.get("reward", 0))
	GameState.run.gold += reward
	print("[Hub NPC] 퀘스트 수락 — %s: +%d G (잔액 %d)" % [
		_npc_meet_current.get("name", "?"), reward, GameState.run.gold
	])
	# 수락하면 리스트로 복귀. 같은 NPC를 또 만나면 다른 퀘스트 뽑힘.
	_return_to_npc_list()


func _on_npc_leave_pressed() -> void:
	# 떠나기: 보상 없이 리스트로 복귀.
	_return_to_npc_list()


func _return_to_npc_list() -> void:
	_npc_meet_overlay.visible = false
	_populate_npc_list()  # 골드 갱신을 위해 리프레시
	_npc_list_overlay.visible = true


func _build_npc_meet_overlay() -> void:
	var shell: Dictionary = _make_overlay_shell(480)
	_npc_meet_overlay = shell["overlay"]
	var vbox: VBoxContainer = shell["vbox"]

	_npc_meet_title_label = Label.new()
	_npc_meet_title_label.add_theme_font_size_override(&"font_size", 24)
	_npc_meet_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_npc_meet_title_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_npc_meet_body_label = Label.new()
	_npc_meet_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_npc_meet_body_label.custom_minimum_size = Vector2(440, 120)
	_npc_meet_body_label.add_theme_font_size_override(&"font_size", 14)
	vbox.add_child(_npc_meet_body_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 16)
	var accept_btn := Button.new()
	accept_btn.text = "퀘스트 수락"
	accept_btn.custom_minimum_size = Vector2(140, 40)
	accept_btn.pressed.connect(_on_npc_accept_pressed)
	buttons.add_child(accept_btn)
	var leave_btn := Button.new()
	leave_btn.text = "떠나기"
	leave_btn.custom_minimum_size = Vector2(140, 40)
	leave_btn.pressed.connect(_on_npc_leave_pressed)
	buttons.add_child(leave_btn)
	vbox.add_child(buttons)


# ─────────────────────────────────────────────────────────────
# 메인 hub 액션
# ─────────────────────────────────────────────────────────────

func _on_to_map_pressed() -> void:
	if GameState.run == null:
		GameState.start_new_run()
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


func _on_to_menu_pressed() -> void:
	GameState.end_run(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
