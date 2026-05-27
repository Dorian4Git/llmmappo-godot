extends Node2D
class_name MARLEnvironment

const MAX_STEPS = 500
var current_step = 0
const RENDER_SCALE = 10.0 
const GRID_LIMIT = 60.0

enum Actions { UP, DOWN, LEFT, RIGHT, INTERACT }

var zone_wood_pos = Vector2(10, 10)
var zone_stone_pos = Vector2(50, 10)
var zone_workbench_pos = Vector2(30, 30)
var zone_gold_pos = Vector2(30, 50)

var obstacles = [
	Rect2(20, 20, 20, 2), 
	Rect2(20, 35, 2, 15), 
	Rect2(40, 35, 2, 15)
]

var wood_collected = false
var stone_collected = false
var pickaxe_crafted = false
var gold_mined = false

var agents = [
	{"id": 0, "pos": Vector2(5, 5), "color": Color.CYAN, "inventory": {"wood": 0, "stone": 0, "pickaxe": 0}, "current_action": 0, "last_reward": 0.0},
	{"id": 1, "pos": Vector2(55, 5), "color": Color.MAGENTA, "inventory": {"wood": 0, "stone": 0, "pickaxe": 0}, "current_action": 0, "last_reward": 0.0}
]

var needs_reset = false

func _ready():
	reset()

# ---------------------------------------------------------
# The Physics Engine Loop (Driven by PyTorch via Sync)
# ---------------------------------------------------------
func _physics_process(_delta):
	var agent_wants_reset = false
	var a0_needs = false
	var a1_needs = false
	if has_node("Agent0/AIController2D"):
		a0_needs = get_node("Agent0/AIController2D").needs_reset
		if a0_needs: agent_wants_reset = true
	if has_node("Agent1/AIController2D"):
		a1_needs = get_node("Agent1/AIController2D").needs_reset
		if a1_needs: agent_wants_reset = true

	if needs_reset or agent_wants_reset:
		reset()
		return

	current_step += 1
	var step_penalty = -0.01
	
	for i in range(agents.size()):
		_apply_movement(agents[i], agents[i].current_action)
		agents[i].last_reward += step_penalty + _apply_interaction(agents[i], agents[i].current_action)

	if gold_mined or current_step >= MAX_STEPS:
		needs_reset = true
		
	queue_redraw()

# ---------------------------------------------------------
# Controller Interface API
# ---------------------------------------------------------
func set_agent_action(agent_id: int, action: int):
	agents[agent_id].current_action = action

func get_agent_reward(agent_id: int) -> float:
	var r = agents[agent_id].last_reward
	agents[agent_id].last_reward = 0.0
	return r

func is_env_done() -> bool:
	return needs_reset

func get_agent_obs(agent_id: int) -> Array:
	# Godot RL requires a 1D float array for standard observations.
	# We flatten the spatial data and boolean flags.
	var obs = []
	for a in agents:
		obs.append(a.pos.x)
		obs.append(a.pos.y)
	
	obs.append(1.0 if wood_collected else 0.0)
	obs.append(1.0 if stone_collected else 0.0)
	obs.append(1.0 if pickaxe_crafted else 0.0)
	obs.append(1.0 if gold_mined else 0.0)
	
	# Append one-hot agent identifier to allow policy differentiation
	if agent_id == 0:
		obs.append(1.0)
		obs.append(0.0)
	else:
		obs.append(0.0)
		obs.append(1.0)
		
	return obs

# ---------------------------------------------------------
# Core MDP Mechanics & Rendering
# ---------------------------------------------------------
func reset():
	current_step = 0
	wood_collected = false
	stone_collected = false
	pickaxe_crafted = false
	gold_mined = false
	needs_reset = false
	
	if has_node("Agent0/AIController2D"):
		get_node("Agent0/AIController2D").reset()
	if has_node("Agent1/AIController2D"):
		get_node("Agent1/AIController2D").reset()
	
	# Randomize starting positions within role-appropriate regions.
	# A0 (Lumberjack) spawns near the Wood zone [10,10].
	# A1 (Miner)      spawns near the Stone zone [50,10].
	# This makes the Workbench 'closest agent' decision genuinely dynamic:
	# the LLM reads actual positions; the cache always picks A0 (sub-optimal ~50%).
	agents[0].pos = Vector2(randi_range(2, 18), randi_range(2, 18))
	agents[1].pos = Vector2(randi_range(42, 58), randi_range(2, 18))
	
	agents[0].inventory = {"wood": 0, "stone": 0, "pickaxe": 0}
	agents[1].inventory = {"wood": 0, "stone": 0, "pickaxe": 0}
	
	for a in agents:
		a.last_reward = 0.0
	queue_redraw()

func _apply_movement(agent: Dictionary, action: int):
	var step_size = 1.0
	var next_pos = agent.pos

	match action:
		Actions.UP: next_pos.y -= step_size
		Actions.DOWN: next_pos.y += step_size
		Actions.LEFT: next_pos.x -= step_size
		Actions.RIGHT: next_pos.x += step_size
	
	if next_pos.x < 0 or next_pos.x > GRID_LIMIT or next_pos.y < 0 or next_pos.y > GRID_LIMIT: return 
	for obs in obstacles:
		if obs.has_point(next_pos): return 

	agent.pos = next_pos

