extends Node

class_name NPCSpawner

const NpcType = GlobalGameState.NpcType
const SettlementType = GlobalGameState.SettlementType

# Building type to NPC type mappings
const BUILDING_NPC_TYPES = {
	GlobalGameState.BuildingType.HOUSE: [NpcType.PEASANT],
	GlobalGameState.BuildingType.TAVERN: [NpcType.PEASANT, NpcType.MERCHANT],
	GlobalGameState.BuildingType.SHOP: [NpcType.MERCHANT],
	GlobalGameState.BuildingType.MANOR: [NpcType.NOBLE],
	GlobalGameState.BuildingType.BARRACKS: [NpcType.SOLDIER],
	GlobalGameState.BuildingType.CHURCH: [NpcType.PEASANT],
	GlobalGameState.BuildingType.KEEP: [NpcType.SOLDIER, NpcType.NOBLE]
}

# NPC job assignments by type
const NPC_JOBS = {
	NpcType.PEASANT: ["farmer", "laborer", "servant"],
	NpcType.MERCHANT: ["shopkeeper", "trader", "innkeeper"],
	NpcType.SOLDIER: ["guard", "patrol", "watchman"],
	NpcType.NOBLE: ["lord", "administrator", "official"],
	NpcType.BANDIT: ["thief", "outlaw", "marauder"],
	NpcType.ANIMAL: ["wild", "stray", "pet"],
	NpcType.MONSTER: ["predator", "creature", "beast"]
}

# Workplace mappings for jobs
const JOB_WORKPLACES = {
	"farmer": GlobalGameState.BuildingType.HOUSE,
	"laborer": GlobalGameState.BuildingType.HOUSE,
	"servant": GlobalGameState.BuildingType.MANOR,
	"shopkeeper": GlobalGameState.BuildingType.SHOP,
	"trader": GlobalGameState.BuildingType.SHOP,
	"innkeeper": GlobalGameState.BuildingType.TAVERN,
	"guard": GlobalGameState.BuildingType.BARRACKS,
	"patrol": GlobalGameState.BuildingType.BARRACKS,
	"watchman": GlobalGameState.BuildingType.KEEP,
	"lord": GlobalGameState.BuildingType.MANOR,
	"administrator": GlobalGameState.BuildingType.KEEP,
	"official": GlobalGameState.BuildingType.KEEP,
	"thief": null, # No fixed workplace
	"outlaw": null,
	"marauder": null,
	"wild": null,
	"stray": null,
	"pet": GlobalGameState.BuildingType.HOUSE,
	"predator": null,
	"creature": null,
	"beast": null
}

# Reference to the NPC scene
var npc_scene: PackedScene
var rng: RandomNumberGenerator

func _init():
	rng = RandomNumberGenerator.new()
	rng.randomize()
	npc_scene = preload("res://scenes/npc.tscn") # Make sure this path is correct

func spawn_settlement_npcs(settlement_data: Dictionary, parent_node: Node2D) -> Array[Node]:
	var spawned_npcs: Array[Node] = []
	var settlement_type = settlement_data.get("type", SettlementType.TOWN)
	
	# Get NPC counts for this settlement type
	var npc_counts = GlobalGameState.settlement_npc_counts[settlement_type]
	print("Spawning NPCs for settlement type: ", settlement_type, " with counts: ", npc_counts)
	# Map to track building occupancy
	var building_occupancy = {}
	
	# Spawn NPCs for each type
	for npc_type in npc_counts:
		var count = npc_counts[npc_type]
		for _i in range(count):
			var npc = spawn_npc(npc_type, parent_node)
			if npc:
				# Assign home, job and route
				setup_npc_in_settlement(npc, npc_type, settlement_data, building_occupancy)
				spawned_npcs.append(npc)
	
	return spawned_npcs

