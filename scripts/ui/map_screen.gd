extends Control

## StS식 노드 맵 화면. GameState.run.nodes를 받아서 격자로 배치하고
## 도달 가능한 노드를 버튼으로 그린다. Fog of War: revealed_nodes에 있는 노드만
## kind 아이콘 표시, 나머지는 "?".

const NODE_SIZE: Vector2 = Vector2(56, 56)
## 컴팩트 레이아웃 — 노드 사이 절대 간격 고정. 화면을 꽉 채우지 않고 중앙 배치.
const X_STEP: float = 120.0
const Y_STEP: float = 90.0
## 화면 가장자리 최소 여백 (info 라벨/뒤로 가기 버튼이 자리잡을 영역 확보).
const MIN_MARGIN: Vector2 = Vector2(120, 100)
const EDGE_COLOR_NORMAL: Color = Color(0.35, 0.35, 0.45)
const EDGE_COLOR_HIGHLIGHT: Color = Color(0.85, 0.75, 0.35)
const EDGE_WIDTH: float = 2.5

var _node_positions: Array[Vector2] = []
var _node_buttons: Array[Button] = []
var _info_label: Label
var _back_button: Button


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_widefield.jpg")
	if GameState.run == null:
		push_warning("[MapScreen] GameState.run is null — 메인 메뉴로 복귀")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	_build_chrome()
	GameState.node_entered.connect(_on_node_entered)
	resized.connect(_rebuild)
	_rebuild()


## 정보 라벨 + 메뉴로 돌아가기 버튼을 프로그래매틱하게 만든다.
## .tscn에 직접 추가해도 되지만 일단 코드로 — 다음 단계에서 통합할 예정.
func _build_chrome() -> void:
	_info_label = Label.new()
	_info_label.position = Vector2(16, 16)
	_info_label.add_theme_font_size_override(&"font_size", 18)
	add_child(_info_label)

	_back_button = Button.new()
	_back_button.text = "메뉴로"
	_back_button.position = Vector2(16, 56)
	_back_button.custom_minimum_size = Vector2(100, 32)
	_back_button.pressed.connect(_on_back_pressed)
	add_child(_back_button)


func _rebuild() -> void:
	for b in _node_buttons:
		b.queue_free()
	_node_buttons.clear()

	_node_positions = _compute_positions()
	var reachable: Array[int] = GameState.run.reachable_from_current()

	for i in GameState.run.nodes.size():
		var btn := Button.new()
		btn.text = _get_label(i)
		btn.custom_minimum_size = NODE_SIZE
		btn.size = NODE_SIZE
		btn.position = _node_positions[i] - NODE_SIZE * 0.5
		btn.disabled = not reachable.has(i)
		btn.pressed.connect(_on_node_pressed.bind(i))
		btn.tooltip_text = _tooltip_for(i)
		add_child(btn)
		_node_buttons.append(btn)

	_update_info()
	queue_redraw()


func _compute_positions() -> Array[Vector2]:
	# 각 depth의 lane 수를 먼저 집계.
	var lanes_at_depth: Dictionary = {}  ## depth -> count
	var max_depth: int = 0
	for n: MapNode in GameState.run.nodes:
		lanes_at_depth[n.depth] = lanes_at_depth.get(n.depth, 0) + 1
		if n.depth > max_depth:
			max_depth = n.depth

	# 맵 전체 박스 크기 (가로: depth 수 * X_STEP, 세로: 가장 넓은 depth 기준)
	var max_lanes_in_any_depth: int = 1
	for w in lanes_at_depth.values():
		if int(w) > max_lanes_in_any_depth:
			max_lanes_in_any_depth = int(w)

	var map_w: float = float(max_depth) * X_STEP
	var map_h: float = float(max_lanes_in_any_depth - 1) * Y_STEP

	# 화면 중앙 정렬 (단, 최소 여백 확보).
	var screen_size: Vector2 = size
	var origin_x: float = maxf((screen_size.x - map_w) * 0.5, MIN_MARGIN.x)
	var origin_y: float = maxf((screen_size.y - map_h) * 0.5, MIN_MARGIN.y)
	var origin: Vector2 = Vector2(origin_x, origin_y)
	var center_y: float = map_h * 0.5

	# 각 노드의 위치: depth → X, lane → 해당 depth 폭 안에서 세로 중앙 정렬.
	var positions: Array[Vector2] = []
	for n: MapNode in GameState.run.nodes:
		var w_here: int = int(lanes_at_depth.get(n.depth, 1))
		var y_offset: float
		if w_here == 1:
			y_offset = center_y
		else:
			# lane 0..w-1을 (w-1) 등간격으로 분배, 깊이 가운데(center_y)에 대칭.
			var span: float = float(w_here - 1) * Y_STEP
			y_offset = center_y - span * 0.5 + float(n.lane) * Y_STEP
		positions.append(origin + Vector2(float(n.depth) * X_STEP, y_offset))
	return positions


