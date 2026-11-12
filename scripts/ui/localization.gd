extends RefCounted
## Round 34 Priority 9: localization FOUNDATION. Translations are built from
## the tables below at runtime (no editor import step needed) and looked up
## by KEY with tr(); missing keys/locales fall back to English. Covered so
## far: the main menu, pause menu, settings, credits, and a few common
## gameplay prompts (shift clock / sleep / laptop). The rest of the game is
## still English-only -- see MILESTONE1_DESIGN.md Round 34.
## Also gives the default UI font a CJK system-font FALLBACK (only used for
## glyphs the default font lacks, so Latin text keeps its look).

const TABLES := {
	"en": {
		"MENU_CONTINUE": "Continue", "MENU_NEW_GAME": "New Game", "MENU_LOAD": "Load Game",
		"MENU_SETTINGS": "Settings", "MENU_CREDITS": "Credits", "MENU_QUIT": "Quit",
		"MENU_BACK": "Back", "MENU_NO_SAVE": "No saved game yet",
		"MENU_NEW_CONFIRM": "Start a new game? Your saved progress is kept until you save again.",
		"MENU_START": "Start", "MENU_CANCEL": "Cancel",
		"SLOT_MANUAL": "Manual save", "SLOT_AUTOSAVE": "Autosave (start of day)", "SLOT_DAY": "Day %d", "SLOT_EMPTY": "empty",
		"PAUSE_TITLE": "Paused", "PAUSE_RESUME": "Resume", "PAUSE_SAVE": "Save Game", "PAUSE_MAIN_MENU": "Return to Main Menu",
		"SET_AUDIO": "Audio", "SET_VOL_Master": "Master volume", "SET_VOL_Ambient": "Ambient sound", "SET_VOL_SFX": "Effects",
		"SET_VOL_UI": "Interface", "SET_VOL_Voice": "Voice", "SET_DISPLAY": "Display", "SET_FULLSCREEN": "Fullscreen",
		"SET_WINDOW_SIZE": "Window size", "SET_INPUT": "Input", "SET_SENS": "Mouse sensitivity", "SET_INVERT": "Invert mouse Y",
		"SET_LANGUAGE": "Language", "SET_CONTROLS": "Controls", "SET_REDUCE_FX": "Reduce visual effects",
		"SET_BRIGHTNESS": "Brightness", "SET_THOUGHT_VOICE": "Spoken inner thoughts", "SET_THOUGHT_CAPTIONS": "Inner-thought captions",
		"SET_THOUGHT_VOLUME": "Inner-voice volume", "SET_THOUGHT_SOURCE": "Inner voice",
		"VOICE_SRC_RECORDED": "Recorded voice (installed voice pack)", "VOICE_SRC_SYSTEM": "Natural system voice: %s",
		"VOICE_SRC_OFF": "Captions only (spoken thoughts are off)",
		"VOICE_SRC_NONE": "Captions only — no natural voice installed. macOS: System Settings › Accessibility › Spoken Content › System Voice › Manage Voices… add an English (Enhanced or Premium) voice, then restart the game.",
		"CONTROLS_TEXT": "WASD move · Mouse look · Click interact · Space pick up / drop / stow · C wristwatch · E sit / get up (bunk) · G sleep (after the shift) · H repeat assistant · J skip assistant · Esc pause / close",
		"SET_AI": "Station assistant", "SET_AI_GUIDANCE": "Assistant guidance", "SET_AI_VOICE": "Assistant voice", "SET_AI_CAPTIONS": "Assistant captions", "SET_UI_SCALE": "Interface scale", "SET_STEADY_WARN": "Steady warning lights (no flashing)",
		"CREDITS_TITLE": "Credits",
		"PROMPT_OPEN_LAPTOP": "Click: Open Laptop", "SHIFT_REMAINING": "Shift in progress — %s remaining.",
		"SHIFT_ENDED": "Daily shift ended — you may return to your quarters.",
	},
	"zh_CN": {
		"MENU_CONTINUE": "继续游戏", "MENU_NEW_GAME": "新游戏", "MENU_LOAD": "读取存档",
		"MENU_SETTINGS": "设置", "MENU_CREDITS": "制作人员", "MENU_QUIT": "退出",
		"MENU_BACK": "返回", "MENU_NO_SAVE": "暂无存档",
		"MENU_NEW_CONFIRM": "开始新游戏？在你再次存档之前，现有存档会被保留。",
		"MENU_START": "开始", "MENU_CANCEL": "取消",
		"SLOT_MANUAL": "手动存档", "SLOT_AUTOSAVE": "自动存档（每日开始）", "SLOT_DAY": "第 %d 天", "SLOT_EMPTY": "空",
		"PAUSE_TITLE": "已暂停", "PAUSE_RESUME": "继续", "PAUSE_SAVE": "保存游戏", "PAUSE_MAIN_MENU": "返回主菜单",
		"SET_AUDIO": "音频", "SET_VOL_Master": "主音量", "SET_VOL_Ambient": "环境音", "SET_VOL_SFX": "音效",
		"SET_VOL_UI": "界面音效", "SET_VOL_Voice": "语音", "SET_DISPLAY": "显示", "SET_FULLSCREEN": "全屏",
		"SET_WINDOW_SIZE": "窗口大小", "SET_INPUT": "输入", "SET_SENS": "鼠标灵敏度", "SET_INVERT": "反转鼠标Y轴",
		"SET_LANGUAGE": "语言", "SET_CONTROLS": "操作说明", "SET_REDUCE_FX": "减少视觉效果",
		"SET_BRIGHTNESS": "亮度", "SET_THOUGHT_VOICE": "内心独白语音", "SET_THOUGHT_CAPTIONS": "内心独白字幕",
		"SET_THOUGHT_VOLUME": "内心独白音量", "SET_THOUGHT_SOURCE": "内心独白声音",
		"VOICE_SRC_RECORDED": "真人录音（已安装语音包）", "VOICE_SRC_SYSTEM": "自然系统语音：%s",
		"VOICE_SRC_OFF": "仅字幕（已关闭内心独白语音）",
		"VOICE_SRC_NONE": "仅字幕——未安装自然语音。macOS：系统设置 › 辅助功能 › 朗读内容 › 系统语音 › 管理语音…，添加中文（增强版或高级版）语音，然后重新启动游戏。",
		"CONTROLS_TEXT": "WASD 移动 · 鼠标 视角 · 点击 互动 · 空格 拾取/放下/收纳 · C 手表 · E 坐下/起身（床铺）· G 睡觉（班次结束后）· H 重复助手指令 · J 跳过 · Esc 暂停/关闭",
		"SET_AI": "站务助手", "SET_AI_GUIDANCE": "助手指引", "SET_AI_VOICE": "助手语音", "SET_AI_CAPTIONS": "助手字幕", "SET_UI_SCALE": "界面缩放", "SET_STEADY_WARN": "警示灯常亮（不闪烁）",
		"CREDITS_TITLE": "制作人员",
		"PROMPT_OPEN_LAPTOP": "点击：打开笔记本电脑", "SHIFT_REMAINING": "当班中——剩余 %s。",
		"SHIFT_ENDED": "今日班次结束——你可以返回宿舍。",
	},
}
const LANGUAGE_NAMES := {"en": "English", "zh_CN": "简体中文"}
static var _done: bool = false