func setup_npc_in_settlement(npc: Node, npc_type: GlobalGameState.NpcType, settlement_data: Dictionary, building_occupancy: Dictionary) -> void:
	var home_building = find_suitable_building(npc_type, settlement_data, GlobalGameState.BuildingType.HOUSE, building_occupancy)
	var job = assign_job(npc_type)
	var workplace_type = JOB_WORKPLACES.get(job)
	var workplace_building = {}
	
	if workplace_type != null:
		workplace_building = find_suitable_building(npc_type, settlement_data, workplace_type, building_occupancy)
	
	# If we couldn't find specific buildings, just use any suitable building
	if home_building.is_empty():
		home_building = find_suitable_building(npc_type, settlement_data)
	
	if workplace_building.is_empty() and workplace_type != null:
		workplace_building = find_suitable_building(npc_type, settlement_data)
	
	# Set home position
	if not home_building.is_empty():
		var home_pos = Vector2(
			home_building["pos"].x * GlobalGameState.TILE_SIZE,
			home_building["pos"].y * GlobalGameState.TILE_SIZE
		)
		npc.initialize(npc.get_parent(), home_pos)
		npc.home_position = home_pos
		
		# Update occupancy
		var building_id = home_building.get("id", "unknown")
		building_occupancy[building_id] = building_occupancy.get(building_id, 0) + 1
	else:
		# Fallback to random position
		npc.initialize(npc.get_parent(), Vector2.ZERO)
	
	# Set work position if available
	if not workplace_building.is_empty():
		var work_pos = Vector2(
			workplace_building["pos"].x * GlobalGameState.TILE_SIZE,
			workplace_building["pos"].y * GlobalGameState.TILE_SIZE
		)
		npc.work_position = work_pos
		
		# Update occupancy for workplace too
		var building_id = workplace_building.get("id", "unknown")
		building_occupancy[building_id] = building_occupancy.get(building_id, 0) + 1
	
	# Generate a patrol route for guards/soldiers
	if npc_type == NpcType.SOLDIER:
		generate_patrol_route(npc, settlement_data)
	
	# Set job-related properties
	setup_npc_job(npc, job, workplace_building, settlement_data)

func generate_patrol_route(npc: Node, settlement_data: Dictionary) -> void:
	# Create a patrol route if this is a guard/soldier
	var patrol_points = []
	var buildings = settlement_data.get("buildings", {})
	var center = settlement_data.get("center", Vector2(0, 0))
	
	# Option 1: Patrol around important buildings
	var important_buildings = []
	for building in buildings.values():
		var type = building.get("type")
		if type in [GlobalGameState.BuildingType.KEEP, GlobalGameState.BuildingType.SHOP,
				   GlobalGameState.BuildingType.TAVERN, GlobalGameState.BuildingType.CHURCH]:
			important_buildings.append(building)
	
	if important_buildings.size() >= 2:
		# Create patrol route between important buildings
		for i in range(min(4, important_buildings.size())):
			var building = important_buildings[i]
			var pos = Vector2(
				building["pos"].x,
				building["pos"].y
			)
			patrol_points.append(Vector2i(pos))
	else:
		# Option 2: Create a route around the settlement center
		for i in range(4):
			var angle = i * PI / 2 # 0, 90, 180, 270 degrees
			var distance = rng.randi_range(3, 6)
			var point = Vector2(center.x, center.y) + Vector2(cos(angle), sin(angle)) * distance
			patrol_points.append(Vector2i(point))
	
	# Store patrol route in the NPC's state data
	if patrol_points.size() > 0:
		npc.state_data["patrol_points"] = patrol_points
		npc.state_data["current_patrol_point"] = 0

func assign_job(npc_type: GlobalGameState.NpcType) -> String:
	var possible_jobs = NPC_JOBS.get(npc_type, ["none"])
	return possible_jobs[rng.randi() % possible_jobs.size()]

func setup_npc_job(npc: Node, job: String, _workplace: Dictionary, settlement_data: Dictionary) -> void:
	# Customize NPC based on job
	npc.npc_name = generate_name_for_job(job, npc.npc_type)
	
	# Set job-specific schedule
	var schedule = generate_schedule_for_job(job, npc.npc_type)
	if schedule.size() > 0:
		npc.schedule = schedule
	
	# Set work-related properties based on job
	match job:
		"shopkeeper", "trader":
			npc.can_trade = true
			npc.gold = rng.randi_range(50, 200)
			# Generate shop inventory
			for i in range(5 + rng.randi() % 10):
				npc._add_random_store_item()
		"innkeeper":
			npc.can_trade = true
			npc.gold = rng.randi_range(30, 100)
		"guard", "patrol", "watchman":
			# Set to patrol behavior
			npc.npc_properties[npc.npc_type]["behavior"] = "patrol"
		"lord", "administrator", "official":
			npc.gold = rng.randi_range(100, 500)
	
	# Set custom dialogue based on job
	setup_dialogue_for_job(npc, job, settlement_data)