func _apply_interaction(agent: Dictionary, action: int) -> float:
	var reward = 0.0
	if action != Actions.INTERACT: return reward
	var dist_threshold = 3.0
	
	if not wood_collected and agent.pos.distance_to(zone_wood_pos) < dist_threshold:
		if agent.id == 0: # Only Agent 0 (Lumberjack) can collect Wood
			agent.inventory.wood += 1
			wood_collected = true
			reward += 2.0 # Milestone reward
	elif not stone_collected and agent.pos.distance_to(zone_stone_pos) < dist_threshold:
		if agent.id == 1: # Only Agent 1 (Miner) can collect Stone
			agent.inventory.stone += 1
			stone_collected = true
			reward += 2.0 # Milestone reward
	elif wood_collected and stone_collected and not pickaxe_crafted and agent.pos.distance_to(zone_workbench_pos) < dist_threshold:
		# Either agent can use the Workbench
		agent.inventory.pickaxe += 1
		pickaxe_crafted = true
		reward += 3.0 # Milestone reward
	elif pickaxe_crafted and not gold_mined and agent.pos.distance_to(zone_gold_pos) < dist_threshold:
		if agent.id == 1: # Only Agent 1 (Miner) can mine Gold
			gold_mined = true
			reward += 10.0 
	return reward

func _draw():
	# Draw Obstacles
	for obs in obstacles:
		var render_rect = Rect2(obs.position * RENDER_SCALE, obs.size * RENDER_SCALE)
		draw_rect(render_rect, Color.DARK_SLATE_GRAY, true)

	var zone_size = Vector2(30, 30)
	var offset = zone_size / 2.0
	var default_font = ThemeDB.fallback_font
	
	# Wood Zone (Saddle Brown -> Dark Gray when collected)
	var w_color = Color.SADDLE_BROWN if not wood_collected else Color.DARK_GRAY
	var w_rect = Rect2((zone_wood_pos * RENDER_SCALE) - offset, zone_size)
	draw_rect(w_rect, w_color, true)
	draw_rect(w_rect, Color.BLACK, false, 1.5)
	if default_font:
		draw_string(default_font, (zone_wood_pos * RENDER_SCALE) + Vector2(-15, -18), "Wood", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 11, Color.WHITE)
		if wood_collected:
			draw_string(default_font, (zone_wood_pos * RENDER_SCALE) + Vector2(-15, 8), "(Done)", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 9, Color.LIGHT_GRAY)
	
	# Stone Zone (Light Slate Gray -> Dark Gray when collected)
	var s_color = Color.LIGHT_SLATE_GRAY if not stone_collected else Color.DARK_GRAY
	var s_rect = Rect2((zone_stone_pos * RENDER_SCALE) - offset, zone_size)
	draw_rect(s_rect, s_color, true)
	draw_rect(s_rect, Color.BLACK, false, 1.5)
	if default_font:
		draw_string(default_font, (zone_stone_pos * RENDER_SCALE) + Vector2(-15, -18), "Stone", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 11, Color.WHITE)
		if stone_collected:
			draw_string(default_font, (zone_stone_pos * RENDER_SCALE) + Vector2(-15, 8), "(Done)", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 9, Color.LIGHT_GRAY)
	
	# Workbench Zone (Medium Purple when active -> Dark Gray when pickaxe crafted)
	var wb_active = wood_collected and stone_collected and not pickaxe_crafted
	var wb_color = Color.MEDIUM_PURPLE if wb_active else Color.DARK_GRAY
	var wb_rect = Rect2((zone_workbench_pos * RENDER_SCALE) - offset, zone_size)
	draw_rect(wb_rect, wb_color, true)
	draw_rect(wb_rect, Color.BLACK, false, 1.5)
	if default_font:
		draw_string(default_font, (zone_workbench_pos * RENDER_SCALE) + Vector2(-25, -18), "Workbench", HORIZONTAL_ALIGNMENT_CENTER, 50.0, 11, Color.WHITE)
		if pickaxe_crafted:
			draw_string(default_font, (zone_workbench_pos * RENDER_SCALE) + Vector2(-25, 8), "(Done)", HORIZONTAL_ALIGNMENT_CENTER, 50.0, 9, Color.LIGHT_GRAY)
		elif wb_active:
			draw_string(default_font, (zone_workbench_pos * RENDER_SCALE) + Vector2(-25, 8), "(Ready)", HORIZONTAL_ALIGNMENT_CENTER, 50.0, 9, Color.YELLOW)
	
	# Gold Zone (Gold when active -> Dark Gray when mined)
	var g_active = pickaxe_crafted and not gold_mined
	var g_color = Color.GOLD if g_active else Color.DARK_GRAY
	var g_rect = Rect2((zone_gold_pos * RENDER_SCALE) - offset, zone_size)
	draw_rect(g_rect, g_color, true)
	draw_rect(g_rect, Color.BLACK, false, 1.5)
	if default_font:
		draw_string(default_font, (zone_gold_pos * RENDER_SCALE) + Vector2(-15, -18), "Gold", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 11, Color.WHITE)
		if gold_mined:
			draw_string(default_font, (zone_gold_pos * RENDER_SCALE) + Vector2(-15, 8), "(Mined)", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 9, Color.GREEN)
		elif g_active:
			draw_string(default_font, (zone_gold_pos * RENDER_SCALE) + Vector2(-15, 8), "(Ready)", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 9, Color.YELLOW)

	# Draw Agents
	for agent in agents:
		draw_circle(agent.pos * RENDER_SCALE, 8.0, agent.color)
		draw_circle(agent.pos * RENDER_SCALE, 8.0, Color.BLACK, false, 1.5)
		if default_font:
			draw_string(default_font, agent.pos * RENDER_SCALE + Vector2(-15, -12), "A" + str(agent.id), HORIZONTAL_ALIGNMENT_CENTER, 30.0, 9, Color.BLACK)
