class_name MetaSave
extends SaveSection

## 存档元数据分段（v2 引入）。
##
## 这四个字段**全部是从 SaveData 根上平铺搬过来的既有字段**，没有新增语义：
##   v1 落盘：{ "version": 1, "slot": ..., "saved_at": ..., "game_version": ..., "playtime": ... }
##   v2 落盘：{ "version": 2, "meta": { "slot": ..., "saved_at": ..., "game_version": ..., "playtime": ... } }
##
## 为什么要搬：根上只留"结构版本 + 各个分段"，元数据不再和版本号挤在同一层，
## 与"一段一个类"的既有约定一致（见 save_section.gd 的新增分段三步法）。
##
## 对外契约不变：SaveData.metadata() 仍返回原来那 5 个平铺键，只是值取自这里。
##
## 没有需要范围校验的字段，因此不覆写 validate()。

## 槽位 ID（由 SaveService._stamp() 写入）
var slot: String = ""
## 保存时间（本地时间字符串，既有格式不变）
var saved_at: String = ""
## 保存时的游戏版本（取自 application/config/version；该设置缺失时为空串）
var game_version: String = ""
## 累计游戏时长（秒）
var playtime: float = 0.0
