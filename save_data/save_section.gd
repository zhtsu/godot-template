class_name SaveSection
extends RefCounted

## 所有存档分段的基类：一个分段 = 一个类 = 一组普通 var 字段。
##
## 存档格式（见 core/save_service.gd）是**纯二进制的 Variant 数据**：
## 磁盘上只有值，没有任何脚本 / 资源引用；读档走 bytes_to_var()，
## 它是"不解码对象"的那一版 —— 所以存档文件无法承载、也无法触发任何逻辑。
##
## 规则：分段里只放数据字段（int / float / bool / String / Vector2 / Vector2i / Color /
## Array / Dictionary…），不要放节点或资源引用；放了会在 to_dict() 里被跳过并警告。
##
## 加一个新分段：
##   1) 本目录新建 xxx_save.gd：class_name XxxSave extends SaveSection
##   2) save_data.gd 里加一行：var xxx: XxxSave = XxxSave.new()
##   3) 可选：覆写 validate() 做范围 / 合法性修正（载入后会自动调用）
## 不用改 save_service.gd。

## 这些类型没法进纯数据存档：写进去会变成 null 或无意义的值，所以跳过并警告
const UNSUPPORTED_TYPES: Array[int] = [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]


## 本类（含继承链）声明的所有字段名（普通 var 也会被收到，不需要 @export）
func field_names() -> Dictionary:
	var fields: Dictionary = {}
	for prop in get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields[prop["name"]] = true
	return fields


## 转成纯数据字典；分段字段递归下钻，非数据类型跳过并警告
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for field in field_names():
		var value: Variant = get(field)
		if value is SaveSection:
			out[field] = value.to_dict()
		elif typeof(value) in UNSUPPORTED_TYPES:
			push_warning("[%s] 字段 '%s' 是 %s，纯数据存档存不了，已跳过（读档后会变回默认值）"
				% [_who(), field, type_string(typeof(value))])
		else:
			out[field] = value
	return out


## 从纯数据字典填回自己：分段字段递归下钻，所以每个分段对象的引用都不变（只覆盖叶子值）。
## 字典里没有的字段保持原值 —— 旧存档缺新加的字段时会自动用默认值。
func from_dict(dict: Dictionary) -> void:
	var fields: Dictionary = field_names()
	for field in fields:
		if not dict.has(field):
			continue

		var value: Variant = dict[field]
		var current: Variant = get(field)
		if current is SaveSection:
			if value is Dictionary:
				current.from_dict(value)
			else:
				# 分段字段只认字典：文件里是 null / 字符串一律拒绝，别把整段清空
				push_warning("[%s] 字段 '%s' 应该是分段数据，文件里是 %s，已忽略"
					% [_who(), field, type_string(typeof(value))])
		else:
			set(field, value)

	# 文件里有、本类没有的字段：多半是字段被改名 / 删掉之后的旧档
	for key in dict:
		if not fields.has(key):
			push_warning("[%s] 存档里有未知字段 '%s'，已忽略（改过字段名？考虑用 SaveData.version 做迁移）"
				% [_who(), key])


## 用字典打补丁：只认同名字段；值是字典且当前字段本身是分段时递归合并。
## 例：{"options": {"language": "en"}} 只改 language，options 里其它字段保持原样。
func apply_dict(patch: Dictionary) -> void:
	var fields: Dictionary = field_names()
	for key in patch:
		if not fields.has(key):
			push_warning("[%s] 没有字段 '%s'，已忽略（检查一下字段名）" % [_who(), key])
			continue

		var current: Variant = get(key)
		var value: Variant = patch[key]
		if current is SaveSection:
			if value is Dictionary:
				current.apply_dict(value)
			else:
				push_warning("[%s] 字段 '%s' 是分段，补丁必须是字典，已忽略" % [_who(), key])
		else:
			set(key, value)


## 载入之后自检：先递归所有分段，再调用本类的 validate()
func validate_tree() -> void:
	for field in field_names():
		var value: Variant = get(field)
		if value is SaveSection:
			value.validate_tree()
	validate()


## 自检钩子：子类覆写它修正非法 / 越界的数据（默认什么都不做）
func validate() -> void:
	pass


## 警告信息里用的名字
func _who() -> String:
	return get_script().resource_path.get_file()
