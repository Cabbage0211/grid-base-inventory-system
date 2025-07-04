extends Node
## 背包业务类
class_name InventoryService

## 背包数据库引用
var _inventory_repository: InventoryRepository = InventoryRepository.instance

## 保存所有背包
func save() -> void:
	_inventory_repository.save()

## 读取所有背包
func load() -> void:
	_inventory_repository.load()

## 注册背包，如果重名，检查新注册的是否和数据库中的一致（大小、允许存储的类型）
## 注意：如果背包不显示，大概率是注册返回失败了，请检查配置
func regist_inventory(inv_name: String, columns: int, rows: int, avilable_types: Array[String]) -> bool:
	var inv_data = _inventory_repository.get_inventory(inv_name)
	if inv_data:
		var is_same_size = inv_data.rows == rows and inv_data.columns == columns
		var is_same_avilable_types = avilable_types.size() == inv_data.avilable_types.size()
		if is_same_avilable_types:
			for i in range(avilable_types.size()):
				is_same_avilable_types = avilable_types[i] == inv_data.avilable_types[i]
				if not is_same_avilable_types:
					break
		return is_same_size && is_same_avilable_types
	else:
		return _inventory_repository.add_inventory(inv_name, columns, rows, avilable_types)

## 获取背包数据
func get_inventory(inv_name: String) -> InventoryData:
	return _inventory_repository.get_inventory(inv_name)

## 向背包添加物品
## 如果是可堆叠物品，如果当前数量大于可堆叠数量，会重置为允许的最大值，成功后发射信号 sig_inv_item_updated
## 如果是不可堆叠物品，或堆叠后还有剩余，成功后发射 sig_inv_item_added
func add_item(inv_name: String, item_data: ItemData) -> bool:
	var new_item_data = item_data.duplicate()
	if new_item_data is StackableData:
		if new_item_data.current_amount > new_item_data.stack_size:
			new_item_data.current_amount = new_item_data.stack_size
		var items = find_item_data_by_item_name(inv_name, new_item_data.item_name)
		for item in items:
			if not item.is_full():
				new_item_data.current_amount = item.add_amount(new_item_data.current_amount)
				var new_item_grids = _inventory_repository.get_inventory(inv_name).find_grids_by_item_data(item)
				assert(not new_item_grids.is_empty())
				GBIS.sig_inv_item_updated.emit(inv_name, new_item_grids[0])
				if new_item_data.current_amount <= 0:
					return true
	# 增加不可堆叠物品，或堆叠后剩余的物品
	var grids = _inventory_repository.get_inventory(inv_name).add_item(new_item_data)
	if not grids.is_empty():
		GBIS.sig_inv_item_added.emit(inv_name, new_item_data, grids)
		return true
	return false

## 尝试把正在移动的物品堆叠到这个格子上
func stack_moving_item(inv_name: String, grid_id: Vector2i) -> void:
	if not GBIS.moving_item_service.moving_item:
		return
	var item_data = find_item_data_by_grid(inv_name, grid_id)
	if not item_data is StackableData:
		return
	if item_data.item_name == GBIS.moving_item_service.moving_item.item_name:
		var amount_left = item_data.add_amount(GBIS.moving_item_service.moving_item.current_amount)
		if amount_left > 0:
			GBIS.moving_item_service.moving_item.current_amount = amount_left
		else:
			GBIS.moving_item_service.clear_moving_item()
		GBIS.sig_inv_item_updated.emit(inv_name, grid_id)

## 尝试放置正在移动的物品到这个格子
func place_moving_item(inv_name: String, grid_id: Vector2i) -> bool:
	if place_to(inv_name, GBIS.moving_item_service.moving_item, grid_id):
		GBIS.moving_item_service.clear_moving_item()
		return true
	return false

## 使用物品（默认：鼠标右键点击格子）
func use_item(inv_name: String, grid_id: Vector2i) -> bool:
	var item_data = find_item_data_by_grid(inv_name, grid_id)
	if not item_data:
		return false
	if item_data is EquipmentData:
		if GBIS.equipment_slot_service.try_equip(item_data):
			remove_item_by_data(inv_name, item_data)
			return true
	elif item_data is ConsumableData:
		if item_data.use():
			remove_item_by_data(inv_name, item_data)
		else:
			GBIS.sig_inv_item_updated.emit(inv_name, grid_id)
		return true
	return false

## 通过物品名称找所有物品（同名物品可能有多个实例）
func find_item_data_by_item_name(inv_name: String, item_name: String) -> Array[ItemData]:
	var inv = _inventory_repository.get_inventory(inv_name)
	if inv:
		return inv.find_item_data_by_item_name(item_name)
	return []

## 通过格子找物品
func find_item_data_by_grid(inv_name: String, grid_id: Vector2i) -> ItemData:
	return _inventory_repository.get_inventory(inv_name).find_item_data_by_grid(grid_id)

## 分割物品
func split_item(inv_name: String, grid_id: Vector2i, offset: Vector2i, base_size: int) -> ItemData:
	var inv = _inventory_repository.get_inventory(inv_name)
	if inv:
		var item = inv.find_item_data_by_grid(grid_id)
		if item and item is StackableData and item.stack_size > 1 and item.current_amount > 1:
			var origin_amount = item.current_amount
			var new_amount_1 = origin_amount / 2
			var new_amount_2 = origin_amount - new_amount_1
			item.current_amount = new_amount_1
			GBIS.sig_inv_item_updated.emit(inv_name, grid_id)
			
			var new_item = item.duplicate()
			new_item.current_amount = new_amount_2
			GBIS.moving_item_service.move_item_by_data(new_item, offset, base_size)
			return new_item
	return null

## 判断背包是否存在
func is_inventory_existed(inv_name: String) -> bool:
	return _inventory_repository.get_inventory(inv_name) != null

## 尝试把物品放置到指定格子
func place_to(inv_name: String, item_data: ItemData, grid_id: Vector2i) -> bool:
	if item_data:
		var inv = _inventory_repository.get_inventory(inv_name)
		if inv:
			var grids = inv.try_add_to_grid(item_data, grid_id - GBIS.moving_item_service.moving_item_offset)
			if grids:
				GBIS.sig_inv_item_added.emit(inv_name, item_data, grids)
				return true
	return false

## 快速移动（默认：Shift + 鼠标右键）
func quick_move(inv_name: String, grid_id: Vector2i) -> void:
	var target_inventories = _inventory_repository.get_quick_move_relations(inv_name)
	var item_to_move = _inventory_repository.get_inventory(inv_name).find_item_data_by_grid(grid_id)
	if target_inventories.is_empty() or not item_to_move:
		return
	for target_inventory in target_inventories:
		if add_item(target_inventory, item_to_move):
			remove_item_by_data(inv_name, item_to_move)
			break
		elif item_to_move is StackableData:
			GBIS.sig_inv_item_updated.emit(inv_name, grid_id)

## 增加背包间的快速移动关系
func add_quick_move_relation(inv_name: String, target_inv_name: String) -> void:
	_inventory_repository.add_quick_move_relation(inv_name, target_inv_name)

## 删除背包间的快速移动关系
func remove_quick_move_relation(inv_name: String, target_inv_name: String) -> void:
	_inventory_repository.remove_quick_move_relation(inv_name, target_inv_name)

## 删除背包中的物品，成功后触发 sig_inv_item_removed
func remove_item_by_data(inv_name: String, item_data: ItemData) -> void:
	if _inventory_repository.get_inventory(inv_name).remove_item(item_data):
		GBIS.sig_inv_item_removed.emit(inv_name, item_data)
