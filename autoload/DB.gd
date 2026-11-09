class_name DB
extends RefCounted
## Dota Heroes 静态数据库：英雄 / 兵种 / 法术 / 技能 / 装备 / 建筑 / 剧情
## 数值为原型平衡值，集中放在这里方便后续调表。

const RES_ORDER := ["gold", "wood", "ore", "crystal", "essence"]

const RES := {
	"gold":    {"name": "金币",   "short": "金", "color": "#f2c14e", "daily": 500},
	"wood":    {"name": "木材",   "short": "木", "color": "#8fbf6a", "daily": 4},
	"ore":     {"name": "秘银矿", "short": "矿", "color": "#a9b6c6", "daily": 4},
	"crystal": {"name": "水晶",   "short": "晶", "color": "#7fd8f0", "daily": 2},
	"essence": {"name": "灵魂精华", "short": "魂", "color": "#c58be8", "daily": 1},
}

const FACTIONS := {
	"sentinel": {"name": "近卫军团", "color": "#5fb8e8", "dark": "#16394f", "desc": "守护世界之树的秩序之师"},
	"scourge":  {"name": "天灾军团", "color": "#e0645c", "dark": "#4a1c1c", "desc": "自冰封王座蔓延的亡灵与恶魔"},
	"neutral":  {"name": "中立",     "color": "#b8ac90", "dark": "#2b2a26", "desc": "游荡于荒野的生物"},
}

const TERRAIN := {
	"plain":    {"name": "平原",     "cost": 1,  "color": "#5b6b45"},
	"road":     {"name": "古道",     "cost": 1,  "color": "#8a7652"},
	"forest":   {"name": "幽暗森林", "cost": 2,  "color": "#314b33"},
	"hill":     {"name": "丘陵",     "cost": 2,  "color": "#6d6247"},
	"swamp":    {"name": "腐化沼泽", "cost": 3,  "color": "#46503c"},
	"mountain": {"name": "山脉",     "cost": 99, "color": "#595a61"},
	"water":    {"name": "深渊",     "cost": 99, "color": "#1d3247"},
}

