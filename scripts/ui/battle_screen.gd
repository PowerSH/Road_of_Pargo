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

# 전투 유닛 스프라이트 (AnimatedSprite2D). 프레임 원본 128px → 화면 표시 크기로 스케일.
const SPRITE_FRAME_PX: float = 128.0
## 화면 표시 크기. CombatUnit.BODY_RADIUS*2(=72px)보다 작아야 근접 시 안 겹침.
const SPRITE_DISPLAY_PX: float = 64.0
const SPRITE_SCALE: float = SPRITE_DISPLAY_PX / SPRITE_FRAME_PX
const SPRITE_ANIM_FPS: float = 10.0     ## 원본 GIF가 10 FPS
const PLAYER_SPRITE_DIR: String = "res://resource/sprites/warrior/"
const ENEMY_SPRITE_DIR: String = "res://resource/sprites/slime/"
## 원본 아트가 왼쪽을 보고 있으면 true. (오른쪽이 기본이면 false)
## 동적 flip = (target이 왼쪽인가) XOR (원본이 왼쪽 향함).
const PLAYER_SPRITE_FACES_LEFT: bool = false
const ENEMY_SPRITE_FACES_LEFT: bool = false

# HP 바 — 얇은 ColorRect 2장(배경+채움). 스프라이트(머리) 위에 GAP만큼 띄움.
const HP_BAR_W: float = 44.0
const HP_BAR_H: float = 5.0
const HP_BAR_GAP: float = 6.0  ## 스프라이트 상단과 바 하단 사이 간격

# PREP 그리드 셀 크기
const CELL_SIZE: Vector2 = Vector2(92, 58)
const CELL_GAP: int = 3

# 보관함 — 2행 × 5열 = 10칸. 미배치 유닛만 채우고 나머지는 빈 슬롯.
const ROSTER_COLS: int = 5
const ROSTER_MAX: int = 10
const ROSTER_SLOT_SIZE: Vector2 = Vector2(110, 48)

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

## 사용자가 슬롯에 채워둔 ItemEffect들. 슬롯 UI는 후속 — Cargo 아이템 PR 이후 채움.
## 이 배열이 비어도 ITEM_APPLY 경로는 안전하게 no-op으로 동작한다.
var _slot_items: Array[ItemEffect] = []
# 플레이어 셀 버튼 인덱싱: Vector2i(row, col) -> Button
var _player_cell_buttons: Dictionary = {}
# 보관함 칩 버튼: OwnedUnit -> Button
var _sidebar_buttons: Dictionary = {}
# 보관함 그리드 (직접 참조 — _refresh_sidebar가 _prep_layer 의존 없이 갱신)
var _roster_box: GridContainer

# 팀별 SpriteFrames 캐시 (폴더에서 1회 빌드 후 재사용)
var _sprite_frames_cache: Dictionary = {}  ## String dir -> SpriteFrames

# 라이브 HP 바 — 매 프레임 current_hp에서 직접 갱신 (데미지/회복/초기값 모두 반영)
var _live_bars: Array = []  ## [{unit:CombatUnit, fill:ColorRect, max_hp:float}]


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
	_evict_unfit_from_board()  # 부상/사망 유닛은 전장에서 내려 보관함으로
	_build_layers()
	_enter_prep()


func _exit_tree() -> void:
	# 슬로우모션 중에 씬 전환 시 time_scale 안 복구되면 게임 전체가 느려짐 → 안전망
	Engine.time_scale = 1.0


## 전투 중 매 프레임 HP 바 갱신 — current_hp에서 직접 읽어 데미지·회복 모두 반영.
func _process(_delta: float) -> void:
	if phase != Phase.BATTLE:
		return
	for b in _live_bars:
		var u: CombatUnit = b["unit"]
		var fill: ColorRect = b["fill"]
		if not is_instance_valid(u) or not is_instance_valid(fill) or not fill.visible:
			continue
		var ratio: float = clampf(u.current_hp / b["max_hp"], 0.0, 1.0)
		fill.size = Vector2(HP_BAR_W * ratio, HP_BAR_H)


# ---------- 데이터 시드 (디스크 우선, 없으면 Mock) ----------

const UNITS_DIR: String = "res://resource/units/"
const SYNERGIES_DIR: String = "res://resource/synergies/"
const ENCOUNTERS_DIR: String = "res://resource/encounters/"


