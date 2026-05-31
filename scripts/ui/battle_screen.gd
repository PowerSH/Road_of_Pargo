extends Control

## 일반 전투 화면. battle-flow.md §1~5 의 4 페이즈 상태머신 구현.
## PREP → ITEM_APPLY → BATTLE → (RESULT_SLOWMO) → RESULT_SCREEN → map_screen
##
## 실제 유닛 카탈로그(.tres) / 인카운터 템플릿이 없을 때를 위해 mock 데이터를
## 시드한다. RunState.owned_units가 비어 있고 board에 배치도 없으면 mock 3명을
## 자동 영입 + 배치 (테스트 가능 상태 유지). 실제 데이터가 있으면 mock 안 만듦.

enum Phase { PREP, ITEM_APPLY, BATTLE, RESULT_SLOWMO, RESULT_SCREEN }

const ARENA_SIZE: Vector2 = Vector2(1000, 400)
const PREP_TO_BATTLE_DELAY: float = 0.5
const RESULT_SLOWMO_DURATION: float = 1.5      # game-time 초
const RESULT_SLOWMO_TIME_SCALE: float = 0.3

# 시각 마커 크기 (CombatUnit 위에 그려지는 사각형)
const UNIT_SIZE: Vector2 = Vector2(40, 40)
const HP_BAR_OFFSET: Vector2 = Vector2(-20, -34)
const HP_BAR_SIZE: Vector2 = Vector2(40, 6)

# PREP 그리드 셀 크기 (좌우 두 그리드 + 사이드바 다 들어가도록 컴팩트)
const CELL_SIZE: Vector2 = Vector2(92, 58)
const CELL_GAP: int = 3

var phase: Phase = Phase.PREP

var _prep_layer: Control
var _battle_layer: Node2D
var _result_layer: Control
var _combat_manager: CombatManager

var _encounter_template: EncounterTemplate
var _enemy_board: BoardState
var _enemy_units_list: Array[EnemyUnitData] = []
var _current_result: BattleResult

# PREP 상태 — 사이드바에서 선택된 유닛
var _selected_owned: OwnedUnit = null
# 플레이어 셀 버튼 인덱싱: Vector2i(row, col) -> Button
var _player_cell_buttons: Dictionary = {}
# 사이드바 버튼: OwnedUnit -> Button
var _sidebar_buttons: Dictionary = {}
# 정보 라벨 (PREP 상단)
var _prep_info_label: Label


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_forest.jpg")
	if GameState.run == null:
		push_warning("[BattleScreen] no active run — returning to menu")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	# 기존 placeholder UI (.tscn의 CenterWrap) 숨김
	var existing: Node = get_node_or_null("CenterWrap")
	if existing != null:
		existing.visible = false

	_ensure_test_data()
	_build_layers()
	_enter_prep()


func _exit_tree() -> void:
	# 슬로우모션 중에 씬 전환 시 time_scale 안 복구되면 게임 전체가 느려짐 → 안전망
	Engine.time_scale = 1.0


# ---------- 데이터 시드 (디스크 우선, 없으면 Mock) ----------

const UNITS_DIR: String = "res://resource/units/"
const SYNERGIES_DIR: String = "res://resource/synergies/"


func _ensure_test_data() -> void:
	# 1. 유닛 — owned_units가 비어 있을 때만
	if GameState.run.owned_units.is_empty():
		var loaded: int = _seed_from_disk()
		if loaded == 0:
			print("[BattleScreen] no units on disk — falling back to mock")
			_seed_mock_player_units()
		else:
			print("[BattleScreen] loaded %d units from %s" % [loaded, UNITS_DIR])

	# 2. 보드 자동 배치
	if GameState.board.count_placed() == 0 and not GameState.run.owned_units.is_empty():
		_auto_place_owned_units()

	# 3. 시너지 룰 — active_rules가 비어 있을 때만
	if GameState.run.active_rules.is_empty():
		var rules: Array[SynergyRule] = _load_synergies_from_disk()
		if not rules.is_empty():
			GameState.run.active_rules = rules
			print("[BattleScreen] loaded %d synergy rules" % rules.size())

	# 4. 적 인카운터 (아직 mock)
	_encounter_template = _make_mock_encounter()