func _draw() -> void:
	if _node_positions.is_empty():
		return
	var reachable: Array[int] = GameState.run.reachable_from_current()
	var current: int = GameState.run.current_node_index

	for i in GameState.run.nodes.size():
		var n: MapNode = GameState.run.nodes[i]
		for j: int in n.next_indices:
			var highlight: bool = (i == current) and reachable.has(j)
			var color: Color = EDGE_COLOR_HIGHLIGHT if highlight else EDGE_COLOR_NORMAL
			var width: float = EDGE_WIDTH * 2.0 if highlight else EDGE_WIDTH
			draw_line(_node_positions[i], _node_positions[j], color, width)


func _get_label(index: int) -> String:
	var n: MapNode = GameState.run.nodes[index]
	if index == GameState.run.current_node_index:
		return "●"
	if not GameState.run.is_revealed(index):
		return "?"
	return _kind_symbol(n.kind)


func _kind_symbol(k: MapNode.Kind) -> String:
	match k:
		MapNode.Kind.BATTLE: return "전"
		MapNode.Kind.ELITE: return "엘"
		MapNode.Kind.SHOP: return "$"
		MapNode.Kind.REST: return "쉼"
		MapNode.Kind.EVENT: return "?!"
		MapNode.Kind.TREASURE: return "보"
		MapNode.Kind.BOSS: return "BOSS"
	return "?"


func _tooltip_for(index: int) -> String:
	var n: MapNode = GameState.run.nodes[index]
	if not GameState.run.is_revealed(index) and index != GameState.run.current_node_index:
		return "미지의 노드 (도착 시 공개)"
	return MapNode.Kind.keys()[n.kind]


func _on_node_pressed(index: int) -> void:
	if not GameState.enter_node(index):
		return
	var n: MapNode = GameState.run.nodes[index]
	print("[MapScreen] entered idx=%d kind=%s" % [index, MapNode.Kind.keys()[n.kind]])
	var dest: String = _scene_for_kind(n.kind)
	get_tree().change_scene_to_file(dest)


func _scene_for_kind(kind: MapNode.Kind) -> String:
	match kind:
		MapNode.Kind.BATTLE:
			return "res://scenes/battle_screen.tscn"
		MapNode.Kind.ELITE:
			return "res://scenes/elite_screen.tscn"
		MapNode.Kind.REST:
			return "res://scenes/rest_screen.tscn"
		MapNode.Kind.BOSS:
			return "res://scenes/boss_screen.tscn"
		MapNode.Kind.SHOP:
			return "res://scenes/shop_screen.tscn"
		MapNode.Kind.EVENT:
			return "res://scenes/event_screen.tscn"
		MapNode.Kind.TREASURE:
			return "res://scenes/treasure_screen.tscn"
	push_warning("[MapScreen] unhandled kind: %s" % MapNode.Kind.keys()[kind])
	return "res://scenes/map_screen.tscn"


func _on_node_entered(_index: int) -> void:
	_rebuild()


func _on_back_pressed() -> void:
	GameState.end_run(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _update_info() -> void:
	# 폐기된 RunState.health/max_health는 표시에서 제외 (R4 합의).
	var depth_now: int = 0
	if GameState.run.current_node_index >= 0:
		depth_now = GameState.run.nodes[GameState.run.current_node_index].depth
	_info_label.text = "Chapter %d   Gold: %d   Depth: %d" % [
		GameState.run.chapter,
		GameState.run.gold,
		depth_now,
	]