## 보드에 배치된 유닛 중 전투 불가(부상/사망)인 것을 내려 보관함으로 돌려보낸다.
## 전 전투에서 사망→부상 처리된 유닛이 다음 전투 전장에 다시 나오는 걸 방지.
func _evict_unfit_from_board() -> void:
	if GameState.board == null:
		return
	# iter_placed()는 스냅샷 배열이라 순회 중 제거 안전.
	for entry in GameState.board.iter_placed():
		var owned: OwnedUnit = entry.unit as OwnedUnit
		if owned != null and not owned.is_deployable():
			GameState.board.remove_unit(entry.row, entry.col)


func _ensure_test_data() -> void:
	# GameState.start_new_run이 owned_units / active_rules를 디스크에서 미리 채움.
	# 여기는 안전망 — start_new_run을 거치지 않은 진입(직접 battle_screen 띄우는 디버그 등) 대비.

	# 1. 유닛 — 여전히 비어 있으면 디스크 → mock 순서로 시도.
	if GameState.run.owned_units.is_empty():
		var loaded: int = _seed_from_disk()
		if loaded == 0:
			print("[BattleScreen] no units on disk — falling back to mock")
			_seed_mock_player_units()
		else:
			print("[BattleScreen] safety net loaded %d units from disk" % loaded)

	# 2. 보드 자동 배치
	if GameState.board.count_placed() == 0 and not GameState.run.owned_units.is_empty():
		_auto_place_owned_units()

	# 3. 시너지 룰 안전망 — active_rules가 여전히 비어 있을 때만.
	if GameState.run.active_rules.is_empty():
		var rules: Array[SynergyRule] = _load_synergies_from_disk()
		if not rules.is_empty():
			GameState.run.active_rules = rules
			print("[BattleScreen] safety net loaded %d synergy rules" % rules.size())

	# 4. 적 인카운터 — 디스크 우선, 없으면 mock
	_encounter_template = _load_encounter_from_disk()
	if _encounter_template == null:
		print("[BattleScreen] no encounter on disk — falling back to mock")
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


## 디스크의 인카운터 .tres 중 하나를 무작위 선택. 없으면 null.
func _load_encounter_from_disk() -> EncounterTemplate:
	var dir: DirAccess = DirAccess.open(ENCOUNTERS_DIR)
	if dir == null:
		return null
	var candidates: Array[String] = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			candidates.append(fname)
		fname = dir.get_next()
	if candidates.is_empty():
		return null
	var pick: String = candidates[randi() % candidates.size()]
	var res: Resource = load(ENCOUNTERS_DIR + pick)
	if res is EncounterTemplate:
		print("[BattleScreen] loaded encounter: %s" % pick)
		return res
	return null


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
	main_vbox.add_theme_constant_override(&"separation", 12)
	margin.add_child(main_vbox)

	# 가운데(확장 영역): [플레이어 grid] ⚔ [적 grid] 를 화면 중앙에 정렬.
	var center_area := CenterContainer.new()
	center_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(center_area)

	var battle_hbox := HBoxContainer.new()
	battle_hbox.add_theme_constant_override(&"separation", 16)
	battle_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_area.add_child(battle_hbox)

	# 플레이어 진영 (왼쪽)
	var player_section := VBoxContainer.new()
	player_section.alignment = BoxContainer.ALIGNMENT_CENTER
	player_section.add_child(_build_player_grid())
	battle_hbox.add_child(player_section)

	# 가운데 구분선 ⚔
	var divider := Label.new()
	divider.text = "⚔"
	divider.add_theme_font_size_override(&"font_size", 28)
	divider.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	battle_hbox.add_child(divider)

	# 적 진영 (오른쪽)
	var enemy_section := VBoxContainer.new()
	enemy_section.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_section.add_child(_build_enemy_grid())
	battle_hbox.add_child(enemy_section)

	# 하단: 보관함 — 2×5 고정 그리드(10칸). 미배치 유닛만 채움.
	var roster_label := Label.new()
	roster_label.text = "보관함"
	roster_label.add_theme_font_size_override(&"font_size", 13)
	roster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(roster_label)

	var roster_grid := GridContainer.new()
	roster_grid.name = "RosterContent"
	roster_grid.columns = ROSTER_COLS
	roster_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	roster_grid.add_theme_constant_override(&"h_separation", 6)
	roster_grid.add_theme_constant_override(&"v_separation", 6)
	# 셀→보관함 드롭(회수) 드롭 타깃.
	roster_grid.set_drag_forwarding(Callable(), _sidebar_can_drop, _sidebar_drop)
	main_vbox.add_child(roster_grid)
	_roster_box = roster_grid

	# 하단: 전투 시작 버튼
	var start_btn := Button.new()
	start_btn.text = "전투 시작"
	start_btn.custom_minimum_size = Vector2(240, 50)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.pressed.connect(_on_start_battle_pressed)
	main_vbox.add_child(start_btn)

	_refresh_sidebar()

	return root


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
					label.text = unit.display_name
					cell.modulate = Color(1.0, 0.75, 0.75)
			else:
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
			# 배치는 전적으로 드래그앤드롭. (클릭-선택 방식 폐기)
			#   셀→빈 셀: 이동 / 셀→보관함: 회수 / 보관함→빈 셀: 배치
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
				btn.text = ""
				btn.modulate = Color(1.0, 1.0, 1.0, 0.6)
			else:
				btn.text = owned.source.display_name
				btn.modulate = Color(0.75, 0.9, 1.0)