## 디스크의 .tres 들을 OwnedUnit으로 영입. 영입 개수 반환.
func _seed_from_disk() -> int:
	var count: int = 0
	var dir: DirAccess = DirAccess.open(UNITS_DIR)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res: Resource = load(UNITS_DIR + fname)
			if res is UnitData:
				GameState.run.add_unit_data(res)
				count += 1
		fname = dir.get_next()
	return count


func _load_synergies_from_disk() -> Array[SynergyRule]:
	var rules: Array[SynergyRule] = []
	var dir: DirAccess = DirAccess.open(SYNERGIES_DIR)
	if dir == null:
		return rules
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res: Resource = load(SYNERGIES_DIR + fname)
			if res is SynergyRule:
				rules.append(res)
		fname = dir.get_next()
	return rules


func _seed_mock_player_units() -> void:
	# 보병 4명 — 근접, 단단함
	for i in 4:
		var ud := UnitData.new()
		ud.id = StringName("mock_infantry_%d" % i)
		ud.display_name = "보병 %d" % (i + 1)
		ud.max_hp = 100.0
		ud.attack = 12.0 + float(i) * 2.0     # 12 / 14 / 16 / 18
		ud.attack_speed = 1.0
		ud.attack_range = 80.0                # 근접
		ud.move_speed = 120.0
		GameState.run.add_unit_data(ud)

	# 궁병 3명 — 원거리, 약함
	for i in 3:
		var ud := UnitData.new()
		ud.id = StringName("mock_archer_%d" % i)
		ud.display_name = "궁병 %d" % (i + 1)
		ud.max_hp = 60.0                      # 더 약함
		ud.attack = 9.0 + float(i) * 1.5      # 9 / 10.5 / 12
		ud.attack_speed = 1.1
		ud.attack_range = 300.0               # 원거리
		ud.move_speed = 110.0                 # 약간 느림
		GameState.run.add_unit_data(ud)


## 클래스 기반 자동 배치 — 보병/창병(근접)은 전열, 궁병/석궁병(원거리)은 후열.
##  전열: col 0 row 0~2 + col 1 row 1 (총 4칸, ▶ 모양)
##  후열: col 3 row 0~2 (총 3칸)
func _auto_place_owned_units() -> void:
	var front_pos: Array = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1),
	]
	var back_pos: Array = [
		Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3),
	]

	var melee: Array[OwnedUnit] = []
	var ranged: Array[OwnedUnit] = []
	for owned: OwnedUnit in GameState.run.owned_units:
		if not owned.is_deployable() or owned.source == null:
			continue
		var class_tag: StringName = owned.source.get_class_tag()
		if class_tag == SynergyTypes.CLASS_INFANTRY or class_tag == SynergyTypes.CLASS_SPEARMAN:
			melee.append(owned)
		elif class_tag == SynergyTypes.CLASS_ARCHER or class_tag == SynergyTypes.CLASS_CROSSBOWMAN:
			ranged.append(owned)
		else:
			# 분류 안 되는 유닛(예: mock — types 비어있음)은 근접 취급
			melee.append(owned)

	var idx: int = 0
	for p: Vector2i in front_pos:
		if idx >= melee.size():
			break
		if GameState.board.get_unit(p.x, p.y) == null:
			GameState.board.place_unit(p.x, p.y, melee[idx])
			idx += 1

	idx = 0
	for p: Vector2i in back_pos:
		if idx >= ranged.size():
			break
		if GameState.board.get_unit(p.x, p.y) == null:
			GameState.board.place_unit(p.x, p.y, ranged[idx])
			idx += 1


