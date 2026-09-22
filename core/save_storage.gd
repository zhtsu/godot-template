extends RefCounted

## 存档的**纯文件 IO**：路径拼接、槽位名校验、魔数 / 长度 / 大小校验、解码、原子写、目录枚举。
##
## 约束（FR-008，见 specs/001-core-save-refactor/data-model.md §5.3）：
##   - **不持状态**：存档目录由调用方以参数传入，本类不缓存它
##   - **不订阅事件**、**不持有 SaveData**、不认识 Types
##   - **不加 class_name**：由 core/save_service.gd 经 Paths.SCRIPT_SAVE_STORAGE 用 preload 引用，
##     避免污染全局类缓存（同 addons/godot_core_system/source/core_system.gd 引用模块的方式）
##
## 方法全是 static：调用方不需要 new 一个实例，也不存在"要不要复用实例"的问题。

## 存档文件扩展名
const SAVE_EXTENSION: String = ".sav"
## 文件头魔数：确认"这是我们自己的存档"，顺便挡住随便丢进来的文件
const SAVE_MAGIC: String = "GTSV"
## 超过这个大小的存档文件直接拒绝读取（防止被塞一个巨大文件把内存吃满）
const MAX_SAVE_BYTES: int = 8 * 1024 * 1024
## 槽位名里不允许出现的字符
const SLOT_FORBIDDEN: Array[String] = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", ".."]


## 槽位名合法性：只允许文件名安全的字符串，避免 "../" 之类越出存档目录。
## allow_empty = true 表示"留空"合法（存档时可以自动生成槽位）。
static func is_valid_slot(slot: String, allow_empty: bool) -> bool:
	if slot.is_empty():
		return allow_empty
	if slot.begins_with("."):
		return false
	for bad in SLOT_FORBIDDEN:
		if slot.contains(bad):
			return false
	return true


## 槽位 ID → 存档文件路径
static func path_for(save_dir: String, slot: String) -> String:
	return save_dir.path_join(slot + SAVE_EXTENSION)


## 列出存档目录里所有槽位 ID（不含设置档，也不含 .tmp 残留 —— .tmp 不以 .sav 结尾）
static func list_slots(save_dir: String, excluded_slot: String) -> Array[String]:
	var slots: Array[String] = []
	if not DirAccess.dir_exists_absolute(save_dir):
		return slots

	for file_name in DirAccess.get_files_at(save_dir):
		if not file_name.ends_with(SAVE_EXTENSION):
			continue
		var slot: String = file_name.trim_suffix(SAVE_EXTENSION)
		if slot == excluded_slot:
			continue
		slots.append(slot)
	slots.sort()
	return slots


## 请求没给 slot 时自动生成一个；同秒内重复调用不会撞名
static func make_slot(save_dir: String) -> String:
	var base: String = "save_%d" % int(Time.get_unix_time_from_system())
	var slot: String = base
	var counter: int = 1
	while FileAccess.file_exists(path_for(save_dir, slot)):
		slot = "%s_%d" % [base, counter]
		counter += 1
	return slot


## 原子写入：先写 <slot>.sav.tmp，写入无误后再改名覆盖正式文件。
## var_to_bytes 本身就不编码对象（能编码对象的是 var_to_bytes_with_objects，这里不用）。
static func write(save_dir: String, slot: String, payload: Dictionary) -> bool:
	var path: String = path_for(save_dir, slot)
	var tmp_path: String = path + ".tmp"

	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		CoreSystem.logger.error("[SaveStorage] 打不开临时存档文件: %s" % tmp_path)
		return false

	file.store_buffer(SAVE_MAGIC.to_ascii_buffer())
	file.store_buffer(var_to_bytes(payload))
	var write_err: int = file.get_error()
	file.close()

	if write_err != OK:
		CoreSystem.logger.error("[SaveStorage] 写临时存档失败: %s（错误码 %d）" % [tmp_path, write_err])
		DirAccess.remove_absolute(tmp_path)
		return false

	# rename 会覆盖已存在的目标（Windows 上也一样，实测过）
	var rename_err: int = DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		CoreSystem.logger.error("[SaveStorage] 替换存档失败: %s（错误码 %d）" % [path, rename_err])
		DirAccess.remove_absolute(tmp_path)
		return false

	return true


## 读存档，返回纯数据字典；文件不存在 / 太小 / 太大 / 魔数不对 / 解码失败都返回 {}
## 关键：bytes_to_var 不还原对象，所以存档文件不可能带出任何可执行的东西
static func read(save_dir: String, slot: String) -> Dictionary:
	var path: String = path_for(save_dir, slot)
	if not FileAccess.file_exists(path):
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		CoreSystem.logger.error("[SaveStorage] 打不开存档文件: %s" % path)
		return {}

	var length: int = file.get_length()
	if length < SAVE_MAGIC.length():
		file.close()
		CoreSystem.logger.error("[SaveStorage] 存档文件太小，不是有效存档: %s" % path)
		return {}
	if length > MAX_SAVE_BYTES:
		file.close()
		CoreSystem.logger.error("[SaveStorage] 存档文件过大（%d 字节），拒绝读取: %s" % [length, path])
		return {}

	var magic: String = file.get_buffer(SAVE_MAGIC.length()).get_string_from_ascii()
	if magic != SAVE_MAGIC:
		file.close()
		CoreSystem.logger.error("[SaveStorage] 不是本项目的存档文件（文件头不是 %s）: %s" % [SAVE_MAGIC, path])
		return {}

	var payload: PackedByteArray = file.get_buffer(length - SAVE_MAGIC.length())
	file.close()

	var data: Variant = bytes_to_var(payload)
	if data is Dictionary:
		return data

	CoreSystem.logger.error("[SaveStorage] 存档解码失败: %s" % path)
	return {}
