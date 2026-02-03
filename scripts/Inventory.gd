extends Node
class_name Inventory

## Inventory system that supports stacking items.
## Can be attached to Player, NPCs, or containers.
## Emits signals when inventory changes for UI updates.

signal inventory_changed
signal item_added(item: Item, quantity: int)
signal item_removed(item: Item, quantity: int)
signal inventory_full

## Maximum number of inventory slots (-1 for unlimited)
@export var max_slots: int = -1

## Current weight capacity (-1 for unlimited)
@export var max_weight: float = -1.0

## The items in this inventory
## Each element is a Dictionary with keys: {item: Item, quantity: int}
var items: Array[Dictionary] = []


func _ready():
	pass


## Add an item to the inventory. Returns true if successful.
## Automatically handles stacking for stackable items.
func add_item(item: Item, quantity: int = 1) -> bool:
	if not item:
		push_warning("[Inventory] Attempted to add null item")
		return false
	
	if quantity <= 0:
		return false
	
	# Check weight limit
	if max_weight > 0:
		var current_weight = get_total_weight()
		var added_weight = item.weight * quantity
		if current_weight + added_weight > max_weight:
			inventory_full.emit()
			return false
	
	# If item is stackable, try to stack with existing items
	if item.stackable:
		var remaining = quantity
		
		# First, try to add to existing stacks
		for slot in items:
			if slot.item.id == item.id and slot.quantity < slot.item.max_stack:
				var space_in_stack = slot.item.max_stack - slot.quantity
				var to_add = min(space_in_stack, remaining)
				slot.quantity += to_add
				remaining -= to_add
				
				if remaining <= 0:
					inventory_changed.emit()
					item_added.emit(item, quantity)
					return true
		
		# Create new stacks for remaining items
		while remaining > 0:
			if max_slots > 0 and items.size() >= max_slots:
				inventory_full.emit()
				# Partial success - some items were added
				if remaining < quantity:
					inventory_changed.emit()
					item_added.emit(item, quantity - remaining)
				return false
			
			var stack_size = min(remaining, item.max_stack)
			items.append({
				"item": item.duplicate_item(),
				"quantity": stack_size
			})
			remaining -= stack_size
		
		inventory_changed.emit()
		item_added.emit(item, quantity)
		return true
	else:
		# Non-stackable item - each takes one slot
		if max_slots > 0 and items.size() + quantity > max_slots:
			inventory_full.emit()
			return false
		
		for i in range(quantity):
			items.append({
				"item": item.duplicate_item(),
				"quantity": 1
			})
		
		inventory_changed.emit()
		item_added.emit(item, quantity)
		return true


## Remove a specific quantity of an item from inventory. Returns the actual quantity removed.
func remove_item(item_id: String, quantity: int = 1) -> int:
	if quantity <= 0:
		return 0
	
	var remaining_to_remove = quantity
	var removed = 0
	
	# Remove from stacks (iterate backwards to safely remove items)
	for i in range(items.size() - 1, -1, -1):
		if items[i].item.id == item_id:
			var to_remove = min(items[i].quantity, remaining_to_remove)
			items[i].quantity -= to_remove
			removed += to_remove
			remaining_to_remove -= to_remove
			
			# Remove empty slots
			if items[i].quantity <= 0:
				items.remove_at(i)
			
			if remaining_to_remove <= 0:
				break
	
	if removed > 0:
		inventory_changed.emit()
		# Get the item for the signal (if any left)
		var item_ref = get_item_by_id(item_id)
		if not item_ref:
			# If none left, we need to get it from somewhere - use first removed
			item_ref = ItemDatabase.get_item(item_id) if ItemDatabase else null
		if item_ref:
			item_removed.emit(item_ref, removed)
	
	return removed


## Remove an item at a specific slot index
func remove_item_at_slot(slot_index: int, quantity: int = 1) -> int:
	if slot_index < 0 or slot_index >= items.size():
		return 0
	
	var slot = items[slot_index]
	var to_remove = min(slot.quantity, quantity)
	
	slot.quantity -= to_remove
	
	if slot.quantity <= 0:
		items.remove_at(slot_index)
	
	if to_remove > 0:
		inventory_changed.emit()
		item_removed.emit(slot.item, to_remove)
	
	return to_remove


## Check if inventory has a specific item with at least the given quantity
func has_item(item_id: String, quantity: int = 1) -> bool:
	return get_item_count(item_id) >= quantity