func _make_mock_encounter() -> EncounterTemplate:
	var template := EncounterTemplate.new()
	template.id = &"mock_battle"
	template.display_name = "Mock Battle"
	for i in 3:
		var enemy := EnemyUnitData.new()
		enemy.id = StringName("mock_enemy_%d" % i)
		enemy.display_name = "Bandit %d" % (i + 1)
		enemy.max_hp = 80.0
		enemy.attack = 8.0 + float(i) * 1.5
		enemy.attack_speed = 0.9
		enemy.attack_range = 70.0
		enemy.move_speed = 100.0
		enemy.faction_tags.append(&"bandit")
		var slot := EncounterSlot.new()
		slot.row = 0
		slot.col = i
		slot.fixed_unit = enemy
		template.slots.append(slot)
	return template


# ---------- 레이어 빌드 ----------

func _build_layers() -> void:
	_prep_layer = _build_prep_ui()
	add_child(_prep_layer)

	_battle_layer = Node2D.new()
	_battle_layer.name = "BattleLayer"
	# 뷰포트 중앙에 배치 (1280×720 가정)
	_battle_layer.position = Vector2(640, 360)
	_battle_layer.visible = false
	add_child(_battle_layer)

	_result_layer = _build_result_ui()
	_result_layer.visible = false
	add_child(_result_layer)


func _build_prep_ui() -> Control:
	var root := Control.new()
	root.name = "PrepLayer"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 20)
	margin.add_theme_constant_override(&"margin_right", 20)
	margin.add_theme_constant_override(&"margin_top", 16)
	margin.add_theme_constant_override(&"margin_bottom", 16)
	root.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override(&"separation", 10)
	margin.add_child(main_vbox)

	# 상단: 정보 라벨
	_prep_info_label = Label.new()
	_prep_info_label.text = _prep_info_text()
	_prep_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(_prep_info_label)

	# 가운데: [플레이어 grid] ⚔ [적 grid] [보관함]
	var center_hbox := HBoxContainer.new()
	center_hbox.add_theme_constant_override(&"separation", 12)
	center_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(center_hbox)

	# 1. 플레이어 섹션 (왼쪽 진영)
	var player_section := VBoxContainer.new()
	player_section.add_theme_constant_override(&"separation", 4)
	var player_label := Label.new()
	player_label.text = "플레이어  (후열 ◀──▶ 전열)"
	player_label.add_theme_font_size_override(&"font_size", 13)
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_section.add_child(player_label)
	player_section.add_child(_build_player_grid())
	center_hbox.add_child(player_section)

	# 2. 가운데 구분선 ⚔
	var divider := Label.new()
	divider.text = "⚔"
	divider.add_theme_font_size_override(&"font_size", 28)
	divider.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	divider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_hbox.add_child(divider)

	# 3. 적 섹션 (오른쪽 진영)
	var enemy_section := VBoxContainer.new()
	enemy_section.add_theme_constant_override(&"separation", 4)
	var enemy_label := Label.new()
	enemy_label.text = "적군  (전열 ◀──▶ 후열)"
	enemy_label.add_theme_font_size_override(&"font_size", 13)
	enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_section.add_child(enemy_label)
	enemy_section.add_child(_build_enemy_grid())
	center_hbox.add_child(enemy_section)

	# 4. 보관함 사이드바
	var sidebar_vbox := VBoxContainer.new()
	sidebar_vbox.custom_minimum_size = Vector2(180, 0)
	sidebar_vbox.add_theme_constant_override(&"separation", 4)
	center_hbox.add_child(sidebar_vbox)

	var sidebar_label := Label.new()
	sidebar_label.text = "보관함"
	sidebar_label.add_theme_font_size_override(&"font_size", 13)
	sidebar_vbox.add_child(sidebar_label)

	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_vbox.add_child(sidebar_scroll)

	var sidebar_content := VBoxContainer.new()
	sidebar_content.name = "SidebarContent"
	sidebar_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_content.add_theme_constant_override(&"separation", 3)
	sidebar_scroll.add_child(sidebar_content)

	# 하단: 안내 + 전투 시작 버튼
	var hint := Label.new()
	hint.text = "셀 클릭: 회수  |  사이드바 클릭 + 빈 셀: 배치  |  셀 드래그 → 빈 셀: 이동"
	hint.add_theme_font_size_override(&"font_size", 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1.0, 1.0, 1.0, 0.65)
	main_vbox.add_child(hint)

	var start_btn := Button.new()
	start_btn.text = "전투 시작"
	start_btn.custom_minimum_size = Vector2(240, 50)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.pressed.connect(_on_start_battle_pressed)
	main_vbox.add_child(start_btn)

	_refresh_sidebar()

	return root