# ---------------------------------------------------------------- 英雄
# atk 攻击 / def 防御 / power 力量(法伤) / knowledge 知识(魔法值、视野)
const HEROES := {
	"crystal_maiden": {
		"name": "水晶室女", "en": "Crystal Maiden", "title": "冰霜的传承者", "faction": "sentinel",
		"klass": "法师", "color": "#7fd8f0", "atk": 1, "def": 1, "power": 4, "knowledge": 4,
		"spells": ["frost_nova", "frost_armor", "arcane_bolt"],
		"skills": {"sorcery": 1, "wisdom": 1},
		"army": [{"unit": "militia", "count": 24}, {"unit": "archer", "count": 14}],
		"bio": "来自霜月山脉的法师，曾以一己之力冰封整条冰封之路。如今她带着近卫的旌旗重返战场，只为阻止天灾军团染指世界之树。",
	},
	"antimage": {
		"name": "敌法师", "en": "Anti-Mage", "title": "魔法的终结者", "faction": "sentinel",
		"klass": "战士", "color": "#9d7bff", "atk": 4, "def": 3, "power": 1, "knowledge": 2,
		"spells": ["mana_burn", "holy_light"],
		"skills": {"offense": 1, "logistics": 1},
		"army": [{"unit": "militia", "count": 30}, {"unit": "knight", "count": 5}],
		"bio": "他厌恶魔法，却生于魔法最为泛滥的年代。每一次闪烁，都是他对天灾法师们无声的宣判。",
	},
	"luna": {
		"name": "月之骑士", "en": "Luna", "title": "银月之刃", "faction": "sentinel",
		"klass": "游侠", "color": "#d9e6f2", "atk": 3, "def": 3, "power": 2, "knowledge": 2,
		"spells": ["arcane_bolt", "holy_light"],
		"skills": {"archery": 1, "leadership": 1},
		"army": [{"unit": "archer", "count": 22}, {"unit": "knight", "count": 7}],
		"bio": "月神殿最后的圣骑士。她的月刃在黑夜里划出银弧，为近卫军团照亮每一条被腐化的道路。",
	},
	"lina": {
		"name": "秀逗魔导师", "en": "Lina Inverse", "title": "焚尽一切的火焰", "faction": "sentinel",
		"klass": "法师", "color": "#ff9a52", "atk": 1, "def": 1, "power": 5, "knowledge": 3,
		"spells": ["dragon_slave", "laguna_blade", "arcane_bolt"],
		"skills": {"sorcery": 1, "archery": 1},
		"army": [{"unit": "militia", "count": 18}, {"unit": "priest", "count": 8}],
		"bio": "别被她的名字骗了。当龙破斩撕开夜空时，天灾的食尸鬼连灰烬都留不下。",
	},
	"skeleton_king": {
		"name": "骷髅王", "en": "Skeleton King", "title": "不眠的王者", "faction": "scourge",
		"klass": "战士", "color": "#d8b45a", "atk": 5, "def": 4, "power": 1, "knowledge": 1,
		"spells": ["holy_light", "frost_armor"],
		"skills": {"offense": 1, "armorer": 1},
		"army": [{"unit": "ghoul", "count": 30}, {"unit": "skeleton_archer", "count": 12}],
		"bio": "他曾是这片土地的王，如今只余一顶王冠与一具不朽的骨架。重生，是他最残酷的天赋。",
	},
	"nevermore": {
		"name": "影魔", "en": "Nevermore", "title": "灵魂的收藏家", "faction": "scourge",
		"klass": "刺客", "color": "#8b5cf0", "atk": 4, "def": 2, "power": 3, "knowledge": 2,
		"spells": ["shadowraze", "death_pulse", "arcane_bolt"],
		"skills": {"offense": 1, "logistics": 1},
		"army": [{"unit": "ghoul", "count": 22}, {"unit": "gargoyle", "count": 8}],
		"bio": "每一个倒在他面前的灵魂，都会成为他影压里的一声回响。他正在为世界之树准备一场盛大的魂之挽歌。",
	},
	"lich": {
		"name": "巫妖", "en": "Kel'Thuzad", "title": "霜之哀伤的祭司", "faction": "scourge",
		"klass": "法师", "color": "#79c7d6", "atk": 1, "def": 2, "power": 5, "knowledge": 4,
		"spells": ["frost_nova", "death_pulse", "frost_armor"],
		"skills": {"sorcery": 1, "wisdom": 1},
		"army": [{"unit": "skeleton_archer", "count": 20}, {"unit": "necromancer", "count": 7}],
		"bio": "被冰封王座复活的法师，把整座城邦变成了他的冰霜实验室。",
	},
	"axe": {
		"name": "斧王", "en": "Axe", "title": "血斧部族的统领", "faction": "scourge",
		"klass": "战士", "color": "#d0684c", "atk": 5, "def": 4, "power": 1, "knowledge": 1,
		"spells": ["holy_light", "mana_burn"],
		"skills": {"armorer": 1, "leadership": 1},
		"army": [{"unit": "ghoul", "count": 34}, {"unit": "ogre", "count": 6}],
		"bio": "他不讲战术，只讲谁先倒下。天灾需要这样一把不讲道理的斧头。",
	},
}

