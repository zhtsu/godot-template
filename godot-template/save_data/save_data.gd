class_name SaveData
extends SaveSection

## 存档根：结构版本 + 元数据分段 + 各个分段。分段都在这个目录下各自一个类。
## 落盘格式是纯二进制 Variant 数据（core/save_service.gd 负责读写），
## 磁盘上不含任何脚本 / 资源引用。
##
## 加一个新分段只要两步（详见 save_section.gd）：
##   1) 新建 xxx_save.gd：class_name XxxSave extends SaveSection
##   2) 在下面"分段"区加一行：var xxx: XxxSave = XxxSave.new()

## SaveService 启动时会把它指向自己持有的那一份，方便各处只读访问：
##   SaveData.current.options.language
## 只读用；改数据仍然发事件（Events.SAVE_REQUEST），不要直接改这个引用。
static var current: SaveData = null

## 存档结构版本。版本号 MUST 与真实结构对应，改结构时 +1 并在 migrate() 里声明策略。
##
## 版本历史：
##   1 → 2（**不兼容**）：元数据 slot / saved_at / game_version / playtime 从根上平铺
##          移入 meta 分段（MetaSave）。字段本身没有增删，`metadata()` 对外返回的键也
##          **不变**；变的只是落盘字典形状与内存字段路径（save_data.slot → save_data.meta.slot）。
##          模板尚未发布、无真实用户存档，所以旧档策略取**显式拒绝**而不是写迁移（见 migrate()）。
##          这种"整版拒绝"只能来一次：以后改结构 MUST 提升版本**并提供迁移路径**。
##   2 → 3（**兼容**）：options 段新增三个音量字段（master_volume / music_volume / sfx_volume）。
##          旧档在 migrate() 里补齐默认值，**可继续读取**，不需要拒绝。
##   3 → 4（**兼容**）：options 段新增按键重映射表（input_bindings，动作名 → 物理键码）。
##          旧档补一个空表，界面上就显示默认按键。
var version: int = 4

# ===== 分段：加一行就多一块存档内容 =====

## 元数据（槽位 ID、保存时间、当时游戏版本、累计游戏时长；前三个由 SaveService 自动填）
var meta: MetaSave = MetaSave.new()

## 设置界面选中的项（分辨率 / 语言）；候选列表在 core/options_data.gd
var options: OptionsSave = OptionsSave.new()


## 只取元数据，给存档列表用。
## 对外契约不变：仍是 v1 那 5 个平铺键，只是值取自 meta 段（调用方与存档列表都不用改）。
func metadata() -> Dictionary:
	return {
		"version": version,
		"slot": meta.slot,
		"saved_at": meta.saved_at,
		"game_version": meta.game_version,
		"playtime": meta.playtime,
	}


## 旧档迁移钩子：载入的存档 version 低于当前 version 时会先调用它。
## 返回空字典 = 拒绝载入这个存档。
##
## 现存的三条规则：
##   - v1 → v2：**显式拒绝**。v1 的元数据还平铺在根上，没有 meta 段；模板尚未发布、
##     不存在真实用户存档，所以当时选择了拒绝而不是写迁移（一次性决定，见 version 的注释）。
##   - v2 → v3：**写迁移**。options 段新增三个音量字段，旧档补齐默认值即可继续读。
##   - v3 → v4：**写迁移**。options 段新增按键重映射表（input_bindings），旧档补空表。
## 以后的结构变更 MUST 走 v2 → v3 / v3 → v4 这种"按 from_version 逐级补齐字段"的路子，
## MUST NOT 再整体拒绝一整个版本。
func migrate(dict: Dictionary, from_version: int) -> Dictionary:
	if from_version >= version:
		return dict

	if from_version < 2:
		push_warning("[SaveData] 存档结构版本 %d 过旧（v1 元数据平铺 → v2 meta 分段），本版本不提供迁移，拒绝载入"
			% from_version)
		return {}

	var migrated: Dictionary = dict.duplicate(true)

	# v2 → v4：给 options 段补齐后加的字段。
	# 其实 from_dict 对"字典里没有的字段"本来就会保留默认值，这里显式补齐是为了让
	# 迁移后的落盘字段完整、且迁移逻辑本身可被断言（而不是靠 from_dict 的副作用）。
	if from_version < 4:
		var options_value: Variant = migrated.get("options", null)
		if options_value is Dictionary:
			var options_dict: Dictionary = options_value

			# v2 → v3：音量三件套
			if from_version < 3:
				if not options_dict.has("master_volume"):
					options_dict["master_volume"] = OptionsSave.DEFAULT_VOLUME
				if not options_dict.has("music_volume"):
					options_dict["music_volume"] = OptionsSave.DEFAULT_VOLUME
				if not options_dict.has("sfx_volume"):
					options_dict["sfx_volume"] = OptionsSave.DEFAULT_VOLUME

			# v3 → v4：按键重映射表（空表 = 全用 project.godot 的默认绑定）
			if not options_dict.has("input_bindings"):
				options_dict["input_bindings"] = {}

			migrated["options"] = options_dict

	migrated["version"] = version
	return migrated
