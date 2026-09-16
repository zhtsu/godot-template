extends Node

## 存档服务：持有唯一一份 SaveData，把「存档事件」变成对它的读写 + 落盘纯二进制数据。
## 挂在 entry/main.tscn 上（与 UiRoot 同级）。
##
## 文件格式：4 字节魔数 "GTSV" + var_to_bytes(纯数据字典)，扩展名 .sav。
## 读回来用 bytes_to_var() —— 注意是"不解码对象"的那一版，不是 bytes_to_var_with_objects()。
## 也就是说：存档文件里就算被塞进对象 / 脚本引用，读出来也只是 null，不可能执行任何逻辑。
##
## 写入是原子的：先写 <slot>.sav.tmp，确认无误后再改名覆盖正式文件；
## 中途崩溃只会留下 .tmp，旧存档始终完整。
##
## 两类文件分开放：
##   options.sav（槽位 OptionsSave.SLOT）= 机器级设置，只有元数据 + options 段；
##   其它槽位                          = 游戏进度，元数据 + 除 options 外的所有分段。
##
## 所有请求都进同一个任务队列按顺序执行，一次 drain 有上限，剩下的下一帧继续
## （避免监听者在结果事件里继续投任务造成同一帧死循环）。
##
## 为什么不用 save_manager.create_save()：那套数据来源固定是「saveable 节点组 + save()」、
## 结构固定是 {metadata, nodes}，塞不下自定义的存档类。这里只借它的存档目录设置。
##
## 游戏代码两种用法：
##   1) 有引用就直接改：save_service.save_data.options.language = "zh_CN"
##   2) 没有引用就在请求里带补丁：request.data = {"options": {"language": "zh_CN"}}
## 然后 push_event(Events.SAVE_REQUEST, request)；结果听 SAVE_FINISHED。

## 存档文件扩展名
const SAVE_EXTENSION: String = ".sav"
## 文件头魔数：确认"这是我们自己的存档"，顺便挡住随便丢进来的文件
const SAVE_MAGIC: String = "GTSV"
## 一次 drain 最多执行多少个任务，剩下的下一帧继续
const MAX_JOBS_PER_DRAIN: int = 16
## 超过这个大小的存档文件直接拒绝读取（防止被塞一个巨大文件把内存吃满）
const MAX_SAVE_BYTES: int = 8 * 1024 * 1024
## 槽位名里不允许出现的字符
const SLOT_FORBIDDEN: Array[String] = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", ".."]

## 唯一的存档数据对象（存档 = 序列化它）
var save_data: SaveData = SaveData.new()

## 任务队列（存 / 读 / 删 / 列表都排队执行）
var _jobs: Array[Callable] = []
var _draining: bool = false

## 存档目录（取自项目的 save_system/save_directory 设置，默认 user://saves）
var _save_dir: String = ""


func _ready() -> void:
	var event_bus: Variant = CoreSystem.event_bus
	event_bus.subscribe_unique_script(Events.SAVE_REQUEST, _on_save_request)
	event_bus.subscribe_unique_script(Events.LOAD_REQUEST, _on_load_request)
	event_bus.subscribe_unique_script(Events.DELETE_SAVE_REQUEST, _on_delete_request)
	event_bus.subscribe_unique_script(Events.SAVE_LIST_REQUEST, _on_save_list_request)

	_save_dir = CoreSystem.save_manager.save_directory
	DirAccess.make_dir_recursive_absolute(_save_dir)

	# 让各处能只读拿到当前存档（写数据仍然走事件）
	SaveData.current = save_data

	_options_ready()


func _exit_tree() -> void:
	var event_bus: Variant = CoreSystem.event_bus
	event_bus.unsubscribe(Events.SAVE_REQUEST, _on_save_request)
	event_bus.unsubscribe(Events.LOAD_REQUEST, _on_load_request)
	event_bus.unsubscribe(Events.DELETE_SAVE_REQUEST, _on_delete_request)
	event_bus.unsubscribe(Events.SAVE_LIST_REQUEST, _on_save_list_request)

	if SaveData.current == save_data:
		SaveData.current = null


#region 请求入口（只做校验 + 入队，具体干活在任务里）

## 请求存档
func _on_save_request(request: Types.SaveRequest) -> void:
	if not request:
		CoreSystem.logger.error("[SaveService] 存档请求为空")
		_emit(Events.SAVE_FINISHED, _make_result(false, "", "请求为空"))
		return
	if not _is_valid_slot(request.slot, true):
		CoreSystem.logger.error("[SaveService] 非法槽位名: '%s'" % request.slot)
		_emit(Events.SAVE_FINISHED, _make_result(false, request.slot, "非法槽位名", request.reason))
		return

	_enqueue(_do_save.bind(request))