func _prep_info_text() -> String:
	var run: RunState = GameState.run
	var player_placed: int = GameState.board.count_placed()
	var enemy_count: int = _encounter_template.slots.size()
	var selected_name: String = ""
	if _selected_owned != null and _selected_owned.source != null:
		selected_name = "   선택: %s" % _selected_owned.source.display_name
	return "Chapter %d   Gold %d   배치 %d명   vs   적 %d명%s" % [
		run.chapter, run.gold, player_placed, enemy_count, selected_name
	]


func _build_enemy_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = BoardState.COLS
	grid.add_theme_constant_override(&"h_separation", CELL_GAP)
	grid.add_theme_constant_override(&"v_separation", CELL_GAP)
	grid.name = "EnemyGrid"

	# 슬롯 인덱싱: (row,col) -> EncounterSlot
	var slot_lookup: Dictionary = {}
	for slot: EncounterSlot in _encounter_template.slots:
		slot_lookup[Vector2i(slot.row, slot.col)] = slot

	for row in BoardState.ROWS:
		for col in BoardState.COLS:
			var cell := Panel.new()
			cell.custom_minimum_size = CELL_SIZE

			var label := Label.new()
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override(&"font_size", 9)
			label.clip_text = true

			var key := Vector2i(row, col)
			if slot_lookup.has(key):
				var slot: EncounterSlot = slot_lookup[key]
				var unit: EnemyUnitData = slot.fixed_unit
				if unit == null and not slot.variation_pool.is_empty():
					unit = slot.variation_pool[0]
				if unit != null:
					label.text = "%s\nHP %.0f / ATK %.0f" % [
						unit.display_name, unit.max_hp, unit.attack
					]
					cell.modulate = Color(1.0, 0.75, 0.75)
			else:
				label.text = "—"
				cell.modulate = Color(1.0, 1.0, 1.0, 0.4)
			cell.add_child(label)
			grid.add_child(cell)
	return grid


func _build_player_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = BoardState.COLS
	grid.add_theme_constant_override(&"h_separation", CELL_GAP)
	grid.add_theme_constant_override(&"v_separation", CELL_GAP)
	grid.name = "PlayerGrid"

	# 컬럼을 역순으로 추가 — 시각상 col 4(후열)가 왼쪽, col 0(전열)이 오른쪽 (적 진영 방향).
	# 데이터 셀(row, col)은 그대로 유지 — 시그널/배치 로직 변경 없음.
	for row in BoardState.ROWS:
		for col_visual in BoardState.COLS:
			var col: int = BoardState.COLS - 1 - col_visual
			var btn := Button.new()
			btn.custom_minimum_size = CELL_SIZE
			btn.clip_text = true
			btn.add_theme_font_size_override(&"font_size", 9)
			btn.pressed.connect(_on_player_cell_pressed.bind(row, col))
			# 드래그앤드롭: 빠른 클릭은 pressed 시그널 (회수), 드래그 시작 시 _drag_get
			btn.set_drag_forwarding(
				_cell_drag_get.bind(row, col),
				_cell_drag_can_drop.bind(row, col),
				_cell_drag_drop.bind(row, col),
			)
			_player_cell_buttons[Vector2i(row, col)] = btn
			grid.add_child(btn)

	_refresh_player_grid()
	return grid


