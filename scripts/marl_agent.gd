extends AIController2D

# We define the agent's identity via an exported variable so we can set it in the editor
@export var agent_id: int = 0
var env_ref: Node2D

func _ready():
	env_ref = get_parent().get_parent()
	print("Agent ID: ", agent_id, " initialized with env_ref: ", env_ref)
	super._ready()

# ---------------------------------------------------------
# PyTorch Interface Methods (Strict Godot RL API)
# ---------------------------------------------------------
func get_obs() -> Dictionary:
	if env_ref == null:
		print("ERROR: env_ref is null in get_obs for agent: ", agent_id)
		return {"obs": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]}
	var obs_array = env_ref.get_agent_obs(agent_id)
	if obs_array == null:
		print("ERROR: get_agent_obs returned null for agent: ", agent_id)
		return {"obs": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]}
	return {"obs": obs_array}

func get_reward() -> float:
	if env_ref == null: return 0.0
	return env_ref.get_agent_reward(agent_id)

func get_done() -> bool:
	if env_ref == null: return true
	return env_ref.is_env_done()

func set_action(action: Dictionary) -> void:
	if env_ref == null: return
	env_ref.set_agent_action(agent_id, action["action"])

func get_action_space() -> Dictionary:
	# Tells PyTorch to create a discrete probability distribution of size 5
	return {
		"action": {"size": 5, "action_type": "discrete"}
	}
