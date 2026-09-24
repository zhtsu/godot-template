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
##   1 → 2（本次，**不兼容**）：元数据 slot / saved_at / game_version / playtime
##          从根上平铺移入 meta 分段（MetaSave）。字段本身没有增删，
##          `metadata()` 对外返回的键也**不变**；变的只是落盘字典形状与内存字段路径
##          （save_data.slot → save_data.meta.slot）。
##          这是一次性例外下的变更：模板尚未发布、无真实用户存档，
##          旧档策略取**显式拒绝**而不是写迁移（理由见 migrate()）。
##          **该例外已在本次用尽**：以后改结构 MUST 提升版本**并提供迁移路径**。
var version: int = 2

# ===== 分段：加一行就多一块存档内容 =====

## 元数据（槽位 ID、保存时间、当时游戏版本、累计游戏时长；前三个由 SaveService 自动填）
var meta: MetaSave = MetaSave.new()

## 设置界面选中的项（分辨率 / 语言）；候选列表在 core/options_data.gd
var options: OptionsSave = OptionsSave.new()


## 只取元数据，给存档列表用。
## 对外契约不变（FR-002）：仍是 v1 那 5 个平铺键，只是值取自 meta 段。
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
## v1 → v2 的策略是**显式拒绝**（不写迁移），理由：
##   1) 本次援引宪法原则 III 的**一次性例外**（模板未发布、不存在真实用户存档）；
##   2) 目标集合为空 —— 没有真实旧档，写出来的迁移无法被真实数据覆盖验证（research.md R4）；
##   3) 拒绝路径可验证：由 core/save_service.gd 给出**可区分**的失败原因，且不会半读入（FR-006）。
## 例外已在本次用尽：以后的结构变更 MUST 在这里按 from_version 逐级补字段（写迁移）。
func migrate(dict: Dictionary, from_version: int) -> Dictionary:
	push_warning("[SaveData] 存档结构版本 %d 过旧（v1 元数据平铺 → v2 meta 分段），本版本不提供迁移，拒绝载入"
		% from_version)
	return {}