# ---------------------------------------------------------------- 兵种
# hp 单体生命 / atk 单体攻击 / def 单体防御 / spd 先攻 / move 战场移动 / range 射程
const UNITS := {
	# 近卫
	"militia":         {"name": "近卫民兵",   "faction": "sentinel", "tier": 1, "hp": 10, "atk": 3, "def": 2, "spd": 6,  "move": 4, "range": 1, "cost": 60,   "color": "#9fc3d8", "trait": ""},
	"archer":          {"name": "精灵弓手",   "faction": "sentinel", "tier": 2, "hp": 12, "atk": 4, "def": 2, "spd": 8,  "move": 4, "range": 6, "cost": 110,  "color": "#8fd6a0", "trait": "远程"},
	"priest":          {"name": "秘法祭司",   "faction": "sentinel", "tier": 3, "hp": 20, "atk": 6, "def": 3, "spd": 7,  "move": 4, "range": 5, "cost": 200,  "color": "#b9a7ef", "trait": "远程"},
	"knight":          {"name": "银月骑士",   "faction": "sentinel", "tier": 4, "hp": 34, "atk": 9, "def": 7, "spd": 9,  "move": 6, "range": 1, "cost": 340,  "color": "#e3e9f2", "trait": "冲锋"},
	"treant":          {"name": "树精卫士",   "faction": "sentinel", "tier": 5, "hp": 62, "atk": 11,"def": 11,"spd": 4,  "move": 3, "range": 1, "cost": 620,  "color": "#6fa15a", "trait": "高防"},
	"griffin":         {"name": "狮鹫骑士",   "faction": "sentinel", "tier": 6, "hp": 55, "atk": 15,"def": 8, "spd": 12, "move": 8, "range": 1, "cost": 950,  "color": "#f0d78a", "trait": "飞行"},
	# 天灾
	"ghoul":           {"name": "食尸鬼",     "faction": "scourge",  "tier": 1, "hp": 11, "atk": 3, "def": 2, "spd": 7,  "move": 4, "range": 1, "cost": 60,   "color": "#b0a58c", "trait": ""},
	"skeleton_archer": {"name": "骷髅弓手",   "faction": "scourge",  "tier": 2, "hp": 10, "atk": 4, "def": 2, "spd": 8,  "move": 4, "range": 6, "cost": 110,  "color": "#cfc7ad", "trait": "远程"},
	"necromancer":     {"name": "亡灵法师",   "faction": "scourge",  "tier": 3, "hp": 18, "atk": 7, "def": 3, "spd": 6,  "move": 4, "range": 5, "cost": 210,  "color": "#9b8fc4", "trait": "远程"},
	"gargoyle":        {"name": "石像鬼",     "faction": "scourge",  "tier": 4, "hp": 30, "atk": 9, "def": 7, "spd": 11, "move": 8, "range": 1, "cost": 350,  "color": "#8c93a0", "trait": "飞行"},
	"abomination":     {"name": "憎恶",       "faction": "scourge",  "tier": 5, "hp": 70, "atk": 12,"def": 9,  "spd": 4,  "move": 3, "range": 1, "cost": 640,  "color": "#7e9460", "trait": "高血"},
	"frost_drake":     {"name": "霜翼巨龙",   "faction": "scourge",  "tier": 6, "hp": 80, "atk": 17,"def": 10, "spd": 10, "move": 7, "range": 2, "cost": 1000, "color": "#86c9e0", "trait": "龙息"},
	# 中立野怪
	"kobold":          {"name": "狗头人",     "faction": "neutral",  "tier": 1, "hp": 8,  "atk": 2, "def": 1, "spd": 5,  "move": 4, "range": 1, "cost": 40,   "color": "#b98b5a", "trait": ""},
	"wolf":            {"name": "巨狼",       "faction": "neutral",  "tier": 2, "hp": 16, "atk": 5, "def": 3, "spd": 10, "move": 6, "range": 1, "cost": 100,  "color": "#8d8f96", "trait": ""},
	"ogre":            {"name": "食人魔",     "faction": "neutral",  "tier": 3, "hp": 40, "atk": 9, "def": 5, "spd": 4,  "move": 3, "range": 1, "cost": 250,  "color": "#b08a63", "trait": ""},
	"golem":           {"name": "岩石傀儡",   "faction": "neutral",  "tier": 4, "hp": 58, "atk": 10,"def": 12,"spd": 3,  "move": 3, "range": 1, "cost": 480,  "color": "#8b8477", "trait": "高防"},
}