## Get the total count of a specific item across all stacks
func get_item_count(item_id: String) -> int:
	var count = 0
	for slot in items:
		if slot.item.id == item_id:
			count += slot.quantity
	return count


## Get the first item matching the ID (returns the Item resource, not the slot)
func get_item_by_id(item_id: String) -> Item:
	for slot in items:
		if slot.item.id == item_id:
			return slot.item
	return null


## Get all items of a specific type
func get_items_by_type(item_type: Item.ItemType) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in items:
		if slot.item.item_type == item_type:
			result.append(slot)
	return result


## Get the slot at a specific index (returns Dictionary with {item, quantity})
func get_slot(index: int) -> Dictionary:
	if index >= 0 and index < items.size():
		return items[index]
	return {}


## Get total number of occupied slots
func get_slot_count() -> int:
	return items.size()


## Check if inventory is full
func is_full() -> bool:
	if max_slots > 0 and items.size() >= max_slots:
		return true
	if max_weight > 0 and get_total_weight() >= max_weight:
		return true
	return false


## Get total weight of all items in inventory
func get_total_weight() -> float:
	var total = 0.0
	for slot in items:
		total += slot.item.weight * slot.quantity
	return total


## Get total value of all items in inventory
func get_total_value() -> int:
	var total = 0
	for slot in items:
		total += slot.item.get_total_value() * slot.quantity
	return total


## Clear all items from inventory
func clear():
	items.clear()
	inventory_changed.emit()


## Get all items as an array (for serialization/UI)
func get_all_items() -> Array[Dictionary]:
	return items.duplicate()


## Sort inventory by a specific criteria
func sort_by(sort_type: String):
	match sort_type:
		"name":
			items.sort_custom(func(a, b): return a.item.display_name < b.item.display_name)
		"type":
			items.sort_custom(func(a, b): return a.item.item_type < b.item.item_type)
		"value":
			items.sort_custom(func(a, b): return a.item.get_total_value() > b.item.get_total_value())
		"weight":
			items.sort_custom(func(a, b): return a.item.weight < b.item.weight)
		"rarity":
			items.sort_custom(func(a, b): return a.item.rarity > b.item.rarity)
	
	inventory_changed.emit()


## Transfer an item from this inventory to another
func transfer_to(other_inventory: Inventory, item_id: String, quantity: int = 1) -> bool:
	if not has_item(item_id, quantity):
		return false
	
	var item = get_item_by_id(item_id)
	if not item:
		return false
	
	if other_inventory.add_item(item, quantity):
		remove_item(item_id, quantity)
		return true
	
	return false


## Transfer an item from a specific slot to another inventory
func transfer_slot_to(other_inventory: Inventory, slot_index: int, quantity: int = 1) -> bool:
	if slot_index < 0 or slot_index >= items.size():
		return false
	
	var slot = items[slot_index]
	var to_transfer = min(slot.quantity, quantity)
	
	if other_inventory.add_item(slot.item, to_transfer):
		remove_item_at_slot(slot_index, to_transfer)
		return true
	
	return false


## Serialize inventory to a Dictionary (for save/load)
func to_dict() -> Dictionary:
	var item_data = []
	for slot in items:
		item_data.append({
			"item_id": slot.item.id,
			"quantity": slot.quantity,
			# Store any modified properties if needed
			"modifiers": slot.item.modifiers
		})
	
	return {
		"max_slots": max_slots,
		"max_weight": max_weight,
		"items": item_data
	}


## Load inventory from a Dictionary (for save/load)
func from_dict(data: Dictionary):
	clear()
	
	if data.has("max_slots"):
		max_slots = data.max_slots
	if data.has("max_weight"):
		max_weight = data.max_weight
	
	if data.has("items"):
		for item_data in data.items:
			var item = ItemDatabase.get_item(item_data.item_id)
			if item:
				# Restore modifiers
				if item_data.has("modifiers"):
					item.modifiers = item_data.modifiers
				add_item(item, item_data.quantity)
	
	inventory_changed.emit()


## Debug: Print inventory contents
func print_inventory():
	print("[Inventory] Contents (%d/%s slots, %.1f/%.1f weight):" % [
		items.size(),
		str(max_slots) if max_slots > 0 else "∞",
		get_total_weight(),
		max_weight if max_weight > 0 else INF
	])
	for i in range(items.size()):
		var slot = items[i]
		print("  [%d] %s x%d (%.1f kg each)" % [
			i,
			slot.item.get_display_name(),
			slot.quantity,
			slot.item.weight
		])
