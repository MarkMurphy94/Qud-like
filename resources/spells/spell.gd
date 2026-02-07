extends Resource
class_name Spell

## Base spell resource class for all spells in the game.
## Can be extended for specialized spell types.
## Supports both hand-crafted unique spells and procedural generation.

enum SpellType {
	OFFENSIVE,
	DEFENSIVE,
	HEALING,
	UTILITY,
	BUFF,
	DEBUFF,
	SUMMONING
}

enum TargetType {
	SELF,
	SINGLE_ENEMY,
	SINGLE_ALLY,
	AOE_ENEMIES,
	AOE_ALLIES,
	GROUND_TARGET
}

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
	UNIQUE
}

## Core identification
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var spell_type: SpellType = SpellType.UTILITY
@export var rarity: Rarity = Rarity.COMMON

## Casting properties
@export_group("Casting")
@export var mana_cost: int = 0
@export var cast_time: float = 0.0  ## Seconds, 0 = instant
@export var cooldown: float = 0.0  ## Seconds between casts
@export var spell_range: float = 5.0  ## Range in tiles
@export var target_type: TargetType = TargetType.SINGLE_ENEMY
@export var can_move_while_casting: bool = true

## Effect properties
@export_group("Effects")
@export var damage: int = 0
@export var healing: int = 0
@export var aoe_radius: float = 0.0  ## Radius for AOE spells
@export var status_effects: Array[Resource] = []  ## StatusEffect resources
@export var duration: float = 0.0  ## Duration for buffs/debuffs
@export var projectile_speed: float = 10.0  ## Speed of projectile if applicable

## Requirements
@export_group("Requirements")
@export var required_level: int = 1
@export var required_skill: String = ""
@export var required_skill_level: int = 1

## Visuals
@export_group("Visuals")
@export var icon: Texture2D
@export var spritesheet: Texture2D
@export var sprite_region: Rect2i = Rect2i(0, 0, 16, 16)
@export var sprite_index: Vector2i = Vector2i(0, 0)
@export var tile_size: Vector2i = Vector2i(16, 16)
@export var particle_effect: PackedScene
@export var animation: String = ""
@export var spell_color: Color = Color.WHITE

## Optional modifiers (for generated spells)
@export var modifiers: Dictionary = {}


## Returns the icon texture for UI display
func get_icon() -> Texture2D:
	if icon:
		return icon
	
	var sheet = _get_spritesheet()
	if sheet:
		return _create_atlas_texture(sheet)
	return null


## Gets the spritesheet to use, falling back to SpellDatabase default if available
func _get_spritesheet() -> Texture2D:
	if spritesheet:
		return spritesheet
	# Try accessing SpellDatabase as autoload
	var spell_db = Engine.get_main_loop().root.get_node_or_null("/root/SpellDatabase")
	if spell_db and spell_db.has("default_spell_spritesheet"):
		return spell_db.default_spell_spritesheet
	return null


## Gets the tile size, falling back to default
func _get_tile_size() -> Vector2i:
	if tile_size.x > 0 and tile_size.y > 0:
		return tile_size
	var spell_db = Engine.get_main_loop().root.get_node_or_null("/root/SpellDatabase")
	if spell_db and spell_db.has("default_tile_size"):
		return spell_db.default_tile_size
	return Vector2i(16, 16)


## Creates an AtlasTexture from the spritesheet
func _create_atlas_texture(sheet: Texture2D) -> AtlasTexture:
	var atlas = AtlasTexture.new()
	atlas.atlas = sheet
	
	if sprite_region.size.x > 0 and sprite_region.size.y > 0:
		atlas.region = Rect2(sprite_region)
	else:
		var ts = _get_tile_size()
		atlas.region = Rect2(
			sprite_index.x * ts.x,
			sprite_index.y * ts.y,
			ts.x,
			ts.y
		)
	
	return atlas