func _refresh_player_grid() -> void:
	for row in BoardState.ROWS:
		for col in BoardState.COLS:
			var btn: Button = _player_cell_buttons[Vector2i(row, col)]
			var cell_val: Resource = GameState.board.get_unit(row, col)
			var owned: OwnedUnit = cell_val as OwnedUnit
			if owned == null or owned.source == null:
				btn.text = "─"
				btn.modulate = Color(1.0, 1.0, 1.0, 0.6)
			else:
				var hp: float = owned.get_starting_hp(owned.source.max_hp)
				btn.text = "%s\nHP %.0f / %.0f" % [
					owned.source.display_name, hp, owned.source.max_hp
				]
				btn.modulate = Color(0.75, 0.9, 1.0)


func _refresh_sidebar() -> void:
	if _prep_layer == null:
		return
	var sidebar: Node = _prep_layer.find_child("SidebarContent", true, false)
	if sidebar == null:
		return
	for child in sidebar.get_children():
		child.queue_free()
	_sidebar_buttons.clear()

	# 배치된 OwnedUnit은 제외, 나머지를 사이드바에 표시
	var placed_set: Dictionary = {}
	for entry in GameState.board.iter_placed():
		placed_set[entry.unit] = true

	var shown: int = 0
	for owned: OwnedUnit in GameState.run.owned_units:
		if placed_set.has(owned):
			continue
		shown += 1
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 54)
		btn.clip_text = true
		btn.add_theme_font_size_override(&"font_size", 11)

		var badge: String = ""
		var deployable: bool = true
		match owned.status:
			OwnedUnit.Status.READY:
				badge = "✓"
			OwnedUnit.Status.INJURED:
				badge = "⚠(%d)" % owned.injured_stages_left
				deployable = false
			OwnedUnit.Status.DEAD:
				badge = "☠"
				deployable = false

		var name_str: String = owned.source.display_name if owned.source else "?"
		var max_hp: float = owned.source.max_hp if owned.source else 0.0
		var atk: float = owned.source.attack if owned.source else 0.0
		btn.text = "%s %s\nHP %.0f / ATK %.0f" % [badge, name_str, max_hp, atk]
		btn.disabled = not deployable

		if _selected_owned == owned:
			btn.modulate = Color(0.7, 1.0, 0.7)

		btn.pressed.connect(_on_sidebar_unit_pressed.bind(owned))
		sidebar.add_child(btn)
		_sidebar_buttons[owned] = btn

	# 빈 상태 안내
	if shown == 0:
		var empty := Label.new()
		empty.text = "(보관함 비어 있음)"
		empty.add_theme_font_size_override(&"font_size", 11)
		empty.modulate = Color(1.0, 1.0, 1.0, 0.6)
		sidebar.add_child(empty)

	_update_prep_info()


func _update_prep_info() -> void:
	if _prep_info_label != null:
		_prep_info_label.text = _prep_info_text()


func _on_player_cell_pressed(row: int, col: int) -> void:
	var cell_val: Resource = GameState.board.get_unit(row, col)
	var existing: OwnedUnit = cell_val as OwnedUnit

	if existing != null:
		# 셀이 차 있으면 보관함으로 회수
		GameState.board.remove_unit(row, col)
		if _selected_owned == existing:
			_selected_owned = null
		_refresh_player_grid()
		_refresh_sidebar()
		return

	# 빈 셀 — 선택된 유닛 있으면 배치
	if _selected_owned == null:
		return
	if not _selected_owned.is_deployable():
		_selected_owned = null
		_refresh_sidebar()
		return
	GameState.board.place_unit(row, col, _selected_owned)
	_selected_owned = null
	_refresh_player_grid()
	_refresh_sidebar()


func _on_sidebar_unit_pressed(owned: OwnedUnit) -> void:
	if not owned.is_deployable():
		return
	if _selected_owned == owned:
		_selected_owned = null
	else:
		_selected_owned = owned
	_refresh_sidebar()


