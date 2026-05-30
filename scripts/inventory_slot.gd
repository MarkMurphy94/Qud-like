class InventorySlot:
    var item: Item
    var quantity: int
    
    func _init(p_item: Item, p_qty: int = 1) -> void:
        item = p_item
        quantity = p_qty