## 请求读档
func _on_load_request(request: Types.LoadRequest) -> void:
	if not request or not _is_valid_slot(request.slot, false):
		var bad_slot: String = request.slot if request else ""
		CoreSystem.logger.error("[SaveService] 读档请求的 slot 为空或非法: '%s'" % bad_slot)
		_emit(Events.LOAD_FINISHED, _make_result(false, bad_slot, "slot 为空或非法"))
		return

	_enqueue(_do_load.bind(request))


## 请求删除存档
func _on_delete_request(request: Types.DeleteSaveRequest) -> void:
	if not request or not _is_valid_slot(request.slot, false):
		var bad_slot: String = request.slot if request else ""
		CoreSystem.logger.error("[SaveService] 删除存档请求的 slot 为空或非法: '%s'" % bad_slot)
		_emit(Events.DELETE_SAVE_FINISHED, _make_result(false, bad_slot, "slot 为空或非法"))
		return

	_enqueue(_do_delete.bind(request))


## 请求存档列表（无 payload），结果用 SAVE_LIST_READY 发回
func _on_save_list_request() -> void:
	_enqueue(_do_save_list)

#endregion


#region 任务队列

func _enqueue(job: Callable) -> void:
	_jobs.append(job)
	if not _draining:
		_drain_jobs()


## 顺序执行任务；一次最多 MAX_JOBS_PER_DRAIN 个，剩下的下一帧继续
func _drain_jobs() -> void:
	_draining = true
	var processed: int = 0
	while not _jobs.is_empty() and processed < MAX_JOBS_PER_DRAIN:
		var job: Callable = _jobs.pop_front()
		job.call()
		processed += 1
	_draining = false

	if not _jobs.is_empty():
		_drain_jobs.call_deferred()

#endregion


#region 具体任务

## 存档：合并补丁 → 补元数据 → 原子写 → （设置档）立刻应用 → 发结果
func _do_save(request: Types.SaveRequest) -> void:
	if not request.data.is_empty():
		save_data.apply_dict(request.data)

	var slot: String = request.slot if not request.slot.is_empty() else _make_slot()
	var previous_slot: String = save_data.slot
	_stamp(slot)

	var ok: bool = _write(slot)
	if not ok:
		save_data.slot = previous_slot
		CoreSystem.logger.error("[SaveService] 存档失败: %s" % _path_for(slot))
	elif slot == OptionsSave.SLOT:
		# 设置档写完立刻应用，改动即时生效
		_apply_options()

	var result: Types.SaveResult = _make_result(ok, slot, "" if ok else "写入失败", request.reason)
	result.metadata = save_data.metadata()
	if ok:
		result.data = save_data
	_emit(Events.SAVE_FINISHED, result)


## 读档：解码 → 校验版本 → 填回 → 自检 → 发结果
func _do_load(request: Types.LoadRequest) -> void:
	var dict: Dictionary = _prepare_load(_read(request.slot))
	var ok: bool = not dict.is_empty()
	var error: String = ""

	if ok:
		save_data.from_dict(dict)
		save_data.validate_tree()
		CoreSystem.logger.info("[SaveService] 读档成功: %s" % request.slot)
	else:
		error = "存档不存在 / 版本不兼容 / 读取失败"
		CoreSystem.logger.error("[SaveService] 读档失败: %s" % request.slot)

	var result: Types.SaveResult = _make_result(ok, request.slot, error)
	if ok:
		result.metadata = save_data.metadata()
		result.data = save_data
	_emit(Events.LOAD_FINISHED, result)


## 删档
func _do_delete(request: Types.DeleteSaveRequest) -> void:
	var path: String = _path_for(request.slot)
	var ok: bool = FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK
	if not ok:
		CoreSystem.logger.error("[SaveService] 删除存档失败: %s" % path)
	_emit(Events.DELETE_SAVE_FINISHED, _make_result(ok, request.slot, "" if ok else "删除失败"))


## 列存档（不含设置档）
func _do_save_list() -> void:
	var saves: Array[Dictionary] = []
	for slot in _list_slots():
		var dict: Dictionary = _read(slot)
		if dict.is_empty():
			continue
		# 借一个临时实例取元数据，字段表只有 SaveData 一份，不在这里重复维护
		var probe: SaveData = SaveData.new()
		probe.from_dict(dict)
		saves.append({"slot": slot, "metadata": probe.metadata()})

	# 注意：payload 本身是数组时必须再包一层，否则会被当成参数列表展开
	CoreSystem.event_bus.push_event(Events.SAVE_LIST_READY, [saves])