# ---------- 드래그앤드롭: 플레이어 셀 ↔ 플레이어 셀 ----------
# Godot Control.set_drag_forwarding: callable에 (row, col) 바인딩되어 끝에 붙음.
# 시그니처 — set_drag_forwarding의 callable은 가상 메서드와 같음:
#   drag_get(at_pos: Vector2) -> Variant
#   can_drop(at_pos: Vector2, data: Variant) -> bool
#   drop(at_pos: Vector2, data: Variant) -> void

func _cell_drag_get(_at_pos: Vector2, row: int, col: int) -> Variant:
	var owned: OwnedUnit = GameState.board.get_unit(row, col) as OwnedUnit
	if owned == null:
		return null
	# 드래그 프리뷰 — 반투명 셀
	var preview := Panel.new()
	preview.custom_minimum_size = CELL_SIZE
	preview.modulate = Color(0.75, 0.9, 1.0, 0.85)
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override(&"font_size", 10)
	if owned.source != null:
		lbl.text = "%s\nHP %.0f" % [owned.source.display_name, owned.source.max_hp]
	else:
		lbl.text = "?"
	preview.add_child(lbl)
	var src_btn: Button = _player_cell_buttons.get(Vector2i(row, col))
	if src_btn != null:
		src_btn.set_drag_preview(preview)
	return {
		"type": "owned_unit",
		"owned": owned,
		"from_row": row,
		"from_col": col,
	}


func _cell_drag_can_drop(_at_pos: Vector2, data: Variant, row: int, col: int) -> bool:
	if not (data is Dictionary):
		return false
	if data.get("type", "") != "owned_unit":
		return false
	# 같은 자리 = no-op
	if data.get("from_row") == row and data.get("from_col") == col:
		return false
	# 빈 셀에만 드롭 가능 (스왑은 후속 작업)
	return GameState.board.get_unit(row, col) == null


func _cell_drag_drop(_at_pos: Vector2, data: Variant, row: int, col: int) -> void:
	var owned: OwnedUnit = data.get("owned") as OwnedUnit
	if owned == null:
		return
	var from_row: int = data.get("from_row", -1)
	var from_col: int = data.get("from_col", -1)
	if from_row >= 0 and from_col >= 0:
		GameState.board.remove_unit(from_row, from_col)
	GameState.board.place_unit(row, col, owned)
	# 드래그 중에 선택 상태였으면 해제
	if _selected_owned == owned:
		_selected_owned = null
	_refresh_player_grid()
	_refresh_sidebar()


func _build_result_ui() -> Control:
	var root := CenterContainer.new()
	root.name = "ResultLayer"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.name = "ResultStack"
	vbox.add_theme_constant_override(&"separation", 18)
	root.add_child(vbox)

	var outcome := Label.new()
	outcome.name = "Outcome"
	outcome.add_theme_font_size_override(&"font_size", 48)
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(outcome)

	var detail := Label.new()
	detail.name = "Detail"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(detail)

	var continue_btn := Button.new()
	continue_btn.name = "ContinueButton"
	continue_btn.custom_minimum_size = Vector2(240, 50)
	continue_btn.pressed.connect(_on_continue_pressed)
	vbox.add_child(continue_btn)

	return root


# ---------- 페이즈 전환 ----------

func _enter_prep() -> void:
	phase = Phase.PREP
	_prep_layer.visible = true
	_battle_layer.visible = false
	_result_layer.visible = false


func _on_start_battle_pressed() -> void:
	if phase != Phase.PREP:
		return
	_prep_layer.visible = false
	_enter_item_apply()


func _enter_item_apply() -> void:
	phase = Phase.ITEM_APPLY
	# 아이템 슬롯 시스템은 후속. 일단 짧은 딜레이 후 BATTLE로.
	print("[BattleScreen] ITEM_APPLY (skipped — no items yet)")
	get_tree().create_timer(PREP_TO_BATTLE_DELAY).timeout.connect(_enter_battle)