func generate_name_for_job(job: String, npc_type: GlobalGameState.NpcType) -> String:
	var first_names = [
		"John", "Emma", "Bjorn", "Astrid", "Karim", "Leila", "Takeshi",
		"Mei", "Olga", "Diego", "Darius", "Lyra", "Marcus", "Sefa"
	]
	
	var last_names = [
		"Smith", "Andersen", "Al-Farsi", "Tanaka", "Chen", "Ivanov",
		"Rodriguez", "Okafor", "Singh", "Müller", "Blackwood", "Strongarm"
	]
	
	var titles = {
		"lord": ["Lord", "Lady", "Baron", "Baroness"],
		"administrator": ["Administrator", "Overseer", "Magistrate"],
		"official": ["Official", "Minister", "Councilor"],
		"guard": ["Guard", "Protector", "Sentinel"],
		"patrol": ["Watcher", "Sentinel", "Guardian"],
		"watchman": ["Watchman", "Sentinel", "Guardian"],
		"shopkeeper": ["Merchant", "Vendor", "Trader"],
		"trader": ["Trader", "Merchant", "Dealer"],
		"innkeeper": ["Innkeeper", "Host", "Proprietor"]
	}
	
	var first = first_names[rng.randi() % first_names.size()]
	var last = last_names[rng.randi() % last_names.size()]
	var npc_full_name = first + " " + last
	
	# Add title for certain jobs
	if job in titles:
		var title_options = titles[job]
		var title = title_options[rng.randi() % title_options.size()]
		
		if job in ["lord", "administrator", "official"]:
			npc_full_name = title + " " + npc_full_name
		else:
			npc_full_name = npc_full_name + " the " + title
	
	# For monsters and animals, use descriptive names
	if npc_type == NpcType.MONSTER:
		var monster_names = ["Grukk", "Skarr", "Thrag", "Morgath", "Krazak", "Dreadclaw"]
		npc_full_name = monster_names[rng.randi() % monster_names.size()]
	elif npc_type == NpcType.ANIMAL:
		var animal_names = ["Spot", "Rusty", "Swift", "Shadow", "Fang", "Whiskers"]
		var animal_types = ["Wolf", "Deer", "Fox", "Bear", "Cat", "Dog"]
		var animal_type = animal_types[rng.randi() % animal_types.size()]
		
		if rng.randf() < 0.3: # 30% chance for a pet name
			npc_full_name = animal_names[rng.randi() % animal_names.size()]
		else:
			npc_full_name = animal_type # Just the animal type
			
	return npc_full_name

func generate_schedule_for_job(job: String, npc_type: GlobalGameState.NpcType) -> Dictionary:
	var schedule = {}
	
	# Basic schedule template
	match job:
		"farmer", "laborer":
			schedule = {
				5: {"state": NPC.NPCState.WANDER, "location": "home", "duration": 1},
				6: {"state": NPC.NPCState.WORK, "location": "work", "duration": 6},
				12: {"state": NPC.NPCState.EAT, "location": "home", "duration": 1},
				13: {"state": NPC.NPCState.WORK, "location": "work", "duration": 6},
				19: {"state": NPC.NPCState.WANDER, "location": "town", "duration": 2},
				21: {"state": NPC.NPCState.SLEEP, "location": "home", "duration": 8}
			}
		"guard", "patrol", "watchman":
			# Guards work in shifts
			if rng.randf() < 0.5: # Day shift
				schedule = {
					5: {"state": NPC.NPCState.WANDER, "location": "home", "duration": 1},
					6: {"state": NPC.NPCState.PATROL, "location": "work", "duration": 12},
					18: {"state": NPC.NPCState.EAT, "location": "tavern", "duration": 2},
					20: {"state": NPC.NPCState.WANDER, "location": "town", "duration": 2},
					22: {"state": NPC.NPCState.SLEEP, "location": "home", "duration": 7}
				}
			else: # Night shift
				schedule = {
					17: {"state": NPC.NPCState.WANDER, "location": "home", "duration": 1},
					18: {"state": NPC.NPCState.PATROL, "location": "work", "duration": 12},
					6: {"state": NPC.NPCState.EAT, "location": "tavern", "duration": 2},
					8: {"state": NPC.NPCState.WANDER, "location": "town", "duration": 1},
					9: {"state": NPC.NPCState.SLEEP, "location": "home", "duration": 8}
				}
		"shopkeeper", "trader", "innkeeper":
			schedule = {
				7: {"state": NPC.NPCState.WANDER, "location": "home", "duration": 1},
				8: {"state": NPC.NPCState.WORK, "location": "work", "duration": 12},
				20: {"state": NPC.NPCState.EAT, "location": "home", "duration": 1},
				21: {"state": NPC.NPCState.WANDER, "location": "home", "duration": 1},
				22: {"state": NPC.NPCState.SLEEP, "location": "home", "duration": 9}
			}
		"lord", "administrator", "official":
			schedule = {
				8: {"state": NPC.NPCState.WANDER, "location": "home", "duration": 2},
				10: {"state": NPC.NPCState.WORK, "location": "work", "duration": 4},
				14: {"state": NPC.NPCState.EAT, "location": "home", "duration": 2},
				16: {"state": NPC.NPCState.WORK, "location": "work", "duration": 3},
				19: {"state": NPC.NPCState.WANDER, "location": "town", "duration": 3},
				22: {"state": NPC.NPCState.SLEEP, "location": "home", "duration": 10}
			}
		_: # Default schedule
			schedule = {
				7: {"state": NPC.NPCState.WANDER, "location": "home", "duration": 1},
				8: {"state": NPC.NPCState.WANDER, "location": "town", "duration": 4},
				12: {"state": NPC.NPCState.EAT, "location": "home", "duration": 1},
				13: {"state": NPC.NPCState.WANDER, "location": "town", "duration": 7},
				20: {"state": NPC.NPCState.WANDER, "location": "home", "duration": 2},
				22: {"state": NPC.NPCState.SLEEP, "location": "home", "duration": 9}
			}
	
	# Special case for non-civilized types
	if npc_type in [NpcType.ANIMAL, NpcType.MONSTER, NpcType.BANDIT]:
		schedule = {
			5: {"state": NPC.NPCState.SLEEP, "location": "home", "duration": 2},
			7: {"state": NPC.NPCState.WANDER, "location": "area", "duration": 5},
			12: {"state": NPC.NPCState.IDLE, "location": "area", "duration": 2},
			14: {"state": NPC.NPCState.WANDER, "location": "area", "duration": 7},
			21: {"state": NPC.NPCState.SLEEP, "location": "home", "duration": 8}
		}
	
	return schedule