# ---------------------------------------------------------------- 法术
# type: aoe / line / single / heal / buff_def / drain_all / bolt
const SPELLS := {
	"frost_nova":   {"name": "冰霜新星", "cost": 6,  "type": "aoe",      "power": 22, "radius": 1, "school": "冰霜", "desc": "目标格及相邻六格受到冰霜伤害，并降低其速度。"},
	"dragon_slave": {"name": "龙破斩",   "cost": 7,  "type": "line",     "power": 30, "radius": 0, "school": "火焰", "desc": "一道烈焰横贯战场，命中直线上的所有敌军。"},
	"laguna_blade": {"name": "神灭斩",   "cost": 14, "type": "single",   "power": 90, "radius": 0, "school": "火焰", "desc": "对单个敌军单位造成毁灭性伤害。"},
	"arcane_bolt":  {"name": "奥术弹",   "cost": 3,  "type": "single",   "power": 32, "radius": 0, "school": "奥术", "desc": "低消耗的单体魔法飞弹。"},
	"holy_light":   {"name": "神圣之光", "cost": 6,  "type": "heal",     "power": 45, "radius": 0, "school": "神圣", "desc": "治疗一支友军，并复活部分阵亡者。"},
	"frost_armor":  {"name": "霜甲术",   "cost": 5,  "type": "buff_def", "power": 4,  "radius": 0, "school": "冰霜", "desc": "为一支友军附加护甲，本场战斗减免伤害。"},
	"death_pulse":  {"name": "死亡脉冲", "cost": 10, "type": "drain_all","power": 18, "radius": 0, "school": "亡灵", "desc": "对所有敌军造成伤害，并为施法者恢复生命与魔法。"},
	"mana_burn":    {"name": "法力损毁", "cost": 4,  "type": "single",   "power": 26, "radius": 0, "school": "奥术", "desc": "灼烧敌方英雄的魔法值并造成额外伤害。"},
	"shadowraze":   {"name": "影压",     "cost": 5,  "type": "aoe",      "power": 20, "radius": 1, "school": "暗影", "desc": "暗影爆发，灼烧一片区域内的敌军。"},
}

# ---------------------------------------------------------------- 英雄技能（第二技能，最高 3 级）
const SKILLS := {
	"logistics":  {"name": "后勤学", "icon": "行", "desc": "每级 +2 每日移动力"},
	"offense":    {"name": "进攻术", "icon": "攻", "desc": "每级 +8% 全军伤害"},
	"armorer":    {"name": "防御术", "icon": "守", "desc": "每级 -6% 全军受伤"},
	"sorcery":    {"name": "魔力",   "icon": "魔", "desc": "每级 +18% 法术效果"},
	"wisdom":     {"name": "智慧",   "icon": "智", "desc": "每级 +6 魔法上限、每回合额外回魔"},
	"archery":    {"name": "箭术",   "icon": "箭", "desc": "每级 +12% 远程伤害"},
	"leadership": {"name": "统帅",   "icon": "帅", "desc": "每级 +6% 全军伤害、"},
}

# ---------------------------------------------------------------- 装备
const SLOTS := ["weapon", "armor", "helm", "boots", "trinket", "book"]
const SLOT_NAMES := {"weapon": "武器", "armor": "护甲", "helm": "头盔", "boots": "靴子", "trinket": "饰品", "book": "法书"}

const ITEMS := {
	"iron_sword": {"name": "铁剑",         "slot": "weapon",  "price": 900,  "atk": 2, "desc": "朴素但可靠。"},
	"sny":        {"name": "散夜对剑",     "slot": "weapon",  "price": 3400, "atk": 4, "spd": 1, "desc": "双刃如风，先攻 +1。"},
	"bkb":        {"name": "黑皇杖",       "slot": "weapon",  "price": 3900, "atk": 3, "def": 3, "desc": "天神下凡，攻守兼备。"},
	"plate":      {"name": "板甲",         "slot": "armor",   "price": 1100, "def": 3, "desc": "近卫锻造的重甲。"},
	"shiva":      {"name": "希瓦的守护",   "slot": "armor",   "price": 3800, "def": 5, "power": 2, "desc": "极寒之力凝成的护胸。"},
	"crown":      {"name": "王者之冠",     "slot": "helm",    "price": 1600, "power": 2, "knowledge": 2, "desc": "属于骷髅王生前的东西。"},
	"helm":       {"name": "支配头盔",     "slot": "helm",    "price": 1800, "atk": 1, "def": 2, "desc": "令野怪俯首。"},
	"boots":      {"name": "速度之靴",     "slot": "boots",   "price": 900,  "mp": 3, "spd": 1, "desc": "每日移动力 +3。"},
	"travel":     {"name": "远行鞋",       "slot": "boots",   "price": 2700, "mp": 6, "spd": 1, "desc": "每日移动力 +6。"},
	"linken":     {"name": "林肯法球",     "slot": "trinket", "price": 2900, "def": 2, "mana": 12, "desc": "一次法术抵挡，魔法上限 +12。"},
	"amulet":     {"name": "魔力护符",     "slot": "trinket", "price": 1000, "mana": 8, "desc": "魔法上限 +8。"},
	"aghanim":    {"name": "阿哈利姆神杖", "slot": "book",    "price": 4200, "power": 5, "mana": 10, "desc": "极大强化英雄的法术。"},
	"necrobook":  {"name": "死灵书",       "slot": "book",    "price": 2700, "power": 2, "atk": 2, "desc": "召唤死灵助战。"},
}

