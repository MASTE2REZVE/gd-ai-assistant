class_name Inventory
extends RefCounted

## Emitted whenever the contents of the inventory change.
signal inventory_changed

## Items stored as item_name -> count.
var _items: Dictionary = {}


## Add [param count] of [param name] to the inventory.
func add_item(name: String, count: int) -> void:
	_items[name] = _items.get(name, 0) + count
	inventory_changed.emit()


## Remove up to [param count] of [param name] from the inventory.
## Counts are clamped so they never go below zero.
func remove_item(name: String, count: int) -> void:
	if not _items.has(name):
		return
	_items[name] = maxi(_items[name] - count, 0)
	if _items[name] == 0:
		_items.erase(name)
	inventory_changed.emit()


## Return true if the inventory contains at least [param count] of [param name].
func has_item(name: String, count: int = 1) -> bool:
	return _items.get(name, 0) >= count