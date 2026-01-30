extends Area2D
class_name WorldItem

## Represents an item placed in the world that can be picked up.
## Can be placed manually in the editor or spawned via code.
## DO NOT SET ITEM RES IN BASE SCENE

## The item resource - assign a .tres file from resources/items/
@export var item_resource: Item:
	set(value):
		item_resource = value
		if is_inside_tree():
			_update_visual()

## How many of this item (for stackable items)
@export var quantity: int = 1

## Optional: Override the sprite scale
@export var sprite_scale: Vector2 = Vector2(1, 1)

## If true, the item bobs up and down
@export var animate_bob: bool = true

## If true, item can be picked up automatically on collision
@export var auto_pickup: bool = true

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

## Emitted when the item is picked up
signal picked_up(item: Item, qty: int)

## Animation variables
var _bob_time: float = 0.0
var _base_y: float = 0.0


func _ready():
	_base_y = position.y
	_bob_time = randf() * TAU  # Random start phase so items don't all bob in sync
	_update_visual()
	
	if auto_pickup:
		body_entered.connect(_on_body_entered)


func _process(delta: float):
	if animate_bob and sprite:
		_bob_time += delta * 3.0
		sprite.position.y = sin(_bob_time) * 2.0


func _update_visual():
	if not sprite:
		return
	
	if not item_resource:
		sprite.texture = null
		return
	
	# Get the icon from the item (uses ItemDatabase default spritesheet if needed)
	var icon = item_resource.get_icon()
	if icon:
		sprite.texture = icon
	
	# Apply scale
	sprite.scale = sprite_scale
	
	# Optional: Add color tint based on rarity
	sprite.modulate = item_resource.get_rarity_color()


func _on_body_entered(body: Node2D):
	if not item_resource:
		return
	
	# Check if it's the player
	if body.is_in_group("player") or body.name == "Player":
		try_pickup(body)


## Attempt to pick up this item. Returns true if successful.
func try_pickup(picker: Node2D) -> bool:
	if not item_resource:
		return false
	
	# Try to add to picker's inventory if they have one
	if picker.has_method("add_item_to_inventory"):
		if picker.add_item_to_inventory(item_resource.duplicate_item(), quantity):
			_on_picked_up()
			return true
		else:
			# Inventory full or can't carry
			return false
	elif picker.has_method("pickup_item"):
		# Alternative method name
		if picker.pickup_item(item_resource.duplicate_item(), quantity):
			_on_picked_up()
			return true
		else:
			return false
	else:
		# No inventory system, just emit signal and let something else handle it
		_on_picked_up()
		return true


func _on_picked_up():
	picked_up.emit(item_resource, quantity)
	queue_free()


## Set the item programmatically
func set_item(item: Item, qty: int = 1):
	item_resource = item
	quantity = qty


## Get a description for debugging/tooltips
func get_description() -> String:
	if not item_resource:
		return "Empty"
	
	var item_name = item_resource.get_display_name()
	if quantity > 1:
		return "%s x%d" % [item_name, quantity]
	return item_name


## Called in editor to show item preview
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not item_resource:
		warnings.append("No Item Resource assigned. Assign an item .tres file.")
	return warnings
