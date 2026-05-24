class_name MapGenerator
extends RefCounted

## Generates a Slay-the-Spire-shaped node map: `depth` columns wide, `lanes`
## tall, with random forward edges so the player has a few path choices each
## step. The graph is intentionally simple — a real generator would shape
## node-kind distribution, force shops at certain depths, etc. That's left
## as iteration once gameplay is wired up.


static func generate(rng: RandomNumberGenerator, depth: int = 12, lanes: int = 4) -> Array[MapNode]:
	var nodes: Array[MapNode] = []
	var index_at: Dictionary = {}  ## Vector2i(depth, lane) -> array index

	for d in depth:
		for l in lanes:
			var n := MapNode.new()
			n.depth = d
			n.lane = l
			n.kind = _pick_kind(rng, d, depth)
			index_at[Vector2i(d, l)] = nodes.size()
			nodes.append(n)

	for d in depth - 1:
		for l in lanes:
			var here_idx: int = index_at[Vector2i(d, l)]
			var here: MapNode = nodes[here_idx]
			var edges: int = rng.randi_range(1, 2)
			var candidates: Array[int] = []
			for offset: int in [-1, 0, 1]:
				var nl: int = l + offset
				if nl >= 0 and nl < lanes:
					candidates.append(nl)
			candidates.shuffle()
			for i in min(edges, candidates.size()):
				var target_idx: int = index_at[Vector2i(d + 1, candidates[i])]
				if not here.next_indices.has(target_idx):
					here.next_indices.append(target_idx)

	# Boss column: collapse final layer into a single boss node by rewiring
	# the second-to-last column to a single lane.
	var boss := MapNode.new()
	boss.kind = MapNode.Kind.BOSS
	boss.depth = depth
	boss.lane = lanes / 2
	var boss_idx: int = nodes.size()
	nodes.append(boss)
	for l in lanes:
		var last_col_idx: int = index_at[Vector2i(depth - 1, l)]
		nodes[last_col_idx].next_indices = [boss_idx]

	return nodes


static func _pick_kind(rng: RandomNumberGenerator, d: int, total_depth: int) -> MapNode.Kind:
	if d == 0:
		return MapNode.Kind.BATTLE
	if d == total_depth - 2:
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