func setup_dialogue_for_job(npc: Node, job: String, settlement_data: Dictionary) -> void:
	# Add job-specific dialogue options
	var settlement_name = settlement_data.get("name", "this settlement")
	
	# Skip for animals and monsters
	if npc.npc_type in [NpcType.ANIMAL, NpcType.MONSTER]:
		return
	
	# Add job-specific greeting
	if npc.dialogue_tree.has("ROOT"):
		match job:
			"farmer", "laborer":
				npc.dialogue_tree["ROOT"]["text"] = "Good day. I'm working the fields around " + settlement_name + "."
			"servant":
				npc.dialogue_tree["ROOT"]["text"] = "Greetings. I serve the noble household here in " + settlement_name + "."
			"shopkeeper":
				npc.dialogue_tree["ROOT"]["text"] = "Welcome to my shop! Looking to buy something?"
			"trader":
				npc.dialogue_tree["ROOT"]["text"] = "Hello there! I've got wares from all over, if you're interested."
			"innkeeper":
				npc.dialogue_tree["ROOT"]["text"] = "Welcome to my establishment! Can I get you something to drink?"
			"guard", "patrol", "watchman":
				npc.dialogue_tree["ROOT"]["text"] = "Halt there. All's well in " + settlement_name + " today?"
			"lord":
				npc.dialogue_tree["ROOT"]["text"] = "Yes? I am quite busy with affairs of state."
			"administrator", "official":
				npc.dialogue_tree["ROOT"]["text"] = "Welcome to " + settlement_name + ". What business brings you here?"
		
	# Add job-specific information dialogue
	if npc.dialogue_tree.has("INFO"):
		match job:
			"farmer", "laborer", "servant":
				npc.dialogue_tree["INFO"]["text"] = "What would you like to know about life in " + settlement_name + "?"
			"shopkeeper", "trader", "innkeeper":
				npc.dialogue_tree["INFO"]["text"] = "I hear all sorts of news from customers. What would you like to know?"
			"guard", "patrol", "watchman":
				npc.dialogue_tree["INFO"]["text"] = "I keep my eyes open while on duty. What do you want to know?"
			"lord", "administrator", "official":
				npc.dialogue_tree["INFO"]["text"] = "I oversee matters in " + settlement_name + ". What information do you seek?"
	
	# Add job-specific place description
	if npc.dialogue_tree.has("PLACE"):
		var description = settlement_name + " is "
		match settlement_data.get("type", SettlementType.TOWN):
			SettlementType.TOWN:
				description += "a bustling town with merchants and craftsfolk of various trades."
			SettlementType.CITY:
				description += "a proper city with many districts and people from all walks of life."
			_: # Default for any other settlement type
				description += "a small settlement where folks try to make a living as best they can."
		
		npc.dialogue_tree["PLACE"]["text"] = description