# ---------------------------------------------------------------- 城镇建筑
const BUILDINGS := {
	"hall":       {"name": "城镇大厅", "max": 3, "cost": {"gold": 2500, "wood": 10, "ore": 8}, "desc": "城镇根基。每级每日 +500 金币。", "icon": "城"},
	"barracks":   {"name": "兵营",     "max": 1, "cost": {"gold": 1200, "wood": 8,  "ore": 4},  "desc": "解锁 1 级兵种招募。", "icon": "兵"},
	"archery":    {"name": "射手营地", "max": 1, "cost": {"gold": 1800, "wood": 12, "ore": 4},  "desc": "解锁远程兵种招募。", "icon": "弓"},
	"mage_tower": {"name": "魔法塔",   "max": 3, "cost": {"gold": 2200, "wood": 5,  "ore": 5, "crystal": 5}, "desc": "每级提供新法术与每日回魔。", "icon": "塔"},
	"tavern":     {"name": "酒馆",     "max": 1, "cost": {"gold": 1500, "wood": 6},  "desc": "可花费金币招募新的英雄。", "icon": "酒"},
	"forge":      {"name": "铁匠铺",   "max": 1, "cost": {"gold": 1600, "wood": 5,  "ore": 8},  "desc": "可购买 Dota 装备。", "icon": "锻"},
	"market":     {"name": "市场",     "max": 1, "cost": {"gold": 1200, "wood": 8},  "desc": "开放资源互换。", "icon": "市"},
	"wall":       {"name": "城墙",     "max": 1, "cost": {"gold": 2000, "ore": 15},  "desc": "守城战中全军防御 +3。", "icon": "墙"},
	"silo":       {"name": "资源仓库", "max": 1, "cost": {"gold": 1000, "wood": 10}, "desc": "每日额外产出各类资源各 1。", "icon": "仓"},
}

# 各阵营可招募的兵种（按建筑等级解锁）
const RECRUITS := {
	"sentinel": ["militia", "archer", "priest", "knight", "treant", "griffin"],
	"scourge":  ["ghoul", "skeleton_archer", "necromancer", "gargoyle", "abomination", "frost_drake"],
}

# ---------------------------------------------------------------- 剧情
const STORY_INTRO := [
	"世界之树的根须仍在燃烧。自冰封王座苏醒之日起，天灾军团的亡灵浪潮已吞没了北境三座城邦。",
	"近卫军团退守至银月城，最后的法师们在魔法塔里点亮了古老的奥术灯火。你，是议会选中的统帅。",
	"探索迷雾、夺取矿脉、重建城镇、集结英雄 —— 在下一个血月升起前，把战线推回冰封王座。",
	"「不是每一场战争都由剑决定。有时，它由一个回合决定。」 —— 水晶室女",
]

const LORE := [
	{"title": "世界之树", "text": "近卫军团守护的远古巨树，其根系贯穿整片大陆。传说若树心被腐化，所有生灵的记忆都会被天灾抹去。"},
	{"title": "冰封王座", "text": "极北之地的一块寒冰，囚禁着巫妖王意志。天灾军团的每一具骷髅，都能听见从那里传来的低语。"},
	{"title": "天灾与近卫", "text": "两支军团的战争已持续了三个纪元。河道是天然的国境线，河以北是亡灵，河以南是生者。"},
	{"title": "肉山", "text": "沉睡在远古遗迹中的不朽巨兽。冒险者们说，杀死它的人会得到不朽之守护，但从未有人回来证实。"},
	{"title": "英雄与统帅", "text": "在这片大陆上，一名英雄可以抵得上一支军队。英雄会成长、会习得技能、会握起神杖 —— 这是与纯粹帝国经营最大的不同。"},
	{"title": "矿脉与魔力", "text": "金币、木材、秘银、水晶与灵魂精华，是支撑战争运转的五种血脉。占领矿场，比打赢一场遭遇战更重要。"},
]