## 보관함(2×5 그리드) 갱신. 배치된 유닛은 보드에 있으므로 칸을 차지하지 않는다.
## 미배치 유닛만 채우고, 나머지는 빈 슬롯으로 10칸을 채운다.
func _refresh_sidebar() -> void:
	if _roster_box == null:
		return
	for child in _roster_box.get_children():
		child.queue_free()
	_sidebar_buttons.clear()

	var placed_set: Dictionary = {}
	for entry in GameState.board.iter_placed():
		placed_set[entry.unit] = true

	# 미배치 유닛만.
	var unplaced: Array[OwnedUnit] = []
	for owned: OwnedUnit in GameState.run.owned_units:
		if not placed_set.has(owned):
			unplaced.append(owned)

	# 최소 10칸(2×5). 미배치가 10을 초과하면 그만큼 칸이 늘어난다.
	var total: int = maxi(ROSTER_MAX, unplaced.size())
	for i in total:
		if i < unplaced.size():
			_roster_box.add_child(_make_roster_chip(unplaced[i]))
		else:
			_roster_box.add_child(_make_empty_slot())


## 미배치 유닛 칩 — 전투가능하면 드래그 소스, 부상/사망이면 비활성.
func _make_roster_chip(owned: OwnedUnit) -> Button:
	var chip := Button.new()
	chip.custom_minimum_size = ROSTER_SLOT_SIZE
	chip.clip_text = true
	chip.add_theme_font_size_override(&"font_size", 11)

	var badge: String = ""
	match owned.status:
		OwnedUnit.Status.INJURED:
			badge = "⚠"
		OwnedUnit.Status.DEAD:
			badge = "☠"
	var name_str: String = owned.source.display_name if owned.source else "?"
	chip.text = "%s %s" % [badge, name_str] if badge != "" else name_str

	if owned.is_deployable():
		chip.set_drag_forwarding(
			_sidebar_drag_get.bind(owned), Callable(), Callable()
		)
	else:
		chip.disabled = true

	_sidebar_buttons[owned] = chip
	return chip


## 빈 보관함 슬롯 — 드롭이 그리드로 통과하도록 mouse_filter=IGNORE.
func _make_empty_slot() -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = ROSTER_SLOT_SIZE
	slot.modulate = Color(1.0, 1.0, 1.0, 0.22)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


# ---------- 드래그앤드롭 (배치 전용 인터랙션) ----------
# 페이로드: {type:"owned_unit", owned, from_row, from_col}  ← 셀 출처
#           {type:"owned_unit", owned, from_sidebar:true}    ← 보관함 출처
# set_drag_forwarding 콜백 시그니처:
#   drag_get(at_pos) -> Variant / can_drop(at_pos, data) -> bool / drop(at_pos, data) -> void

func _make_drag_preview(text: String) -> Control:
	var preview := Panel.new()
	preview.custom_minimum_size = CELL_SIZE
	preview.modulate = Color(0.75, 0.9, 1.0, 0.9)
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override(&"font_size", 10)
	lbl.text = text
	preview.add_child(lbl)
	return preview


func _cell_drag_get(_at_pos: Vector2, row: int, col: int) -> Variant:
	var owned: OwnedUnit = GameState.board.get_unit(row, col) as OwnedUnit
	if owned == null:
		return null
	var name_str: String = owned.source.display_name if owned.source else "?"
	var src_btn: Button = _player_cell_buttons.get(Vector2i(row, col))
	if src_btn != null:
		src_btn.set_drag_preview(_make_drag_preview(name_str))
	return {
		"type": "owned_unit",
		"owned": owned,
		"from_row": row,
		"from_col": col,
	}


func _sidebar_drag_get(_at_pos: Vector2, owned: OwnedUnit) -> Variant:
	if owned == null or not owned.is_deployable():
		return null
	var name_str: String = owned.source.display_name if owned.source else "?"
	var src_btn: Button = _sidebar_buttons.get(owned)
	if src_btn != null:
		src_btn.set_drag_preview(_make_drag_preview(name_str))
	return {
		"type": "owned_unit",
		"owned": owned,
		"from_sidebar": true,
	}