func spawn_wilderness_npcs(_area_size: Vector2i, parent_node: Node2D, wilderness_type: String = "normal") -> Array[Node]:
	var spawned_npcs: Array[Node] = []
	var spawn_types = []
	var spawn_counts = {}
	
	match wilderness_type:
		"normal":
			spawn_types = [NpcType.ANIMAL, NpcType.PEASANT, NpcType.BANDIT]
			spawn_counts = {
				NpcType.ANIMAL: rng.randi_range(2, 5),
				NpcType.PEASANT: rng.randi_range(0, 2),
				NpcType.BANDIT: rng.randi_range(0, 2)
			}
		"dangerous":
			spawn_types = [NpcType.MONSTER, NpcType.BANDIT]
			spawn_counts = {
				NpcType.MONSTER: rng.randi_range(1, 3),
				NpcType.BANDIT: rng.randi_range(2, 4)
			}
		"peaceful":
			spawn_types = [NpcType.ANIMAL, NpcType.PEASANT]
			spawn_counts = {
				NpcType.ANIMAL: rng.randi_range(3, 6),
				NpcType.PEASANT: rng.randi_range(1, 2)
			}
	
	for npc_type in spawn_types:
		var count = spawn_counts[npc_type]
		for _i in range(count):
			var npc = spawn_npc(npc_type, parent_node)
			if npc:
				# Initialize with wilderness-appropriate job and behavior
				setup_npc_in_wilderness(npc, npc_type, wilderness_type)
				spawned_npcs.append(npc)
	
	return spawned_npcs

func setup_npc_in_wilderness(npc: Node, npc_type: GlobalGameState.NpcType, wilderness_type: String) -> void:
	# Initialize NPC at a random position in local area only
	npc.initialize(npc.get_parent(), Vector2.ZERO)
	
	# Assign an appropriate wilderness job
	var job = ""
	match npc_type:
		NpcType.PEASANT:
			job = ["hunter", "gatherer", "traveler"][rng.randi() % 3]
		NpcType.BANDIT:
			job = ["thief", "outlaw", "marauder"][rng.randi() % 3]
		NpcType.ANIMAL:
			job = ["wild", "predator" if wilderness_type == "dangerous" else "prey"][rng.randi() % 2]
		NpcType.MONSTER:
			job = ["predator", "creature", "beast"][rng.randi() % 3]
	
	# Set up job-specific behaviors
	npc.npc_name = generate_name_for_job(job, npc_type)
	
	# Set behavior based on type and wilderness
	match npc_type:
		NpcType.BANDIT:
			npc.npc_properties[npc_type]["behavior"] = "aggressive"
		NpcType.MONSTER:
			npc.npc_properties[npc_type]["behavior"] = "hunt"
		NpcType.ANIMAL:
			if wilderness_type == "dangerous":
				npc.npc_properties[npc_type]["behavior"] = "hunt" if rng.randf() < 0.3 else "flee_on_approach"
			else:
				npc.npc_properties[npc_type]["behavior"] = "flee_on_approach"
		NpcType.PEASANT:
			# Travelers and hunters wander farther
			npc.wander_radius = 15.0 if job == "traveler" or job == "hunter" else 8.0

func spawn_npc(npc_type: GlobalGameState.NpcType, parent_node: Node2D) -> Node:
	var npc = npc_scene.instantiate()
	parent_node.add_child(npc)
	npc.npc_type = npc_type
	
	print("Spawning NPC of type: ", npc_type, " in local area environment")
	return npc

func find_suitable_building(npc_type: GlobalGameState.NpcType, settlement_data: Dictionary, specific_type = null, building_occupancy = null) -> Dictionary:
	var buildings = settlement_data.get("buildings", {})
	var suitable_buildings = []
	
	for building in buildings.values():
		var building_type = building.get("type")
		
		# If specific type is requested, filter by that
		if specific_type != null:
			if building_type == specific_type:
				suitable_buildings.append(building)
		# Otherwise use the NPC type mapping
		elif building_type in BUILDING_NPC_TYPES:
			if npc_type in BUILDING_NPC_TYPES[building_type]:
				suitable_buildings.append(building)
	
	if suitable_buildings.is_empty():
		return {}
	
	# If we're tracking occupancy, prefer less crowded buildings
	if building_occupancy != null and not building_occupancy.is_empty():
		# Sort by occupancy (less occupied first)
		suitable_buildings.sort_custom(func(a, b):
			var a_id = a.get("id", "unknown")
			var b_id = b.get("id", "unknown")
			var a_occupancy = building_occupancy.get(a_id, 0)
			var b_occupancy = building_occupancy.get(b_id, 0)
			return a_occupancy < b_occupancy
		)
		
		# Return the least occupied suitable building
		return suitable_buildings[0]
	
	# Otherwise pick randomly
	return suitable_buildings[rng.randi() % suitable_buildings.size()]
