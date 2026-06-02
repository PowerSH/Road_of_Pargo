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

## 역할별 퀘스트 템플릿. 매번 무작위 1개를 골라서 NPC가 제안.
## kind / target_value / reward_gold / description / detail / reward_text.
const QUEST_TEMPLATES_BY_ROLE: Dictionary = {
	"길드장": [
		{"kind": Quest.Kind.WIN_BATTLES, "target": 3, "reward": 100,
		 "desc": "노상 정리 의뢰", "reward_text": "100 G",
		 "detail": "이 마을을 떠나기 전 3번의 전투에서 승리해 도로를 안전하게 만들어 주게."},
		{"kind": Quest.Kind.DEFEAT_BOSS, "target": 1, "reward": 150,
		 "desc": "보스 토벌", "reward_text": "150 G",
		 "detail": "다음 챕터 보스를 직접 처치하라. 보상은 길드 금고에서 직접 내겠다."},
	],
	"조합장": [
		{"kind": Quest.Kind.WIN_BATTLES, "target": 2, "reward": 70,
		 "desc": "상단 호위", "reward_text": "70 G",
		 "detail": "이웃 상단의 호위 계약일세. 다음 2번의 전투에서 살아남으면 보상금을 보장하지."},
		{"kind": Quest.Kind.HIRE_UNITS, "target": 2, "reward": 80,
		 "desc": "용병단 보강", "reward_text": "80 G",
		 "detail": "새 용병 2명을 영입하라. 조합이 지원금을 내겠다."},
	],
	"상인": [
		{"kind": Quest.Kind.WIN_BATTLES, "target": 1, "reward": 40,
		 "desc": "도로 정리", "reward_text": "40 G",
		 "detail": "다음 전투에서 승리해 주시오. 작은 답례를 드리리다."},
		{"kind": Quest.Kind.HIRE_UNITS, "target": 1, "reward": 30,
		 "desc": "용병 추천", "reward_text": "30 G",
		 "detail": "용병 1명을 새로 영입하시오. 거래 안전에 도움이 될 게요."},
	],
	"주민": [
		{"kind": Quest.Kind.WIN_BATTLES, "target": 1, "reward": 25,
		 "desc": "마을 수호", "reward_text": "25 G",
		 "detail": "도로의 위험을 한 번 정리해 주세요. 적은 돈이지만 감사 표시를 드리겠어요."},
		{"kind": Quest.Kind.HIRE_UNITS, "target": 1, "reward": 20,
		 "desc": "마을 청년 추천", "reward_text": "20 G",
		 "detail": "마을 청년이 용병 일에 관심이 있어요. 한 명만 더 영입해 주시겠어요?"},
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
## 신규 제안 모드일 때 보관 — 수락 버튼 클릭 시 Quest 객체로 변환되어 active_quests에 추가됨.
var _npc_meet_pending_template: Dictionary = {}
## 신규 제안 / 진행 중 / 완료 보상 수령 — 3-state 분기용 버튼들.
var _npc_meet_accept_btn: Button
var _npc_meet_claim_btn: Button
var _npc_meet_leave_btn: Button


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
	_apply_meet_to_ui()
	_npc_list_overlay.visible = false
	_npc_meet_overlay.visible = true


## NPC 조우 화면을 현재 active quest 상태에 따라 갱신.
## 3-state: 신규 제안 / 진행 중 / 완료 보상 수령.
func _apply_meet_to_ui() -> void:
	var role: String = _npc_meet_current.get("role", "?")
	var npc_name: String = _npc_meet_current.get("name", "?")
	if _npc_meet_title_label != null:
		_npc_meet_title_label.text = "%s — %s" % [npc_name, role]

	var active: Quest = GameState.run.active_quest_from_role(role)
	if active != null:
		if active.is_complete():
			_set_meet_complete_state(active)
		else:
			_set_meet_in_progress_state(active)
	else:
		var tmpl: Dictionary = _pick_quest_template(role)
		_npc_meet_pending_template = tmpl
		_set_meet_offer_state(tmpl)


func _pick_quest_template(role: String) -> Dictionary:
	var pool: Array = QUEST_TEMPLATES_BY_ROLE.get(role, [])
	if pool.is_empty():
		return {}
	return pool[GameState.rng.randi() % pool.size()]


# ── 3-state 본문 + 버튼 ────────────────────────────────────────

func _set_meet_offer_state(tmpl: Dictionary) -> void:
	if tmpl.is_empty():
		_npc_meet_body_label.text = "별다른 용건은 없는 모양이다."
		_npc_meet_accept_btn.visible = false
		_npc_meet_claim_btn.visible = false
		_npc_meet_leave_btn.text = "떠나기"
		return
	var body: String = "%s\n\n%s" % [tmpl.get("desc", ""), tmpl.get("detail", "")]
	body += "\n\n[보상: %s]" % tmpl.get("reward_text", "")
	_npc_meet_body_label.text = body
	_npc_meet_accept_btn.visible = true
	_npc_meet_accept_btn.text = "퀘스트 수락"
	_npc_meet_claim_btn.visible = false
	_npc_meet_leave_btn.text = "떠나기"


func _set_meet_in_progress_state(q: Quest) -> void:
	var body: String = "[진행 중] %s\n\n%s" % [q.description, q.detail]
	body += "\n\n진행도: %s   보상: %s" % [q.progress_text(), q.reward_text]
	_npc_meet_body_label.text = body
	_npc_meet_accept_btn.visible = false
	_npc_meet_claim_btn.visible = false
	_npc_meet_leave_btn.text = "떠나기"


func _set_meet_complete_state(q: Quest) -> void:
	var body: String = "[완료!] %s\n\n%s\n\n수령 가능한 보상: %s" % [
		q.description, q.detail, q.reward_text,
	]
	_npc_meet_body_label.text = body
	_npc_meet_accept_btn.visible = false
	_npc_meet_claim_btn.visible = true
	_npc_meet_claim_btn.text = "보상 수령"
	_npc_meet_leave_btn.text = "떠나기"


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

## 신규 퀘스트 수락 — pending template을 Quest 객체로 변환해 active_quests에 추가.
## 골드는 여기서 안 줌 (완료 후 보상 수령에서 지급).
func _on_npc_accept_pressed() -> void:
	if _npc_meet_pending_template.is_empty():
		return
	var role: String = _npc_meet_current.get("role", "?")
	# 동일 role의 active quest가 있으면 거부 (UI에선 이미 분기됨, 안전망).
	if GameState.run.has_active_quest_from(role):
		return
	var tmpl: Dictionary = _npc_meet_pending_template
	var q := Quest.new()
	q.id = StringName("q_%s_%d" % [role, Time.get_ticks_msec()])
	q.giver_role = role
	q.giver_name = _npc_meet_current.get("name", "?")
	q.description = tmpl.get("desc", "")
	q.detail = tmpl.get("detail", "")
	q.kind = int(tmpl.get("kind", Quest.Kind.WIN_BATTLES))
	q.target_value = int(tmpl.get("target", 1))
	q.reward_gold = int(tmpl.get("reward", 0))
	q.reward_text = tmpl.get("reward_text", "")
	q.accepted_at_chapter = GameState.run.chapter
	q.accepted_at_stage = max(GameState.run.current_node_index, 0)
	GameState.run.active_quests.append(q)
	_npc_meet_pending_template = {}
	print("[Hub NPC] 퀘스트 수락: %s (%s) — %s" % [q.description, role, q.summary()])
	_return_to_npc_list()


## 완료된 퀘스트 보상 수령 — 골드 지급 + active_quests에서 제거 + completed에 추가.
func _on_npc_claim_pressed() -> void:
	var role: String = _npc_meet_current.get("role", "?")
	var q: Quest = GameState.run.active_quest_from_role(role)
	if q == null or not q.is_complete():
		return
	if not QuestTracker.grant_reward(GameState.run, q):
		return
	GameState.run.active_quests.erase(q)
	GameState.run.completed_quest_ids.append(q.id)
	print("[Hub NPC] 퀘스트 보상 수령: %s — +%d G (잔액 %d)" % [
		q.description, q.reward_gold, GameState.run.gold
	])
	_return_to_npc_list()


func _on_npc_leave_pressed() -> void:
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
	_npc_meet_accept_btn = Button.new()
	_npc_meet_accept_btn.text = "퀘스트 수락"
	_npc_meet_accept_btn.custom_minimum_size = Vector2(140, 40)
	_npc_meet_accept_btn.pressed.connect(_on_npc_accept_pressed)
	buttons.add_child(_npc_meet_accept_btn)
	_npc_meet_claim_btn = Button.new()
	_npc_meet_claim_btn.text = "보상 수령"
	_npc_meet_claim_btn.custom_minimum_size = Vector2(140, 40)
	_npc_meet_claim_btn.visible = false
	_npc_meet_claim_btn.pressed.connect(_on_npc_claim_pressed)
	buttons.add_child(_npc_meet_claim_btn)
	_npc_meet_leave_btn = Button.new()
	_npc_meet_leave_btn.text = "떠나기"
	_npc_meet_leave_btn.custom_minimum_size = Vector2(140, 40)
	_npc_meet_leave_btn.pressed.connect(_on_npc_leave_pressed)
	buttons.add_child(_npc_meet_leave_btn)
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