func _cell_drag_can_drop(_at_pos: Vector2, data: Variant, row: int, col: int) -> bool:
	if not (data is Dictionary) or data.get("type", "") != "owned_unit":
		return false
	# 같은 셀 = no-op
	if data.get("from_row", -99) == row and data.get("from_col", -99) == col:
		return false
	# 빈 셀에만 (스왑은 후속)
	return GameState.board.get_unit(row, col) == null


func _cell_drag_drop(_at_pos: Vector2, data: Variant, row: int, col: int) -> void:
	var owned: OwnedUnit = data.get("owned") as OwnedUnit
	if owned == null:
		return
	# 셀 출처면 원래 자리 비움. 보관함 출처면 비울 게 없음(배치 시 자동으로 보관함에서 빠짐).
	var from_row: int = data.get("from_row", -1)
	var from_col: int = data.get("from_col", -1)
	if from_row >= 0 and from_col >= 0:
		GameState.board.remove_unit(from_row, from_col)
	GameState.board.place_unit(row, col, owned)
	_refresh_player_grid()
	_refresh_sidebar()


## 보관함 드롭 — 보드 셀에서 끌어온 유닛을 회수 (보관함 출처는 무시).
func _sidebar_can_drop(_at_pos: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or data.get("type", "") != "owned_unit":
		return false
	return int(data.get("from_row", -1)) >= 0


func _sidebar_drop(_at_pos: Vector2, data: Variant) -> void:
	var from_row: int = data.get("from_row", -1)
	var from_col: int = data.get("from_col", -1)
	if from_row >= 0 and from_col >= 0:
		GameState.board.remove_unit(from_row, from_col)
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

	# ── ItemEffect 1차 소비: effect_type별 max만 살림 (battle-flow.md §3) ──
	var item_effects: Array[ItemEffect] = ItemEffectApplier.consolidate(_slot_items)

	# 플레이어 시너지 룰 = 활성 룰 + FAKE_SYNERGY 가상 룰
	var effective_rules: Array[SynergyRule] = GameState.run.active_rules.duplicate()
	for fr in ItemEffectApplier.collect_fake_rules(item_effects):
		effective_rules.append(fr)

	# 플레이어 측: 시너지 + ItemEffect STAT_BOOST 적용 후 빌드
	var player_stats: Array[ComputedStats] = []
	var player_owned: Array[OwnedUnit] = []
	var player_grid: Array[Vector2i] = []
	var computed: Dictionary = SynergyEngine.compute(GameState.board, effective_rules)
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

	# TEMP_UNIT 효과로 추가 유닛 보드에 끼움 (전투 종료 후 폐기)
	for spec in ItemEffectApplier.collect_temp_units(item_effects):
		var t_owned: OwnedUnit = spec["owned"]
		if t_owned == null or t_owned.source == null:
			continue
		var t_stats: ComputedStats = ComputedStats.from_base(t_owned.source)
		player_stats.append(t_stats)
		player_owned.append(t_owned)
		player_grid.append(Vector2i(spec["row"], spec["col"]))

	ItemEffectApplier.apply_to_player(player_stats, player_owned, item_effects)

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
	ItemEffectApplier.apply_to_enemy(enemy_stats, _enemy_units_list, item_effects)
	var enemy_grid: Array[Vector2i] = []
	for entry in _enemy_board.iter_placed():
		enemy_grid.append(Vector2i(entry.row, entry.col))

	# Combat-time 적 시너지 룰만 분리 (DEATH_TRIGGER / HP_THRESHOLD / NUMBER_ADVANTAGE).
	var combat_rules: Array[EnemySynergyRule] = []
	for rule in _encounter_template.rules:
		if rule != null and not rule.is_pre_battle():
			combat_rules.append(rule)

	print("[BattleScreen] BATTLE start — player=%d enemies=%d items=%d combat_rules=%d" % [
		player_stats.size(), enemy_stats.size(), item_effects.size(), combat_rules.size()
	])
	_combat_manager.start_battle(
		player_stats, player_owned, enemy_stats, player_grid, enemy_grid, combat_rules
	)

	# SHIELD 효과 — 스폰된 player CombatUnit에 target_filter_tag 매칭해 부여.
	for shield_spec in ItemEffectApplier.collect_shields(item_effects):
		var tag: StringName = shield_spec["filter_tag"]
		var amount: float = shield_spec["amount"]
		for u in _combat_manager.player_units():
			if tag == &"" or _player_matches_filter(u, tag):
				u.shield += amount


## ItemEffect.target_filter_tag로 player CombatUnit 필터링.
## CombatUnit.stats.source가 UnitData면 has_type 검사.
func _player_matches_filter(unit: CombatUnit, tag: StringName) -> bool:
	if unit == null or unit.stats == null:
		return false
	var src: Resource = unit.stats.source
	if src is UnitData:
		return (src as UnitData).has_type(tag)
	return false


## 폴더의 0.png..N.png 를 SpriteFrames("default" 루프 애니메이션)으로 빌드. 결과 캐시.
func _get_sprite_frames(dir_path: String) -> SpriteFrames:
	if _sprite_frames_cache.has(dir_path):
		return _sprite_frames_cache[dir_path]
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", SPRITE_ANIM_FPS)
	frames.set_animation_loop(&"default", true)
	var i: int = 0
	while true:
		var p: String = "%s%d.png" % [dir_path, i]
		if not ResourceLoader.exists(p):
			break
		var tex: Texture2D = load(p) as Texture2D
		if tex == null:
			break
		frames.add_frame(&"default", tex)
		i += 1
	_sprite_frames_cache[dir_path] = frames
	return frames


func _on_unit_spawned(unit: CombatUnit) -> void:
	# 시각: 애니메이션 스프라이트 (플레이어=전사 / 적=슬라임)
	var dir_path: String = PLAYER_SPRITE_DIR if unit.team == CombatUnit.Team.PLAYER else ENEMY_SPRITE_DIR
	var is_player: bool = unit.team == CombatUnit.Team.PLAYER
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = _get_sprite_frames(dir_path)
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 픽셀아트 크리스프
	if sprite.sprite_frames.get_frame_count(&"default") > 0:
		sprite.play(&"default")
	unit.add_child(sprite)

	# 방향: 초기엔 상대 진영을 향하고, 이후 이동 방향(target)에 맞춰 동적 갱신.
	var base_left: bool = PLAYER_SPRITE_FACES_LEFT if is_player else ENEMY_SPRITE_FACES_LEFT
	var init_face_left: bool = not is_player  # 플레이어는 오른쪽, 적은 왼쪽을 봄
	sprite.flip_h = (init_face_left != base_left)
	unit.facing_changed.connect(func(face_left: bool) -> void:
		sprite.flip_h = (face_left != base_left)
	)

	# HP 바 — ColorRect 2장. 스프라이트 상단(= -SPRITE_DISPLAY_PX/2) 위로 띄움.
	var sprite_half: float = SPRITE_DISPLAY_PX * 0.5
	var bar_top: float = -sprite_half - HP_BAR_GAP - HP_BAR_H
	var bar_pos := Vector2(-HP_BAR_W * 0.5, bar_top)

	var hp_bg := ColorRect.new()
	hp_bg.name = "HpBg"
	hp_bg.size = Vector2(HP_BAR_W, HP_BAR_H)
	hp_bg.position = bar_pos
	hp_bg.color = Color(0.06, 0.04, 0.03, 0.7)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit.add_child(hp_bg)

	var max_hp: float = maxf(unit.stats.max_hp, 0.001)
	# 초기 채움 = 현재 HP 비율. carry-over로 깎인 HP가 전투 시작 시 바에 반영됨.
	# (이전엔 항상 풀 너비로 만들고 damaged 때만 줄여서, 깎인 채 시작해도 꽉 차 보였음)
	var init_ratio: float = clampf(unit.current_hp / max_hp, 0.0, 1.0)

	var hp_fill := ColorRect.new()
	hp_fill.name = "HpFill"
	hp_fill.size = Vector2(HP_BAR_W * init_ratio, HP_BAR_H)
	hp_fill.position = bar_pos
	hp_fill.color = Color(0.42, 0.62, 0.30) if unit.team == CombatUnit.Team.PLAYER else Color(0.78, 0.20, 0.16)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit.add_child(hp_fill)

	# Settings: ON_HOVER 모드는 평소 숨김 (hover 연동은 후속)
	if Settings.hp_bar_mode == Settings.HpBarMode.ON_HOVER:
		hp_bg.visible = false
		hp_fill.visible = false

	# 매 프레임 갱신 대상으로 등록 (damaged 신호에 의존하지 않음 — 회복도 반영).
	_live_bars.append({"unit": unit, "fill": hp_fill, "max_hp": max_hp})

	unit.died.connect(func(_u: CombatUnit) -> void:
		sprite.modulate.a = 0.25
		sprite.stop()
		hp_bg.visible = false
		hp_fill.visible = false
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