func _enter_battle() -> void:
	phase = Phase.BATTLE
	_battle_layer.visible = true

	_combat_manager = CombatManager.new()
	_combat_manager.name = "CombatManager"
	_combat_manager.arena_size = ARENA_SIZE
	_combat_manager.injury_threshold = GameState.run.injury_threshold()
	_combat_manager.battle_ended.connect(_on_battle_ended)
	_combat_manager.unit_spawned.connect(_on_unit_spawned)
	_battle_layer.add_child(_combat_manager)

	# 플레이어 측: stats + owned + 그리드 위치를 한 번 iter_placed로 같이 빌드 (parallel 보장)
	var player_stats: Array[ComputedStats] = []
	var player_owned: Array[OwnedUnit] = []
	var player_grid: Array[Vector2i] = []
	var computed: Dictionary = GameState.compute_current_synergies()
	for entry in GameState.board.iter_placed():
		var owned_ref: OwnedUnit = entry.unit as OwnedUnit
		if owned_ref == null:
			continue
		var key := Vector2i(entry.col, entry.row)
		if not computed.has(key):
			continue
		player_stats.append(computed[key])
		player_owned.append(owned_ref)
		player_grid.append(Vector2i(entry.row, entry.col))

	# 적 인카운터 생성
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var enemy_gen: Dictionary = EncounterGenerator.generate(_encounter_template, rng)
	_enemy_board = enemy_gen["board"]
	_enemy_units_list = enemy_gen["units"]
	var enemy_computed: Dictionary = EnemySynergyEngine.compute_pre_battle(
		_enemy_board, _encounter_template.rules
	)
	var enemy_stats: Array[ComputedStats] = EnemySynergyEngine.payload_from(
		_enemy_board, enemy_computed
	)
	var enemy_grid: Array[Vector2i] = []
	for entry in _enemy_board.iter_placed():
		enemy_grid.append(Vector2i(entry.row, entry.col))

	print("[BattleScreen] BATTLE start — player=%d enemies=%d" % [
		player_stats.size(), enemy_stats.size()
	])
	_combat_manager.start_battle(
		player_stats, player_owned, enemy_stats, player_grid, enemy_grid
	)


func _on_unit_spawned(unit: CombatUnit) -> void:
	# 시각 마커: 사각형 (팀 색상) + HP 바
	var color_rect := ColorRect.new()
	color_rect.size = UNIT_SIZE
	color_rect.position = -UNIT_SIZE * 0.5
	color_rect.color = Color.SKY_BLUE if unit.team == CombatUnit.Team.PLAYER else Color.INDIAN_RED
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_rect.name = "Marker"
	unit.add_child(color_rect)

	var hp_bar := ProgressBar.new()
	hp_bar.size = HP_BAR_SIZE
	hp_bar.position = HP_BAR_OFFSET
	hp_bar.max_value = unit.stats.max_hp
	hp_bar.value = unit.current_hp
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.name = "HpBar"
	# Settings에 따라 ON_HOVER 모드는 평소 숨김 (후속 단계에서 마우스 hover 연동)
	if Settings.hp_bar_mode == Settings.HpBarMode.ON_HOVER:
		hp_bar.visible = false
	unit.add_child(hp_bar)

	unit.damaged.connect(func(u: CombatUnit, _amt: float) -> void:
		hp_bar.value = u.current_hp
	)
	unit.died.connect(func(_u: CombatUnit) -> void:
		color_rect.modulate.a = 0.2
		hp_bar.visible = false
	)