const EVENTS := [
	{"title": "流浪商人", "text": "一支商队穿过迷雾，愿意用一批物资换取庇护。你获得了 800 金币。", "effect": {"gold": 800}},
	{"title": "月神赐福", "text": "银月洒满营地，所有英雄的魔法值完全恢复。", "effect": {"mana": 99}},
	{"title": "腐化蔓延", "text": "北境的腐化又浓了一分，一支野怪营地在你未探索的区域扎下根来。", "effect": {"camp": 1}},
	{"title": "古老的藏宝图", "text": "斥候在废墟中找到一张残图，你获得少量水晶与灵魂精华。", "effect": {"crystal": 3, "essence": 2}},
	{"title": "老兵归队", "text": "一批退伍的近卫战士加入了你的城镇守备军。", "effect": {"troops": 1}},
	{"title": "魔法潮汐", "text": "奥术潮汐席卷大陆，魔法塔的学者们借此为英雄们补满了法力。", "effect": {"mana": 99}},
]

const TIPS := [
	"点击大地图上高亮的六边形移动英雄；灰色迷雾区域无法进入。",
	"每回合的移动力有限，「后勤学」和「速度之靴」能让你走得更远。",
	"占领矿场是滚雪球的关键，越早扩张，后期招兵越轻松。",
	"战斗中按兵种速度决定行动顺序，远程单位在贴身时伤害减半。",
	"英雄每回合可施放一次法术，法术不计入部队的行动。",
	"点击敌方英雄或野怪营地即可发起战斗，胜利后获得经验与装备。",
]

static func level_xp(level: int) -> int:
	return int(700.0 * pow(float(level), 1.45))

static func unit_hp_pool(count: int, top_hp: int, unit_id: String) -> int:
	return max(0, (count - 1) * int(UNITS[unit_id].hp) + top_hp)

static func hero_max_mp(hero: Dictionary) -> int:
	var base := 12 + int(hero.skill.get("logistics", 0)) * 2
	for slot in SLOTS:
		var it: String = hero.items.get(slot, "")
		if it != "" and ITEMS.has(it):
			base += int(ITEMS[it].get("mp", 0))
	return base

static func hero_max_mana(hero: Dictionary) -> int:
	var base := 10 * int(hero.knowledge) + int(hero.skill.get("wisdom", 0)) * 6
	for slot in SLOTS:
		var it: String = hero.items.get(slot, "")
		if it != "" and ITEMS.has(it):
			base += int(ITEMS[it].get("mana", 0))
	return base

## 计算装备加成后的最终四维
static func hero_stats(hero: Dictionary) -> Dictionary:
	var s := {"atk": int(hero.atk), "def": int(hero.defense), "power": int(hero.power), "knowledge": int(hero.knowledge), "spd": 0}
	for slot in SLOTS:
		var it: String = hero.items.get(slot, "")
		if it != "" and ITEMS.has(it):
			for k in ["atk", "def", "power", "knowledge", "spd"]:
				s[k] += int(ITEMS[it].get(k, 0))
	return s

static func res_text(cost: Dictionary) -> String:
	var out := ""
	for k in RES_ORDER:
		if cost.has(k) and int(cost[k]) > 0:
			if out != "":
				out += "   "
			out += "%s %d" % [RES[k].name, int(cost[k])]
	return out if out != "" else "无"

static func can_afford(res: Dictionary, cost: Dictionary) -> bool:
	for k in cost:
		if int(res.get(k, 0)) < int(cost[k]):
			return false
	return true

static func pay(res: Dictionary, cost: Dictionary) -> void:
	for k in cost:
		res[k] = int(res.get(k, 0)) - int(cost[k])

static func gain(res: Dictionary, reward: Dictionary) -> void:
	for k in reward:
		res[k] = int(res.get(k, 0)) + int(reward[k])