#endregion


#region 启动时的设置

## 设置档的启动处理：
## 有存档 → 读进来并应用；没有存档（首次运行）→ 把当前引擎状态当成默认值写进内存。
## 后者是为了让"界面显示的选择"和"实际生效的值"永远一致（否则会出现界面显示 English、
## 实际界面是中文这种情况）。
func _options_ready() -> void:
	if FileAccess.file_exists(_path_for(OptionsSave.SLOT)):
		_autoload_options()
		return

	save_data.options.language = TranslationServer.get_locale()
	var window_size: Vector2i = DisplayServer.window_get_size()
	if window_size.x > 0 and window_size.y > 0:
		save_data.options.resolution = window_size
	CoreSystem.logger.info("[SaveService] 首次运行：以当前引擎状态作为设置默认值（%s / %s）"
		% [save_data.options.resolution, save_data.options.language])


## 启动时读设置存档并应用
func _autoload_options() -> void:
	var dict: Dictionary = _prepare_load(_read(OptionsSave.SLOT))
	if dict.is_empty():
		return

	save_data.from_dict(dict)
	save_data.validate_tree()
	_apply_options()
	CoreSystem.logger.info("[SaveService] 已读入并应用设置存档: %s" % OptionsSave.SLOT)

	var result: Types.SaveResult = _make_result(true, OptionsSave.SLOT, "", "options")
	result.metadata = save_data.metadata()
	result.data = save_data
	_emit(Events.LOAD_FINISHED, result)


## 把存档里的设置应用到引擎。项目特有的部分，以后加设置项就改这里
func _apply_options() -> void:
	var options: OptionsSave = save_data.options
	if options == null:
		# 正常不会发生（from_dict 会拒绝把分段设成 null），这里兜一手
		CoreSystem.logger.error("[SaveService] options 段丢失，已重建默认值")
		save_data.options = OptionsSave.new()
		options = save_data.options

	# 语言
	if TranslationServer.get_locale() != options.language:
		TranslationServer.set_locale(options.language)

	# 分辨率：OptionsData.FULLSCREEN（Vector2i.ZERO）代表全屏
	if options.resolution == OptionsData.FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(options.resolution)

	CoreSystem.logger.info("[SaveService] 已应用设置：resolution=%s language=%s"
		% [options.resolution, TranslationServer.get_locale()])

#endregion


#region 内部实现

## 要写进文件的字典。
## 设置档只有元数据 + options；其它槽位是元数据 + 除 options 外的所有分段
## （机器级设置不跟着游戏存档跑）。
func _payload_for(slot: String) -> Dictionary:
	if slot == OptionsSave.SLOT:
		var options_payload: Dictionary = save_data.metadata()
		options_payload["options"] = save_data.options.to_dict()
		return options_payload

	var game_payload: Dictionary = save_data.to_dict()
	game_payload.erase("options")
	return game_payload


## 原子写入：先写 <slot>.sav.tmp，写入无误后再改名覆盖正式文件
## var_to_bytes 本身就不编码对象（能编码对象的是 var_to_bytes_with_objects，这里不用）
func _write(slot: String) -> bool:
	var path: String = _path_for(slot)
	var tmp_path: String = path + ".tmp"

	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		CoreSystem.logger.error("[SaveService] 打不开临时存档文件: %s" % tmp_path)
		return false

	file.store_buffer(SAVE_MAGIC.to_ascii_buffer())
	file.store_buffer(var_to_bytes(_payload_for(slot)))
	var write_err: int = file.get_error()
	file.close()

	if write_err != OK:
		CoreSystem.logger.error("[SaveService] 写临时存档失败: %s（错误码 %d）" % [tmp_path, write_err])
		DirAccess.remove_absolute(tmp_path)
		return false

	# rename 会覆盖已存在的目标（Windows 上也一样，实测过）
	var rename_err: int = DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		CoreSystem.logger.error("[SaveService] 替换存档失败: %s（错误码 %d）" % [path, rename_err])
		DirAccess.remove_absolute(tmp_path)
		return false

	return true