static func setup() -> void:
	if _done:
		return
	_done = true
	for loc in TABLES:
		var t := Translation.new()
		t.locale = loc
		for k in TABLES[loc]:
			t.add_message(k, TABLES[loc][k])
		TranslationServer.add_translation(t)
	# CJK glyphs: system font fallback behind the default font (needs a real
	# display server; the headless server has no system fonts).
	if DisplayServer.get_name() == "headless":
		return
	# Round 36 fix: a SystemFont only resolves the FIRST of its font_names
	# (it does not fall through), and on macOS "PingFang SC" cannot be
	# loaded by FreeType (empty path: every startup logged "FreeType: Error
	# loading font: ''" and CJK text rendered BLANK). Probe each candidate in
	# its own SystemFont and keep the first that really has CJK glyphs.
	var sys: SystemFont = null
	for name in ["Hiragino Sans GB", "Heiti SC", "Songti SC", "Noto Sans CJK SC", "Source Han Sans SC", "Microsoft YaHei", "SimHei", "WenQuanYi Micro Hei"]:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([name])
		if f.has_char(0x4E2D):   # 中
			sys = f
			break
	var base: Font = ThemeDB.fallback_font
	if base != null and sys != null:
		var fb: Array[Font] = base.fallbacks.duplicate()
		fb.append(sys)
		base.fallbacks = fb
