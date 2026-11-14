class_name IslandNavigation
extends RefCounted
## Authored, walkable island paths. Keep guidance out of buildings and over the bridge.
const POINTS := [Vector3(0, 0, 29), Vector3(-15, 0, 12), Vector3(15, 0, 12), Vector3(23, 0, 12), Vector3(23, 0, -15), Vector3(20, 0, -15), Vector3(15, 0, -15), Vector3(-6, 0, -15), Vector3(-15, 0, -15), Vector3(0, 0, -30), Vector3(20, 0, -18), Vector3(25, 0, -18), Vector3(25, 0, -21.35)]
const LINKS := [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [7, 8], [7, 9], [5, 10], [10, 11], [11, 12]]
const DESTINATIONS := [1, 2, 6, 8, 9]
var route: Array[Vector3] = []
var current_stage: int = -1

func reset() -> void:
	current_stage = -1
	route.clear()

func next_point(from: Vector3, stage: int) -> Vector3:
	if stage != current_stage:
		current_stage = stage
		route = make_route(from, stage)
	while route.size() > 1 and Vector2(from.x - route[0].x, from.z - route[0].z).length() < 1.2:
		route.pop_front()
	return route[0] if not route.is_empty() else POINTS[DESTINATIONS[stage]]

func make_route(from: Vector3, stage: int) -> Array[Vector3]:
	var start := 0
	for i in range(POINTS.size()):
		if from.distance_squared_to(POINTS[i]) < from.distance_squared_to(POINTS[start]):
			start = i
	var goal: int = DESTINATIONS[clampi(stage, 0, 4)]
	var costs: Dictionary = {start: 0.0}
	var previous: Dictionary = {}
	var remaining: Array[int] = []
	for i in range(POINTS.size()):
		remaining.append(i)
	while not remaining.is_empty():
		var node: int = remaining[0]
		for candidate in remaining:
			if float(costs.get(candidate, INF)) < float(costs.get(node, INF)):
				node = candidate
		remaining.erase(node)
		if node == goal:
			break
		for link in LINKS:
			var neighbor: int = link[1] if link[0] == node else (link[0] if link[1] == node else -1)
			if neighbor < 0 or not neighbor in remaining:
				continue
			var cost: float = float(costs.get(node, INF)) + POINTS[node].distance_to(POINTS[neighbor])
			if cost < float(costs.get(neighbor, INF)):
				costs[neighbor] = cost
				previous[neighbor] = node
	var result: Array[Vector3] = [POINTS[goal]]
	var cursor := goal
	while previous.has(cursor):
		cursor = int(previous[cursor])
		result.push_front(POINTS[cursor])
	return result
