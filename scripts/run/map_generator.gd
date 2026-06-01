class_name MapGenerator
extends RefCounted

## depth별 lane 수를 받아 가변 너비 맵을 생성한다.
## 시작(depth 0)과 보스(마지막 depth)는 항상 1 lane으로 강제.
## 인접 layer 간 공간 근접도 기반으로 1-2 엣지를 연결하고 고아 노드를 보장한다.
##
## 예시 패턴 [1, 2, 1, 3, 2, 1]:
##   depth 0 = 1 node (start, BATTLE)
##   depth 1 = 2 nodes (랜덤 kind)
##   depth 2 = 1 node (랜덤 kind)
##   depth 3 = 3 nodes (랜덤 kind)
##   depth 4 = 2 nodes (랜덤 kind)
##   depth 5 = 1 node (BOSS)
##
## 시작에 거미줄 같은 구조 X — depth당 lane이 적고 (1~3) 인접 거리 가까운 노드만 연결.

const DEFAULT_LANES_PATTERN: Array[int] = [1, 2, 1, 3, 2, 1]


static func generate(rng: RandomNumberGenerator,
		lanes_per_depth: Array[int] = DEFAULT_LANES_PATTERN) -> Array[MapNode]:
	var pattern: Array[int] = _normalize_pattern(lanes_per_depth)
	var nodes: Array[MapNode] = []
	var layer_starts: Array[int] = []
	var total_depth: int = pattern.size()

	# 1) 노드 생성
	for d in total_depth:
		layer_starts.append(nodes.size())
		var width: int = pattern[d]
		for l in width:
			var n := MapNode.new()
			n.depth = d
			n.lane = l
			# 마지막 depth는 BOSS 고정. 그 외는 _pick_kind.
			if d == total_depth - 1:
				n.kind = MapNode.Kind.BOSS
			else:
				n.kind = _pick_kind(rng, d, total_depth)
			nodes.append(n)

	# 2) 인접 layer 간 엣지 연결
	for d in range(total_depth - 1):
		_connect_layers(
			nodes,
			layer_starts[d], pattern[d],
			layer_starts[d + 1], pattern[d + 1],
			rng,
		)

	return nodes


## 첫 depth와 마지막 depth는 반드시 1 lane (시작/보스 단독).
static func _normalize_pattern(lanes_per_depth: Array[int]) -> Array[int]:
	var pattern: Array[int] = lanes_per_depth.duplicate() if not lanes_per_depth.is_empty() else DEFAULT_LANES_PATTERN.duplicate()
	if pattern[0] != 1:
		pattern.insert(0, 1)
	if pattern[pattern.size() - 1] != 1:
		pattern.append(1)
	return pattern


## src layer의 각 노드를 dst layer의 1-2개 노드에 연결. 공간 근접도(정규화 lane 위치)
## 기준으로 가장 가까운 dst부터 선택. 고아 dst(들어오는 엣지 0개)는 임의 src에서 보강.
static func _connect_layers(nodes: Array[MapNode],
		src_start: int, src_w: int,
		dst_start: int, dst_w: int,
		rng: RandomNumberGenerator) -> void:
	var reached: Dictionary = {}  ## dst global idx -> bool
	for j in dst_w:
		reached[dst_start + j] = false

	for i in src_w:
		var src_idx: int = src_start + i
		var src_norm: float = (float(i) + 0.5) / float(src_w)
		# dst 인덱스를 src 정규화 위치 기준 거리 순으로 정렬
		var sorted_dsts: Array = []
		for j in dst_w:
			var d_norm: float = (float(j) + 0.5) / float(dst_w)
			sorted_dsts.append({"idx": dst_start + j, "dist": absf(d_norm - src_norm)})
		sorted_dsts.sort_custom(func(a, b): return a["dist"] < b["dist"])

		# 1~2개 엣지 (src 폭과 dst 폭 모두 작으면 1만)
		var max_edges: int = mini(2, dst_w)
		var n_edges: int = rng.randi_range(1, max_edges)
		for k in n_edges:
			var dst_idx: int = sorted_dsts[k]["idx"]
			if not nodes[src_idx].next_indices.has(dst_idx):
				nodes[src_idx].next_indices.append(dst_idx)
			reached[dst_idx] = true

	# 고아 dst 보강: 들어오는 엣지가 없는 dst에 임의 src에서 엣지 추가
	for dst_idx_var in reached.keys():
		var dst_idx: int = dst_idx_var
		if reached[dst_idx]:
			continue
		var pick: int = src_start + (rng.randi() % src_w)
		if not nodes[pick].next_indices.has(dst_idx):
			nodes[pick].next_indices.append(dst_idx)


static func _pick_kind(rng: RandomNumberGenerator, d: int, total_depth: int) -> MapNode.Kind:
	# 시작 depth는 학습 편의를 위해 BATTLE 고정.
	if d == 0:
		return MapNode.Kind.BATTLE
	# 보스 직전(들어가기 전 회복 기회) — REST 가중치 ↑
	if d == total_depth - 2:
		if rng.randf() < 0.45:
			return MapNode.Kind.REST
	var roll: float = rng.randf()
	if roll < 0.55:
		return MapNode.Kind.BATTLE
	if roll < 0.70:
		return MapNode.Kind.ELITE
	if roll < 0.82:
		return MapNode.Kind.SHOP
	if roll < 0.92:
		return MapNode.Kind.EVENT
	if roll < 0.97:
		return MapNode.Kind.REST
	return MapNode.Kind.TREASURE