## 读存档，返回纯数据字典；文件不存在 / 太小 / 太大 / 魔数不对 / 解码失败都返回 {}
## 关键：bytes_to_var 不还原对象，所以存档文件不可能带出任何可执行的东西
func _read(slot: String) -> Dictionary:
	var path: String = _path_for(slot)
	if not FileAccess.file_exists(path):
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		CoreSystem.logger.error("[SaveService] 打不开存档文件: %s" % path)
		return {}

	var length: int = file.get_length()
	if length < SAVE_MAGIC.length():
		file.close()
		CoreSystem.logger.error("[SaveService] 存档文件太小，不是有效存档: %s" % path)
		return {}
	if length > MAX_SAVE_BYTES:
		file.close()
		CoreSystem.logger.error("[SaveService] 存档文件过大（%d 字节），拒绝读取: %s" % [length, path])
		return {}

	var magic: String = file.get_buffer(SAVE_MAGIC.length()).get_string_from_ascii()
	if magic != SAVE_MAGIC:
		file.close()
		CoreSystem.logger.error("[SaveService] 不是本项目的存档文件（文件头不是 %s）: %s" % [SAVE_MAGIC, path])
		return {}

	var payload: PackedByteArray = file.get_buffer(length - SAVE_MAGIC.length())
	file.close()

	var data: Variant = bytes_to_var(payload)
	if data is Dictionary:
		return data

	CoreSystem.logger.error("[SaveService] 存档解码失败: %s" % path)
	return {}


## 读出"可以载入的字典"；返回空 = 拒绝载入（文件不存在 / 版本比程序新 / 迁移失败）。
## 注意：返回的可能是 migrate() 产生的新字典，所以调用方必须用返回值，
## 千万不要再去 clear 原来的 dict（migrate 默认就是原样返回同一个对象，原地清会把数据清没）。
func _prepare_load(dict: Dictionary) -> Dictionary:
	if dict.is_empty():
		return {}

	var file_version: int = int(dict.get("version", 0))
	if file_version == save_data.version:
		return dict

	if file_version > save_data.version:
		CoreSystem.logger.error("[SaveService] 存档版本 %d 比当前程序 %d 新，拒绝载入（请用新版程序打开）"
			% [file_version, save_data.version])
		return {}

	CoreSystem.logger.warning("[SaveService] 存档版本 %d 较旧（当前 %d），尝试迁移后载入"
		% [file_version, save_data.version])

	var migrated: Dictionary = save_data.migrate(dict, file_version)
	if migrated.is_empty():
		CoreSystem.logger.error("[SaveService] 迁移失败，拒绝载入")
		return {}

	migrated["version"] = save_data.version
	return migrated


## 槽位名合法性：只允许文件名安全的字符串，避免 "../" 之类越出存档目录。
## allow_empty = true 表示"留空"合法（存档时可以自动生成槽位）。
func _is_valid_slot(slot: String, allow_empty: bool) -> bool:
	if slot.is_empty():
		return allow_empty
	if slot.begins_with("."):
		return false
	for bad in SLOT_FORBIDDEN:
		if slot.contains(bad):
			return false
	return true


## 列出存档目录里所有槽位 ID（不含设置档，也不含 .tmp 残留）
func _list_slots() -> Array[String]:
	var slots: Array[String] = []
	if not DirAccess.dir_exists_absolute(_save_dir):
		return slots

	for file_name in DirAccess.get_files_at(_save_dir):
		if not file_name.ends_with(SAVE_EXTENSION):
			continue
		var slot: String = file_name.trim_suffix(SAVE_EXTENSION)
		if slot == OptionsSave.SLOT:
			continue
		slots.append(slot)
	slots.sort()
	return slots


## 槽位 ID → 存档文件路径
func _path_for(slot: String) -> String:
	return _save_dir.path_join(slot + SAVE_EXTENSION)


## 请求没给 slot 时自动生成一个；同秒内重复调用不会撞名
func _make_slot() -> String:
	var base: String = "save_%d" % int(Time.get_unix_time_from_system())
	var slot: String = base
	var counter: int = 1
	while FileAccess.file_exists(_path_for(slot)):
		slot = "%s_%d" % [base, counter]
		counter += 1
	return slot


## 写盘前补齐由服务负责的元数据
func _stamp(slot: String) -> void:
	save_data.slot = slot
	save_data.saved_at = Time.get_datetime_string_from_system()
	save_data.game_version = str(ProjectSettings.get_setting("application/config/version", ""))


## 组装结果对象
func _make_result(ok: bool, slot: String, error: String = "", reason: String = "manual") -> Types.SaveResult:
	var result: Types.SaveResult = Types.SaveResult.new()
	result.ok = ok
	result.slot = slot
	result.reason = reason
	result.error = error
	return result


## 发送结果事件
func _emit(event_name: String, result: Types.SaveResult) -> void:
	CoreSystem.event_bus.push_event(event_name, result)

#endregion