func _on_battle_ended(result: BattleResult) -> void:
	# CombatManager는 적 power를 모름 → caller가 gold 계산해서 setter
	var is_boss: bool = _current_node_is_boss()
	var is_draw: bool = result.outcome == BattleResult.Outcome.DRAW
	result.gold_reward = EncounterGenerator.compute_gold_reward(
		_enemy_units_list, is_boss, is_draw
	)
	result.enemy_power_total = EncounterGenerator.compute_total_power(_enemy_units_list)
	result.encounter_id = _encounter_template.id
	_current_result = result

	GameState.run.gold += result.gold_reward

	print("[BattleScreen] BATTLE end — outcome=%s gold=+%d dur=%.1fs" % [
		BattleResult.Outcome.keys()[result.outcome],
		result.gold_reward,
		result.duration_sec,
	])

	# WIN 시만 슬로우모션, LOSS/DRAW는 즉시 결과 화면
	if result.outcome == BattleResult.Outcome.PLAYER_WIN:
		_enter_result_slowmo()
	else:
		_enter_result_screen()


func _current_node_is_boss() -> bool:
	# battle_screen은 일반 전투 노드용 — 사실상 항상 false.
	# 그래도 안전 차원으로 현재 노드 kind 확인.
	var idx: int = GameState.run.current_node_index
	if idx < 0 or idx >= GameState.run.nodes.size():
		return false
	return GameState.run.nodes[idx].kind == MapNode.Kind.BOSS


func _enter_result_slowmo() -> void:
	phase = Phase.RESULT_SLOWMO
	Engine.time_scale = RESULT_SLOWMO_TIME_SCALE
	# 슬로우모션 동안의 실제 경과 시간 = game_time / time_scale
	# 그러나 create_timer는 실제 시간 단위 — 1.5s 게임타임은 0.45s 실시간.
	# 사용자가 "1.5초 슬로우모션 본다" = 실제 5초 정도 — 너무 김.
	# 일단 게임타임 1.5초 × 0.3 = 실시간 0.45초 진행 후 결과 화면.
	get_tree().create_timer(RESULT_SLOWMO_DURATION * RESULT_SLOWMO_TIME_SCALE).timeout.connect(_finish_slowmo)


func _finish_slowmo() -> void:
	Engine.time_scale = 1.0
	_enter_result_screen()


func _enter_result_screen() -> void:
	phase = Phase.RESULT_SCREEN
	Engine.time_scale = 1.0
	_battle_layer.visible = false
	_result_layer.visible = true
	_populate_result_screen()


func _populate_result_screen() -> void:
	var outcome_label: Label = _result_layer.get_node("ResultStack/Outcome")
	var detail_label: Label = _result_layer.get_node("ResultStack/Detail")
	var continue_btn: Button = _result_layer.get_node("ResultStack/ContinueButton")

	match _current_result.outcome:
		BattleResult.Outcome.PLAYER_WIN:
			outcome_label.text = "승리"
			detail_label.text = "골드 +%d\n부상자: %d명\n전투 시간 %.1fs" % [
				_current_result.gold_reward,
				_current_result.newly_injured.size(),
				_current_result.duration_sec,
			]
			continue_btn.text = "계속"
		BattleResult.Outcome.DRAW:
			outcome_label.text = "무승부"
			detail_label.text = "골드 +%d (절반)\n양측 부상: %d명\n전투 시간 %.1fs" % [
				_current_result.gold_reward,
				_current_result.newly_injured.size(),
				_current_result.duration_sec,
			]
			continue_btn.text = "계속"
		BattleResult.Outcome.PLAYER_LOSS:
			outcome_label.text = "패배"
			detail_label.text = "런 종료\n전투 시간 %.1fs" % _current_result.duration_sec
			continue_btn.text = "메인 메뉴로"


func _on_continue_pressed() -> void:
	if _current_result.outcome == BattleResult.Outcome.PLAYER_LOSS:
		GameState.end_run(false)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# ---------- 기존 .tscn의 placeholder 시그널 stub ----------
# .tscn에 [connection] 줄이 _on_victory_pressed / _on_defeat_pressed로 걸려 있어서
# 메서드가 없으면 파싱 워닝. CenterWrap이 invisible이라 실제 호출 안 됨.

func _on_victory_pressed() -> void:
	pass


func _on_defeat_pressed() -> void:
	pass