## Returns the display name with modifiers applied
func get_display_name() -> String:
	var prefix = modifiers.get("prefix", "")
	var suffix = modifiers.get("suffix", "")
	var name = display_name
	if prefix:
		name = prefix + " " + name
	if suffix:
		name = name + " " + suffix
	return name


## Returns a color associated with the spell's rarity
func get_rarity_color() -> Color:
	match rarity:
		Rarity.COMMON:
			return Color.WHITE
		Rarity.UNCOMMON:
			return Color.GREEN
		Rarity.RARE:
			return Color.CORNFLOWER_BLUE
		Rarity.EPIC:
			return Color.MEDIUM_PURPLE
		Rarity.LEGENDARY:
			return Color.ORANGE
		Rarity.UNIQUE:
			return Color.GOLD
		_:
			return Color.WHITE


## Returns a string representation of the rarity
func get_rarity_name() -> String:
	match rarity:
		Rarity.COMMON:
			return "Common"
		Rarity.UNCOMMON:
			return "Uncommon"
		Rarity.RARE:
			return "Rare"
		Rarity.EPIC:
			return "Epic"
		Rarity.LEGENDARY:
			return "Legendary"
		Rarity.UNIQUE:
			return "Unique"
		_:
			return "Common"


## Returns the spell type as a string
func get_spell_type_name() -> String:
	match spell_type:
		SpellType.OFFENSIVE:
			return "Offensive"
		SpellType.DEFENSIVE:
			return "Defensive"
		SpellType.HEALING:
			return "Healing"
		SpellType.UTILITY:
			return "Utility"
		SpellType.BUFF:
			return "Buff"
		SpellType.DEBUFF:
			return "Debuff"
		SpellType.SUMMONING:
			return "Summoning"
		_:
			return "Unknown"


## Returns the target type as a string
func get_target_type_name() -> String:
	match target_type:
		TargetType.SELF:
			return "Self"
		TargetType.SINGLE_ENEMY:
			return "Single Enemy"
		TargetType.SINGLE_ALLY:
			return "Single Ally"
		TargetType.AOE_ENEMIES:
			return "Area (Enemies)"
		TargetType.AOE_ALLIES:
			return "Area (Allies)"
		TargetType.GROUND_TARGET:
			return "Ground Target"
		_:
			return "Unknown"


## Checks if the caster can cast this spell
func can_cast(caster) -> bool:
	if not caster:
		return false
	
	# Check mana
	if caster.has_method("get_current_mana"):
		if caster.get_current_mana() < get_mana_cost():
			return false
	
	# Check level requirement
	if caster.has_method("get_level"):
		if caster.get_level() < required_level:
			return false
	
	# Check skill requirement
	if required_skill != "":
		if caster.has_method("get_skill_level"):
			if caster.get_skill_level(required_skill) < required_skill_level:
				return false
	
	# Check if spell is on cooldown
	if caster.has_method("is_spell_on_cooldown"):
		if caster.is_spell_on_cooldown(id):
			return false
	
	return true


## Returns the actual mana cost including modifiers
func get_mana_cost() -> int:
	var modifier_bonus = modifiers.get("mana_cost_reduction", 0)
	return max(0, mana_cost - modifier_bonus)


## Returns the actual damage including modifiers
func get_damage() -> int:
	var modifier_bonus = modifiers.get("damage_bonus", 0)
	return damage + modifier_bonus


## Returns the actual healing including modifiers
func get_healing() -> int:
	var modifier_bonus = modifiers.get("healing_bonus", 0)
	return healing + modifier_bonus


## Returns whether this is an AOE spell
func is_aoe() -> bool:
	return target_type in [TargetType.AOE_ENEMIES, TargetType.AOE_ALLIES, TargetType.GROUND_TARGET]


## Returns whether this spell requires a target
func requires_target() -> bool:
	return target_type != TargetType.SELF


## Creates a deep copy of this spell
func duplicate_spell() -> Spell:
	var new_spell = duplicate(true)
	new_spell.modifiers = modifiers.duplicate(true)
	new_spell.status_effects = status_effects.duplicate(true)
	return new_spell