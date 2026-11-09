extends Node
## Round 36 Priority 5: the STATION OPERATIONS ASSISTANT -- ordinary station
## automation heard over the internal speakers: calm, professional, brief.
## No body, no portrait, no personality arc, no hidden identity.
##
## EVENT-DRIVEN from real state only (no parallel quest system):
##   - DayPlan.order_rows(): each assignment's NEXT physical step (`short`)
##     and its completion -> first-time step lines / acknowledgements;
##   - the day-1 orientation fields (c01/e06/c05/c02/e05) and the workday;
##   - arriving near a piece of equipment whose task is open (first time);
##   - real alarms: breaker trips, Bus A overload, cabin pressure / O2;
##   - explicit equipment hooks: interlocks, a missing part (event()).
## PRIORITY: safety (0) > first-time instruction (1) > information (2). A
## safety line interrupts anything lower. Non-safety lines wait while a
## focused equipment view is open, during sleep / wake transitions and
## while the tree is paused. One line at a time; never repeats a lesson
## (taught keys are saved); safety repeats only after a cooldown.
## CONTROLS: H repeats the last instruction (or states the current task),
## J skips. SETTINGS (GameSettings): ai_guidance, ai_voice, ai_captions;
## speech volume follows the Master x Voice settings.

const GS = preload("res://scripts/station/game_settings.gd")
const Speech = preload("res://scripts/audio/speech_provider.gd")
enum Prio { SAFETY, INSTRUCT, INFO }

@export var day_plan_path: NodePath = ^"../DayPlan"
@export var hud_path: NodePath = ^"../Player/HUD"
@export var player_path: NodePath = ^"../Player/LookPivot/PitchPivot/Camera3D"

## key -> [prio, en, zh_CN]
const LINES := {
	&"intro_greet": [Prio.INFO, "Good morning, Technician. Station Operations online. Your shift is ready.", "早上好，技术员。站务系统已上线，你的班次已就绪。"],
	&"intro_job": [Prio.INFO, "Your job is maintenance: keep the station's systems running and report what you find.", "你的工作是维护：保持空间站各系统运转，并报告发现的问题。"],
	&"intro_watch": [Prio.INSTRUCT, "Press C to raise your wristwatch. It shows your next assignment and the shift clock.", "按 C 抬起手表，查看下一项任务和班次时间。"],
	&"intro_getup": [Prio.INSTRUCT, "Press E to get up, then report to the Control Room workstation.", "按 E 起身，然后前往控制室工作站。"],
	&"intro_control": [Prio.INSTRUCT, "Report to the Control Room workstation for today's briefing.", "请前往控制室工作站查看今日简报。"],
	&"ws_intro": [Prio.INSTRUCT, "The station map shows where work is needed. Orange is routine, red is an emergency. Select a room.", "站务地图显示哪里需要处理：橙色为例行维护，红色为紧急情况。点选一个舱室。"],
	&"ws_checkin": [Prio.INSTRUCT, "Press CHECK IN to start your shift.", "按“签到”开始你的班次。"],
	&"ws_auto": [Prio.INFO, "Orders close automatically once the equipment is verified. There is no report to file.", "设备验证后工单会自动关闭，无需另行提交。"],
	&"d1_e06": [Prio.INSTRUCT, "Engineering reports a loose connection. Tighten it in Engineering.", "工程舱报告一处连接松动，请到工程舱拧紧。"],
	&"d1_e06_done": [Prio.INSTRUCT, "Connection secured. Verify the repair at the workstation.", "连接已紧固。请到工作站验证维修。"],
	&"d1_c05_done": [Prio.INSTRUCT, "Repair verified. Run the power diagnostic at the workstation.", "维修已验证。请在工作站运行电源诊断。"],
	&"d1_fault": [Prio.INSTRUCT, "The diagnostic shows a fault on the Engineering power circuit. Work Orders lists the spare you need.", "诊断显示工程舱电源电路有故障，工单上列出了所需备件。"],
	&"d1_repair_done": [Prio.INSTRUCT, "Power restored. Verify the repair at the workstation.", "电力已恢复。请在工作站验证维修。"],
	&"elec_intro": [Prio.INSTRUCT, "Electrical service: isolate the circuit before you disconnect anything. Work one terminal at a time.", "电气维修：断开任何部件前先隔离电路，每次只处理一个端子。"],
	&"storage_intro": [Prio.INSTRUCT, "Storage: spares sit on labelled shelves. Space picks a part up; Space at its shelf stows it.", "储藏室：备件放在有标签的架子上。按空格拾取，在对应架子前按空格收纳。"],
	&"breaker_intro": [Prio.INSTRUCT, "Breaker panel EPS-2. A lit red lamp marks a tripped breaker. Check its fault lamp before you reset it.", "断路器面板 EPS-2。红灯亮表示已跳闸；复位前先查看故障灯。"],
	&"breaker_cause": [Prio.SAFETY, "That breaker re-trips: its cause is still present. Clear the cause first.", "该断路器会再次跳闸：故障原因仍在，请先排除。"],
	&"breaker_done": [Prio.INFO, "Power restored. The circuit is operating normally.", "供电已恢复，电路运行正常。"],
	&"overload_warn": [Prio.SAFETY, "Warning: Bus A overload. Reduce channel output at the distribution panel.", "警告：A 母线过载。请在配电面板降低通道输出。"],
	&"overload_trip": [Prio.SAFETY, "Breaker B-03 tripped. Emergency lighting active in Engineering. Balance Bus A, then reset it.", "B-03 已跳闸，工程舱应急照明启动。先平衡 A 母线，再复位。"],
	&"emerg_overload": [Prio.SAFETY, "Warning. Engineering power overload. Breaker trip imminent.", "警告：工程舱电力过载，断路器即将跳闸。"],
	&"emerg_30": [Prio.SAFETY, "Thirty seconds to breaker trip.", "距断路器跳闸还有三十秒。"],
	&"emerg_clear": [Prio.INFO, "Overload cleared. Bus A stable.", "过载已解除，A 母线稳定。"],
	&"vent_intro": [Prio.INSTRUCT, "Check the airflow gauge, then release both retaining clips before opening the cover.", "先查看气流表，然后在打开盖板前松开两个固定卡扣。"],
	&"vent_open": [Prio.INSTRUCT, "Clips released. Open the grille.", "卡扣已松开，打开格栅。"],
	&"vent_clean": [Prio.INSTRUCT, "Remove debris from the blocked sections.", "清除堵塞区段的杂物。"],
	&"vent_close": [Prio.INSTRUCT, "Close the grille and secure both clips.", "关闭格栅并扣紧两个卡扣。"],
	&"vent_done": [Prio.INFO, "Airflow restored.", "气流已恢复。"],
	&"power_intro": [Prio.INSTRUCT, "Power distribution: set each channel's output to match its demand. A sustained overload trips B-03.", "配电：将各通道输出调至与需求一致。持续过载会使 B-03 跳闸。"],
	&"power_done": [Prio.INFO, "Bus A balanced and stable.", "A 母线已平衡并稳定。"],
	&"seal_intro": [Prio.INSTRUCT, "Hatch seal: set the lever to INSPECT, examine all four sections, and correct any fault you find.", "舱门密封：将拨杆拨至检查，逐一检查四个区段，并修正发现的故障。"],
	&"seal_fix": [Prio.INSTRUCT, "Fault found: debris, a twisted clip, or a rolled gasket lip. Click the section to correct it.", "发现故障：杂物、扭曲的卡扣或翻出的密封唇。点击该区段进行修正。"],
	&"seal_test": [Prio.INSTRUCT, "Seal corrected. Secure the hatch, then run the pressure-hold test.", "密封已修正。锁紧舱门后进行保压测试。"],
	&"seal_done": [Prio.INFO, "Seal holds. No leak detected.", "密封良好，未检测到泄漏。"],
	&"interlock_cargo": [Prio.SAFETY, "Interlock: the airlock hatch cannot be inspected during a cargo transfer.", "联锁：货物转运期间无法检查气闸舱门。"],
	&"interlock_seal": [Prio.SAFETY, "Interlock: secure the hatch seal before operating the cargo port.", "联锁：操作货运口前请先锁紧舱门密封。"],
	&"data_intro": [Prio.INSTRUCT, "Diagnostic transfer: take module DM-7 to the Engineering capture port, capture, then bring it back here.", "诊断传输：把 DM-7 模块带到工程舱采集端口采集数据，再带回这里。"],
	&"data_capture": [Prio.INSTRUCT, "Seat the module, then press CAPTURE.", "插入模块，然后按采集。"],
	&"data_return": [Prio.INSTRUCT, "Data captured. Return the module to the Control Room upload dock.", "数据已采集。把模块送回控制室上传底座。"],
	&"data_stale": [Prio.INSTRUCT, "That data is stale: the station changed since capture. Recapture in Engineering.", "数据已过期：采集后空间站状态有变化。请回工程舱重新采集。"],
	&"data_done": [Prio.INFO, "Diagnostics uploaded.", "诊断数据已上传。"],
	&"thermal_intro": [Prio.INSTRUCT, "Thermal survey: take probe TP-3 to terminal block TB-A in Engineering and measure all three terminals.", "热巡检：把探头 TP-3 带到工程舱 TB-A 端子排，测量全部三个端子。"],
	&"thermal_hot": [Prio.INSTRUCT, "A terminal is running hot: a loose lug. Re-torque it, then measure it again.", "有端子过热：接线鼻松动。重新拧紧后再次测量。"],
	&"thermal_dock": [Prio.INSTRUCT, "Readings normal. Dock the probe in Control to upload the survey.", "读数正常。把探头放回控制室底座上传巡检数据。"],
	&"thermal_done": [Prio.INFO, "Survey uploaded. Bus A terminals normal.", "巡检已上传，A 母线端子正常。"],
	&"filter_intro": [Prio.INSTRUCT, "Filter service: isolate airflow, release the latches, and fit a clean cartridge from Storage. Note how the housing was found.", "滤芯维护：先隔离气流，松开锁扣，换上储藏室的新滤芯。注意滤壳当前的状态。"],
	&"filter_get": [Prio.INSTRUCT, "Retrieve a clean filter cartridge from Storage.", "从储藏室取一枚新滤芯。"],
	&"filter_missing": [Prio.SAFETY, "You need a clean filter cartridge from Storage for this step.", "这一步需要储藏室的新滤芯。"],
	&"filter_dispose": [Prio.INSTRUCT, "Dispose of the used cartridge in the Storage disposal unit.", "将旧滤芯丢入储藏室的回收装置。"],
	&"filter_done": [Prio.INFO, "Filter service complete.", "滤芯维护完成。"],
	&"calib_intro": [Prio.INSTRUCT, "Sensor calibration: bring both coupled chambers into range and hold them steady.", "传感器校准：将两个耦合腔调入范围并保持稳定。"],
	&"coolant_intro": [Prio.INSTRUCT, "Coolant routing: re-route flow at the valve manifold as the work order describes.", "冷却液路由：按工单说明在阀门组重新分配流向。"],
	&"comms_intro": [Prio.INSTRUCT, "Communications check: run the routine signal check at the comms console.", "通信检查：在通信台进行例行信号检查。"],
	&"rounds_intro": [Prio.INSTRUCT, "Inspection round: read each status tag and log it. The workstation cross-checks your readings.", "巡检：读取并记录每个状态标签，工作站会交叉核对读数。"],
	&"cargo_intro": [Prio.INSTRUCT, "Cargo receiving: check the shipment ID, open the hatch, release the restraint, then carry the tray to Storage.", "货物接收：核对货单编号，打开舱门，松开固定装置，再把托盘搬到储藏室。"],
	&"cargo_return": [Prio.INSTRUCT, "Return the empty carrier tray to the cargo port and secure the hatch.", "把空托盘送回货运口并锁紧舱门。"],
	&"cargo_done": [Prio.INFO, "Shipment received and stowed.", "货物已接收并收纳。"],
	&"disposal_intro": [Prio.INSTRUCT, "Used parts go in the disposal unit. Click it while you hold the part.", "旧部件放入回收装置：手持部件时点击它。"],
	&"shift_end_first": [Prio.INFO, "Shift complete. Unfinished work carries over. Rest in your quarters when you are ready.", "班次结束，未完成的工作会顺延。准备好后回宿舍休息。"],
	&"shift_end": [Prio.INFO, "Shift complete.", "班次结束。"],
	&"env_pressure": [Prio.SAFETY, "Cabin pressure is falling. Inspect the airlock hatch seal.", "舱内气压正在下降，请检查气闸舱门密封。"],
	&"env_o2": [Prio.SAFETY, "Oxygen below nominal. Restore Life Support airflow.", "氧气低于正常值，请恢复生命维持气流。"],
	&"repeat_none": [Prio.INFO, "No active instruction.", "当前没有指令。"],
	&"eva_suit": [Prio.INSTRUCT, "Suit on. Step into the airlock chamber and press OUT.", "宇航服已穿好。进入气闸舱后按“出舱”。"],
	&"eva_outside": [Prio.INSTRUCT, "Tether A is on the hatch ring. W thrusts toward your aim. S brakes.", "安全绳 A 已扣在舱口挂环。按 W 朝准星方向推进，按 S 制动。"],
	&"tether_switch": [Prio.INFO, "Both tethers secure. Now release the old one: R.", "两条安全绳都已扣好。现在按 R 解开旧的那条。"],
	&"tether_intro": [Prio.INSTRUCT, "Tether ring. Click it to clip your free tether. Keep one secured at all times.", "安全绳挂环。点击它扣上空闲的安全绳，始终保持一条扣着。"],
	&"eva_repair": [Prio.INSTRUCT, "Work position. Hands free. W pushes off.", "作业位已固定，双手可用。按 W 蹬离。"],
	# Round 41: dual tethers, aim-and-push movement, solar array work.
	&"eva_aim": [Prio.INSTRUCT, "Aim at your destination. Your tethers limit how far you travel.", "瞄准目的地。安全绳会限制你的移动范围。"],
	&"solar_intro": [Prio.INSTRUCT, "Solar truss. Follow the rings. Clip the next ring before you release the last.", "太阳能桁架。沿挂环前进：先扣下一个挂环，再解开上一个。"],
	&"coupler_live": [Prio.SAFETY, "That coupler is live. Isolate the string first.", "该耦合器带电。请先隔离该组串。"],
	&"eva_interlock": [Prio.SAFETY, "Airlock interlock. Check the suit, the cargo port and the hatch seal.", "气闸联锁：请检查宇航服、货运口和舱门密封。"],
	# Round 39: airlock chamber, EVA tasks, daily routine, end of shift.
	&"airlock_intro": [Prio.INSTRUCT, "Airlock control. Press OUT. Inner seals, chamber vents, outer opens. IN reverses it.", "气闸控制。按“出舱”：内门密封、舱室泄压、外门打开。“进舱”反向执行。"],
	&"airlock_cycle_out": [Prio.INFO, "Sealing inner hatch. Venting.", "正在密封内舱门，泄压中。"],
	&"airlock_cycle_in": [Prio.INFO, "Sealing outer hatch. Pressurizing.", "正在密封外舱门，加压中。"],
	&"lens_intro": [Prio.INSTRUCT, "Exterior camera lens is fouled. Wipe it on EVA, then check the feed again.", "外部摄像头镜头脏污。出舱擦拭后再次检查画面。"],
	&"meal_intro": [Prio.INSTRUCT, "Galley. Eat and drink every day. It counts toward your shift.", "厨房。每天都要吃饭喝水，这计入你的班次。"],
	&"underfed": [Prio.INFO, "You skipped a meal. Eat first. You will be slower until you do.", "你漏了一餐。先吃东西，否则你会变慢。"],
	&"work_complete": [Prio.INFO, "Required work complete. Wrap up, then go to your bunk.", "必要工作已完成。收尾后回到床铺。"],
	&"bed_reminder": [Prio.INFO, "Your shift is over. Get some rest.", "班次已结束，去休息吧。"],
	&"antenna_intro": [Prio.INSTRUCT, "Antenna A1 feed box: open the cover, service the connector, then close the cover.", "A1 天线馈线盒：打开盖板，处理接头，然后关闭盖板。"],
	&"comms_link_intro": [Prio.INSTRUCT, "Comms link panel. Test the link here before and after the antenna repair.", "通信链路面板。在天线维修前后都在这里测试链路。"],
	&"tools_intro": [Prio.INSTRUCT, "Instrument rack: airflow meter for Life Support test ports, leak detector for pressure seals.", "仪器架：气流计用于生命维持测试口，检漏仪用于压力密封。"],
	&"port_intro": [Prio.INFO, "Observation port. Exterior cameras on the workstation cover the same area.", "观察窗。工作站上的外部摄像头覆盖同一区域。"],
}
## Speech-only spellings (captions keep the written designations).
const SPOKEN := {"EPS-2": "E P S 2", "B-03": "B 3", "DM-7": "D M 7", "TP-3": "T P 3", "TB-A": "T B A"}


static func spoken_form(text: String) -> String:
	var t := text
	for k in SPOKEN:
		t = t.replace(k, SPOKEN[k])
	return t


## Lines that are not lessons (may play again: alarms, acknowledgements of
## a later day's events, dynamic lines) -- never added to `taught`.
const REPEATABLE := [&"coupler_live", &"underfed", &"work_complete", &"bed_reminder", &"eva_interlock", &"breaker_cause", &"overload_warn", &"overload_trip", &"emerg_overload", &"emerg_30", &"emerg_clear", &"interlock_cargo", &"interlock_seal", &"filter_missing", &"env_pressure", &"env_o2", &"shift_end", &"repeat_none", &"outage", &"shift_day", &"repeat_task"]
const SAFETY_COOLDOWN_S := 75.0

## Equipment topics: anchor node (relative to the station root), first-
## arrival radius, intro line, and whether its task is open right now.
const TOPICS := {
	&"breaker": ["Equipment/BreakerPanel", 2.2, &"breaker_intro"],
	&"vent": ["Equipment/VentGrille", 2.0, &"vent_intro"],
	&"power": ["Equipment/PowerDistribution", 2.0, &"power_intro"],
	&"seal": ["Equipment/HatchSeal", 2.4, &"seal_intro"],
	&"data": ["Equipment/UploadPort", 1.8, &"data_intro"],
	&"thermal": ["Equipment/ThermalSurvey", 1.8, &"thermal_intro"],
	&"filter": ["Interactables/FilterHousingStation", 2.2, &"filter_intro"],
	&"calib": ["Interactables/SensorCalibrationStation", 2.2, &"calib_intro"],
	&"coolant": ["Interactables/ValveRoutingStation", 2.2, &"coolant_intro"],
	&"comms": ["Interactables/SignalCalibrationStation", 2.4, &"comms_intro"],
	&"elec": ["Geometry/EngineeringCabinet1", 2.2, &"elec_intro"],
	&"storage": ["Geometry/StorageCabinet2", 2.6, &"storage_intro"],
	&"cargo": ["Interactables/CargoPort", 2.4, &"cargo_intro"],
	&"disposal": ["Interactables/TrashDisposal", 2.0, &"disposal_intro"],
	&"antenna": ["Equipment/AntennaMast/FeedBox", 1.8, &"antenna_intro"],
	&"comms_link": ["Equipment/AntennaMast/CommsLinkPanel", 1.8, &"comms_link_intro"],
	&"tools": ["Equipment/ToolRack", 1.6, &"tools_intro"],
	&"airlock": ["AirlockChamber/Panel_chamber", 1.9, &"airlock_intro"],
	&"tether_ring": ["TetherAnchors/Anchor1", 2.2, &"tether_intro"],
	&"eva_worksite": ["Equipment/AntennaMast/FeedBox", 2.4, &"eva_repair"],
	&"solar_truss": ["TetherAnchors/Anchor4", 2.6, &"solar_intro"],
	&"galley": ["Equipment/QuartersLife/Galley", 1.9, &"meal_intro"],
}
## Step narration: (tag, next-step short[@room]) -> line.
const STEP_KEYS := {
	"VENT": {"OPEN GRILLE": &"vent_open", "CLEAN": &"vent_clean", "CLOSE GRILLE": &"vent_close"},
	"BREAKER": {"FIX CAUSE": &"breaker_cause"},
	"SEAL": {"FIX": &"seal_fix", "SECURE HATCH": &"seal_test"},
	"DATA": {"CAPTURE DATA": &"data_capture", "RECAPTURE": &"data_stale", "TAKE MODULE@engineering": &"data_return"},
	"THERMAL": {"TORQUE": &"thermal_hot", "DOCK PROBE": &"thermal_dock"},
	"FILTER": {"GET FILTER": &"filter_get", "DISPOSE OLD": &"filter_dispose"},
	"ROUNDS": {"LOG FILTER": &"rounds_intro"},
	"CARGO": {"RETURN TRAY": &"cargo_return"},
}
## A task's step lines / completion only play once its equipment intro has
## been heard (the player is actually doing that job, not elsewhere).
const TAG_INTRO := {"VENT": &"vent_intro", "BREAKER": &"breaker_intro", "SEAL": &"seal_intro", "DATA": &"data_intro", "THERMAL": &"thermal_intro", "LOADS": &"power_intro", "FILTER": &"filter_intro", "CARGO": &"cargo_intro"}
const DONE_KEYS := {"VENT": &"vent_done", "BREAKER": &"breaker_done", "SEAL": &"seal_done", "DATA": &"data_done", "THERMAL": &"thermal_done", "LOADS": &"power_done", "FILTER": &"filter_done", "CARGO": &"cargo_done"}
const PRIORITY_WORDS := {
	"BREAKER": ["Power restoration", "恢复供电"], "VENT": ["Ventilation cleaning", "通风清洁"], "LOADS": ["Load balancing", "负载平衡"],
	"SEAL": ["Hatch seal inspection", "舱门密封检查"], "DATA": ["Diagnostic transfer", "诊断传输"], "THERMAL": ["The thermal survey", "热巡检"],
	"FILTER": ["Life Support filter service", "生命维持滤芯维护"], "SENSORS": ["Sensor calibration", "传感器校准"], "WIRING": ["Electrical service", "电气维修"],
	"COOLANT": ["Coolant routing", "冷却液路由"], "ROUNDS": ["The inspection round", "巡检"], "COMMS": ["The communications check", "通信检查"], "CARGO": ["Cargo receiving", "货物接收"],
}

# --------------------------------------------------------------- state
var taught: Dictionary = {}        # key -> true (saved)
var intro_done: bool = false       # saved
var last_day_announced: int = 0    # saved
var last_instruction: Dictionary = {}   # {key, args} (saved)
var history: Array = []            # displayed lines this session [{key, prio, text, backend}]
var _queue: Array = []             # [{key, prio, args}]
var _current: Dictionary = {}
var _line_t: float = 0.0
var _line_min_s: float = 0.0
var _gap_t: float = 0.0
var _speech_started: bool = false
var _chime_t: float = -1.0
var _poll_t: float = 0.0
var _alive_t: float = 0.0
var _awake_since: float = -1.0
var _row_short: Dictionary = {}
var _row_tag: Dictionary = {}
var _tripped: Dictionary = {}
var _tripped_init: bool = false
var _overload_was: bool = false
var _env_sev_was: int = 0
var _cool: Dictionary = {}         # key -> time left
var _last_day_polled: int = -1
var _emerg_id: String = ""
var _emerg_30: bool = false
var _d1: Dictionary = {}
var _dp: Node
var _speech: Node
var _chime: AudioStreamPlayer
# caption UI
var _layer: CanvasLayer
var _panel: PanelContainer
var _source: Label
var _text: Label
var _hint: Label
var _light: ColorRect


func _ready() -> void:
	add_to_group(&"station_ai")
	_dp = get_node_or_null(day_plan_path)
	_speech = Speech.new()
	_speech.name = "Speech"
	add_child(_speech)
	_chime = AudioStreamPlayer.new()
	_chime.name = "Chime"
	_chime.bus = "Voice" if AudioServer.get_bus_index("Voice") != -1 else "Master"
	_chime.stream = _build_chime()
	_chime.volume_db = -8.0
	add_child(_chime)
	_build_caption()
	_prewarm.call_deferred()
	if _dp != null:
		if _dp.has_signal("shift_ended_signal"):
			_dp.shift_ended_signal.connect(_on_shift_ended)
	var ss: Node = _station().get_node_or_null("SleepState")
	if ss != null and ss.has_signal("woke_into_new_day"):
		ss.woke_into_new_day.connect(_on_new_day)


## Round 37: the physical intercom speakers (positional voice).
func _speakers() -> Node:
	var sp: Node = get_tree().get_first_node_in_group(&"station_speakers") if is_inside_tree() else null
	if _speech != null and _speech.speakers != sp:
		_speech.speakers = sp
	return sp


func _prewarm() -> void:
	_speakers()
	var lang: String = _lang()
	var lines: Array = []
	for k in LINES:
		var t: String = line_text(k, [], lang)
		lines.append([spoken_form(t) if lang == "en" else t, lang])
	_speech.prewarm(lines)


## The unit that speaks to the player right now.
func listener_unit() -> StringName:
	var eva: Node = get_tree().get_first_node_in_group(&"eva_system") if is_inside_tree() else null
	if eva != null and eva.outside:
		return &"suit_radio"
	var sp: Node = _speakers()
	var cam: Node3D = get_node_or_null(player_path) as Node3D
	if sp == null or cam == null:
		return &""
	return sp.unit_for(cam.global_position)


func _exit_tree() -> void:
	if _speech != null:
		_speech.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		if _speech != null:
			_speech.stop()
		if _panel != null:
			_panel.visible = false
	elif what == NOTIFICATION_UNPAUSED:
		_update_caption()


func _station() -> Node:
	return get_parent()


# ============================================================== settings
func enabled() -> bool:
	return bool(GS.get_value("ai_guidance"))


func voice_on() -> bool:
	return bool(GS.get_value("ai_voice"))


func captions_on() -> bool:
	return bool(GS.get_value("ai_captions"))


## Turns the assistant off/on (persisted setting). Off stops at once.
func set_enabled(on: bool) -> void:
	GS.set_value("ai_guidance", on)
	if not on:
		skip(true)


func _lang() -> String:
	return Speech.lang_family(String(GS.get_value("language")))


# ================================================================== API
## Queues a line. `args` fill a dynamic line's %s placeholders. Lessons
## already taught are ignored (returns false).
func say_key(key: StringName, args: Array = [], prio: int = -1) -> bool:
	if not enabled():
		return false
	if not LINES.has(key) and not key in [&"outage", &"shift_day", &"repeat_task"]:
		return false
	if taught.has(key) and not key in REPEATABLE:
		return false
	if _cool.get(key, 0.0) > 0.0:
		return false
	if not _current.is_empty() and _current["key"] == key:
		return false
	for q in _queue:
		if q["key"] == key:
			return false
	var p: int = prio if prio >= 0 else (int(LINES[key][0]) if LINES.has(key) else Prio.SAFETY)
	if not key in REPEATABLE:
		taught[key] = true
	var item := {"key": key, "prio": p, "args": args}
	if p == Prio.SAFETY:
		_cool[key] = SAFETY_COOLDOWN_S
		# Safety first: interrupt a lower-priority line.
		if not _current.is_empty() and int(_current["prio"]) > Prio.SAFETY:
			_finish_line()
			_gap_t = 0.0
		_queue.push_front(item)
	else:
		# Non-safety lines keep their order (a lesson's lines in sequence).
		_queue.append(item)
	return true


## Equipment hooks (interlocks, wrong part, ...).
func event(key: StringName) -> void:
	say_key(key)


func clear_queue() -> void:
	_queue.clear()
	_finish_line()


## J: skip the current line (all = also drop everything queued).
func skip(all: bool = false) -> void:
	if all:
		_queue.clear()
	_finish_line()


## H: repeat the last instruction, or state the current task.
func repeat_instruction() -> void:
	if not enabled():
		return
	if not last_instruction.is_empty():
		var k: StringName = StringName(last_instruction["key"])
		_queue.push_front({"key": k, "prio": Prio.INSTRUCT, "args": last_instruction.get("args", []), "repeat": true})
		_finish_line()
		return
	var g: Dictionary = _dp.guidance() if _dp != null and _dp.has_method("guidance") else {}
	if g.is_empty():
		_queue.push_front({"key": &"repeat_none", "prio": Prio.INFO, "args": [], "repeat": true})
	else:
		var room: String = _dp.ROOM_SHORT.get(StringName(g.get("room", &"")), "")
		_queue.push_front({"key": &"repeat_task", "prio": Prio.INFO, "args": [String(g.get("label", g.get("short", ""))), room], "repeat": true})
	_finish_line()


func is_showing() -> bool:
	return not _current.is_empty()


func current_key() -> StringName:
	return StringName(_current.get("key", &""))


func caption_text() -> String:
	return _text.text if _text != null and _panel.visible else ""


func is_speaking() -> bool:
	return _speech != null and _speech.is_speaking()


func speech_backend() -> String:
	return _speech.backend_name(_lang()) if _speech != null else "none"


func spoken_log() -> Array:
	return _speech.spoken_log if _speech != null else []


func line_text(key: StringName, args: Array = [], lang: String = "") -> String:
	var l: String = lang if lang != "" else _lang()
	var zh: bool = l == "zh"
	match key:
		&"outage":
			return ("%s照明中断。断路器 %s 已跳闸，面板位于工程舱。" if zh else "Lighting lost in %s. Breaker %s has tripped; the panel is in Engineering.") % args
		&"shift_day":
			return ("第 %d 天。今日安排 %d 项任务。当前优先：%s。%s" if zh else "Day %d. %s scheduled. %s is the current priority.%s") % args
		&"repeat_task":
			return ("当前任务：%s（%s）。" if zh else "Current task: %s. %s.") % args
	var row: Array = LINES.get(key, [Prio.INFO, "", ""])
	return String(row[2] if zh else row[1])


# ============================================================ main loop
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# Only in free roam: the laptop editor, the seated workstation and the
	# focused views own the keyboard (typing "h" must reach the log).
	var ic: Node = get_node_or_null(player_path)
	if ic == null or not ic.interactions_enabled:
		return
	if event.keycode == KEY_H:
		repeat_instruction()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_J and is_showing():
		skip()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_alive_t += delta
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - delta
		if float(_cool[k]) <= 0.0:
			_cool.erase(k)
	if not enabled():
		if not _current.is_empty() or not _queue.is_empty():
			skip(true)
		return
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = 0.25
		_poll_world()
	_run_queue(delta)


func _awake() -> bool:
	var ss: Node = _station().get_node_or_null("SleepState")
	if ss != null and ss.has_method("is_sleeping") and ss.is_sleeping():
		return false
	var eyes: ColorRect = get_node_or_null(String(hud_path) + "/EyesOverlay") as ColorRect
	if eyes != null and eyes.visible and eyes.color.a > 0.3:
		return false
	return true


## Hold non-safety lines while a focused view / transition owns the screen.
func _busy_for(prio: int) -> bool:
	if prio == Prio.SAFETY:
		return not _awake()
	if not _awake():
		return true
	var f: Node = _station().get_node_or_null("FocusedInteractionState")
	if f != null and f.has_method("is_active") and f.is_active():
		return true
	var ws: Node = _station().get_node_or_null("WorkstationState")
	if ws != null and "_tween" in ws and ws._tween != null and ws._tween.is_valid() and ws._tween.is_running():
		return true
	return false


func _focused_active() -> bool:
	var f: Node = _station().get_node_or_null("FocusedInteractionState")
	return f != null and f.has_method("is_active") and f.is_active()


func _run_queue(delta: float) -> void:
	# A focused view took the screen mid-line: pause the (non-safety) line
	# and replay it once the view closes, instead of covering the view.
	if not _current.is_empty() and int(_current["prio"]) != Prio.SAFETY and (_focused_active() or not _awake()):
		var again: Dictionary = {"key": _current["key"], "prio": _current["prio"], "args": _current.get("args", []), "repeat": true}
		_finish_line()
		_gap_t = 0.0
		_queue.push_front(again)
		return
	if not _current.is_empty():
		_line_t += delta
		if _chime_t >= 0.0:
			_chime_t -= delta
			if _chime_t < 0.0:
				_start_speech()
		var speaking: bool = _speech.is_speaking()
		if _line_t >= _line_min_s and not speaking and _chime_t < 0.0:
			_finish_line()
		elif _line_t >= _line_min_s * 3.0 + 4.0:
			_finish_line()   # never stall on a synthesizer that went quiet
		_update_caption()
		return
	if _gap_t > 0.0:
		_gap_t -= delta
		return
	if _queue.is_empty():
		return
	var nxt: Dictionary = _queue[0]
	if _busy_for(int(nxt["prio"])):
		return
	_queue.pop_front()
	_begin_line(nxt)


func _begin_line(item: Dictionary) -> void:
	_current = item
	_line_t = 0.0
	var text: String = line_text(item["key"], item.get("args", []))
	_current["text"] = text
	var zh: bool = _lang() == "zh"
	_line_min_s = maxf(2.6, text.length() * (0.2 if zh else 0.062)) + 0.5
	if int(item["prio"]) <= Prio.INSTRUCT and not item.get("repeat", false):
		last_instruction = {"key": String(item["key"]), "args": item.get("args", [])}
	_speech_started = false
	_current["unit"] = listener_unit()   # fixed for the whole line
	if voice_on() and Speech.effective_volume() > 0:
		var sp: Node = _speakers()
		if String(item["key"]).begins_with("emerg_"):
			_chime_t = 1.25   # the room's alert tone is sounding: wait it out, no chime
		elif sp != null and _current["unit"] != &"":
			sp.play_tone(_current["unit"], _chime.stream, -8.0)
			_chime_t = 0.38
		else:
			_chime.play()
			_chime_t = 0.38
	else:
		_chime_t = -1.0
		_current["backend"] = "captions only (voice off)" if not voice_on() else "muted (Voice volume 0)"
	history.append({"key": String(item["key"]), "prio": int(item["prio"]), "text": text, "t": _alive_t})
	_update_caption()


func _start_speech() -> void:
	if _current.is_empty() or _speech_started:
		return
	_speech_started = true
	_current["backend"] = _speech.speak(_current["key"], spoken_form(_current["text"]) if _lang() == "en" else _current["text"], _lang(), StringName(_current.get("unit", &"")))
	var sp: Node = _speakers()
	if sp != null:
		# OS-TTS fallback is not positional, but the source unit still lights.
		sp.set_lit(StringName(_current.get("unit", &"")) if String(_current["backend"]) == "tts" else &"")
	history[history.size() - 1]["backend"] = _current["backend"]


func _finish_line() -> void:
	if _speech != null:
		_speech.stop()
	var sp: Node = _speakers() if is_inside_tree() else null
	if sp != null:
		sp.set_lit(&"")
	_chime_t = -1.0
	if not _current.is_empty():
		_gap_t = 0.6
	_current = {}
	_update_caption()


# =============================================================== caption
func _build_caption() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "AICaptionLayer"
	_layer.layer = 4
	add_child(_layer)
	var root := Control.new()
	root.name = "AICaption"
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.offset_left = -400.0
	root.offset_right = 400.0
	root.offset_top = 98.0
	root.offset_bottom = 170.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.06, 0.72)
	sb.border_color = Color(0.25, 0.4, 0.42, 0.8)
	sb.border_width_left = 3
	sb.set_content_margin_all(8)
	sb.content_margin_left = 12
	_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_panel.add_child(h)
	var lv := VBoxContainer.new()
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(lv)
	_light = ColorRect.new()
	_light.custom_minimum_size = Vector2(9, 9)
	_light.color = Color(0.3, 0.9, 0.85)
	lv.add_child(_light)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	_source = Label.new()
	_source.add_theme_font_size_override("font_size", 11)
	_source.add_theme_color_override("font_color", Color(0.5, 0.8, 0.78))
	v.add_child(_source)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 17)
	_text.add_theme_color_override("font_color", Color(0.92, 0.94, 0.92))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(620, 0)
	v.add_child(_text)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.62, 0.62))
	v.add_child(_hint)
	_panel.visible = false
	_ignore_mouse(_layer)


## Round 37: captions are display-only -- no part of them may swallow a
## click meant for the laptop / world / UI underneath.
static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


func _update_caption() -> void:
	if _panel == null:
		return
	var show: bool = not _current.is_empty() and captions_on() and enabled() and not get_tree().paused
	_panel.visible = show
	if not show:
		return
	# Over a full-screen equipment view (safety lines only): top-right corner.
	var root: Control = _panel.get_parent() as Control
	var ws: Node = _station().get_node_or_null("WorkstationState")
	if _focused_active():
		root.anchor_left = 1.0; root.anchor_right = 1.0; root.anchor_top = 0.0; root.anchor_bottom = 0.0
		root.offset_left = -560.0; root.offset_right = -12.0; root.offset_top = 8.0; root.offset_bottom = 80.0
		_text.custom_minimum_size = Vector2(500, 0)
	elif ws != null and ws.has_method("is_in_use") and ws.is_in_use():
		# Seated: the screen fills the top of the view -- caption low,
		# above the HUD task-message line.
		root.anchor_left = 0.5; root.anchor_right = 0.5; root.anchor_top = 1.0; root.anchor_bottom = 1.0
		root.offset_left = -400.0; root.offset_right = 400.0; root.offset_top = -205.0; root.offset_bottom = -125.0
		_text.custom_minimum_size = Vector2(620, 0)
	else:
		root.anchor_top = 0.0; root.anchor_bottom = 0.0
		root.anchor_left = 0.5; root.anchor_right = 0.5
		root.offset_left = -400.0; root.offset_right = 400.0; root.offset_top = 98.0; root.offset_bottom = 170.0
		_text.custom_minimum_size = Vector2(620, 0)
	var zh: bool = _lang() == "zh"
	_source.text = ("站务系统" if zh else "STATION OPS") + ("  ·  警告" if zh and int(_current["prio"]) == Prio.SAFETY else ("  ·  CAUTION" if int(_current["prio"]) == Prio.SAFETY else ""))
	_text.text = String(_current.get("text", ""))
	_hint.text = "[H] 重复   [J] 跳过" if zh else "[H] repeat   [J] skip"
	var speaking: bool = _speech != null and _speech.is_speaking()
	var base: Color = Color(1.0, 0.55, 0.2) if int(_current["prio"]) == Prio.SAFETY else Color(0.3, 0.9, 0.85)
	_light.color = base if speaking or _chime_t >= 0.0 else base.darkened(0.6)


func _build_chime() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.34)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t: float = float(i) / rate
		var f: float = 880.0 if t < 0.15 else 660.0
		var lt: float = t if t < 0.15 else t - 0.15
		var env: float = exp(-lt * 14.0) * minf(lt * 200.0, 1.0)
		var smp: float = (sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.0 * t) * 0.15) * env * 0.5
		bytes.encode_s16(i * 2, int(clampf(smp, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = bytes
	return s


# ========================================================= world polling
func _poll_world() -> void:
	if _dp == null:
		return
	var awake: bool = _awake()
	if awake and _awake_since < 0.0:
		_awake_since = _alive_t
	elif not awake:
		_awake_since = -1.0
	var settled: bool = awake and _alive_t - _awake_since >= 1.2 and _alive_t >= 2.0
	if not settled:
		return
	_poll_intro()
	_poll_workstation()
	_poll_day1()
	_poll_rows()
	_poll_topics()
	_poll_alarms()


func _ss() -> Node:
	return _station().get_node_or_null("SleepState")


func _poll_intro() -> void:
	if intro_done or int(_dp.day_number) != 1:
		if int(_dp.day_number) > 1:
			intro_done = true
		return
	intro_done = true
	say_key(&"intro_greet")
	say_key(&"intro_job")
	say_key(&"intro_watch")
	var ss: Node = _ss()
	var in_bunk: bool = ss != null and ss.has_method("is_sitting") and (ss.is_sitting() or ss.is_lying_in_bed())
	say_key(&"intro_getup" if in_bunk else &"intro_control")
	last_day_announced = 1


func _on_new_day() -> void:
	# Called after a sleep -> wake (a NEW day): announce the day once.
	_announce_day.call_deferred()


func _announce_day() -> void:
	if _dp == null or int(_dp.day_number) <= last_day_announced:
		return
	last_day_announced = int(_dp.day_number)
	var rows: Array = _dp.order_rows().filter(func(r): return not r.get("done", false))
	if rows.is_empty():
		return
	rows.sort_custom(func(a, b): return int(a["priority"]) > int(b["priority"]))
	var zh: bool = _lang() == "zh"
	var n: int = rows.size()
	var count: String = ("%d 项" % n) if zh else (["", "One assignment is", "Two assignments are", "Three assignments are", "Four assignments are", "Five assignments are", "Six assignments are"][n] if n <= 6 else "%d assignments are" % n)
	var first: String = PRIORITY_WORDS.get(String(rows[0]["tag"]), [String(rows[0]["tag"]), String(rows[0]["tag"])])[1 if zh else 0]
	var follow: String = ""
	if rows.size() > 1:
		var second: String = PRIORITY_WORDS.get(String(rows[1]["tag"]), [String(rows[1]["tag"]), String(rows[1]["tag"])])[1 if zh else 0]
		follow = ("随后：%s。" % second) if zh else " %s can follow." % second
	say_key(&"shift_day", [int(_dp.day_number), n if zh else count, first, follow], Prio.INFO)


func _poll_workstation() -> void:
	var ws: Node = _station().get_node_or_null("WorkstationState")
	if ws == null or not ws.has_method("is_in_use") or not ws.is_in_use():
		return
	say_key(&"ws_intro")
	if not _dp.is_task_done(&"c01"):
		say_key(&"ws_checkin")
	else:
		say_key(&"ws_auto")


func _poll_day1() -> void:
	if int(_dp.workday) != 0:
		return
	var st := {"e06": _dp.assignment_task_id == &"e06", "e06_done": _dp.is_task_done(&"e06"), "c05": _dp.is_task_done(&"c05"), "fault": _dp.fault_target == &"engineering_power", "e05": _dp.is_task_done(&"e05")}
	if st["e06"] and not st["e06_done"]:
		say_key(&"d1_e06")
	if st["e06_done"] and not st["c05"]:
		say_key(&"d1_e06_done")
	if st["c05"] and not st["fault"]:
		say_key(&"d1_c05_done")
	if st["fault"] and not st["e05"]:
		say_key(&"d1_fault")
	if st["e05"] and not _d1.get("e05_seen", false):
		_d1["e05_seen"] = true
		say_key(&"d1_repair_done")


func _poll_rows() -> void:
	var seen := {}
	for r in _dp.order_rows():
		var id: String = String(r["id"])
		var tag: String = String(r["tag"])
		if r.get("done", false):
			if _row_short.has(id):
				_row_done(tag)
				_row_short.erase(id)
			continue
		seen[id] = true
		_row_tag[id] = tag
		var short: String = String(r.get("short", ""))
		var room: String = String(r.get("room", ""))
		if _row_short.get(id, "") != short:
			_row_short[id] = short
			_step_line(tag, short, room)
	for id in _row_short.keys():
		if not seen.has(id):
			_row_done(String(_row_tag.get(id, "")))
			_row_short.erase(id)


## Round 38: practised families get no routine step narration.
const TAG_FAMILY := {"VENT": "life_support", "BREAKER": "electrical", "LOADS": "electrical", "THERMAL": "electrical", "SEAL": "mechanical", "DATA": "communications", "ANTENNA": "communications", "FILTER": "life_support", "EXT CAM": "eva", "SOLAR PNL": "eva", "SOLAR CPL": "electrical", "SOLAR HNG": "mechanical"}


func _proficient(tag: String) -> bool:
	return TAG_FAMILY.has(tag) and _dp != null and _dp.has_method("proficiency_level") and _dp.proficiency_level(TAG_FAMILY[tag]) >= 3


func _step_line(tag: String, short: String, room: String) -> void:
	if TAG_INTRO.has(tag) and not taught.has(TAG_INTRO[tag]):
		return
	if _proficient(tag):
		return
	var table: Dictionary = STEP_KEYS.get(tag, {})
	if table.is_empty():
		return
	var key: Variant = table.get("%s@%s" % [short, room], table.get(short, table.get(short.get_slice(" ", 0), null)))
	if key != null:
		say_key(key)


func _row_done(tag: String) -> void:
	if TAG_INTRO.has(tag) and not taught.has(TAG_INTRO[tag]):
		return
	if DONE_KEYS.has(tag):
		say_key(DONE_KEYS[tag])


func _topic_active(t: StringName) -> bool:
	var W = _dp.Workday
	match t:
		&"breaker", &"vent", &"power", &"seal", &"data", &"thermal":
			return _dp.has_open_order(t)
		&"filter":
			return int(_dp.workday) == W.FILTER_SERVICE and not _dp.is_work_order_closed()
		&"calib":
			return int(_dp.workday) == W.CALIBRATION and not _dp.is_work_order_closed()
		&"coolant":
			return int(_dp.workday) == W.COOLANT_INSPECTION and not _dp.is_work_order_closed()
		&"comms":
			return int(_dp.workday) == W.COMMS_CHECK and not _dp.is_work_order_closed()
		&"elec":
			return (int(_dp.workday) == W.ELECTRICAL_SERVICE and not _dp.is_work_order_closed()) or (_dp.fault_target == &"engineering_power" and not _dp.is_task_done(&"e05"))
		&"storage":
			var g: Dictionary = _dp.guidance()
			return StringName(g.get("room", &"")) == &"storage" or (int(_dp.workday) == 0 and _dp.required_component_id != &"" and not _dp.is_task_done(&"e05"))
		&"cargo":
			return _dp.cargo_duty == "open"
		&"antenna", &"comms_link":
			return _dp.has_open_order(&"antenna")
		&"tools":
			return true
		&"airlock":
			var eva: Node = get_tree().get_first_node_in_group(&"eva_system")
			return (eva != null and eva.suited) or _dp.has_open_order(&"antenna") or _dp.has_open_order(&"lens") or _dp.has_open_order(&"solar_clean") or _dp.has_open_order(&"solar_coupler") or _dp.has_open_order(&"solar_hinge")
		&"tether_ring", &"eva_worksite", &"solar_truss":
			var e2: Node = get_tree().get_first_node_in_group(&"eva_system")
			return e2 != null and e2.outside
		&"galley":
			return _dp.has_method("meal_done") and not _dp.meal_done()
		&"disposal":
			var cs: Node = _station().get_node_or_null("Player/CarrySystem")
			return cs != null and cs.is_carrying() and cs.carried_item_id() == &"used_filter_cartridge"
	return false


func _poll_topics() -> void:
	var cam: Node3D = get_node_or_null(player_path) as Node3D
	if cam == null:
		return
	var p: Vector3 = cam.global_position
	for t in TOPICS:
		var key: StringName = TOPICS[t][2]
		if taught.has(key):
			continue
		var anchor: Node3D = _station().get_node_or_null(TOPICS[t][0]) as Node3D
		if anchor == null:
			continue
		var d: Vector3 = anchor.global_position - p
		if absf(d.y) > 1.6 or Vector2(d.x, d.z).length() > float(TOPICS[t][1]):
			continue
		if _topic_active(t):
			say_key(key)


func _poll_alarms() -> void:
	var eq: Node = _station().get_node_or_null("Equipment")
	var br: Node = eq.get_node_or_null("BreakerPanel") if eq != null else null
	if int(_dp.day_number) != _last_day_polled:
		_last_day_polled = int(_dp.day_number)
		_tripped_init = false   # a new day's armed faults are announced by the day summary
	if br != null:
		var now := {}
		for i in br.BREAKERS.size():
			if not br.on[i]:
				now[i] = true
				if _tripped_init and not _tripped.has(i):
					if String(br.cause[i]) == "overload":
						say_key(&"overload_trip")
					elif String(br.cause[i]) != "":
						var zone: String = _dp.ROOM_SHORT.get(StringName(br.BREAKERS[i]["zone"]), "the station")
						say_key(&"outage", [zone if _lang() != "zh" else _zone_zh(StringName(br.BREAKERS[i]["zone"])), br.BREAKERS[i]["id"]], Prio.SAFETY)
		_tripped = now
		_tripped_init = true
	# Round 37: timed emergencies from the ONE status model (onset, 30 s
	# escalation, cleared) -- the trip itself is the breaker line above.
	var stn: Node = _station().get_node_or_null("StationStatus")
	if stn != null:
		var e: Dictionary = stn.emergency()
		var eid: String = String(e.get("id", ""))
		if eid != _emerg_id:
			if eid != "":
				say_key(&"emerg_overload")
			elif _emerg_id != "" and br != null and br.on[2]:
				say_key(&"emerg_clear")
			_emerg_id = eid
			_emerg_30 = false
		elif eid != "" and not _emerg_30 and float(e["seconds"]) <= 30.0:
			_emerg_30 = true
			say_key(&"emerg_30")
	var env: Node = _station().get_node_or_null("EnvironmentModel")
	if env != null and "severity" in env:
		var sev: int = int(env.severity)
		if sev > _env_sev_was and sev >= 1:
			var hs: Node = eq.get_node_or_null("HatchSeal") if eq != null else null
			say_key(&"env_pressure" if hs != null and hs.leak_kpa() > 0.0 and float(env.pressure_kpa) < 100.0 else &"env_o2")
		_env_sev_was = sev


static func _zone_zh(z: StringName) -> String:
	return {&"living_quarters": "宿舍", &"life_support": "生命维持舱", &"engineering": "工程舱", &"communications": "通信舱"}.get(z, "舱段")


func _on_shift_ended(_day: int) -> void:
	if not taught.has(&"shift_end_first"):
		say_key(&"shift_end_first")
	else:
		say_key(&"shift_end")


# ============================================================ save / load
func state_dict() -> Dictionary:
	return {"taught": taught.keys().map(func(k): return String(k)), "intro_done": intro_done, "last_day_announced": last_day_announced, "last_instruction": last_instruction.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	taught = {}
	for k in Array(d.get("taught", [])):
		taught[StringName(String(k))] = true
	intro_done = bool(d.get("intro_done", intro_done))
	last_day_announced = int(d.get("last_day_announced", last_day_announced))
	last_instruction = Dictionary(d.get("last_instruction", {}))
	# Nothing queued before the load belongs to the loaded game.
	_queue.clear()
	_finish_line()
	_row_short.clear()
	_tripped_init = false


## An existing save from before Round 36 has no assistant state: treat its
## progress as already oriented (no first-day intro replay), but let
## first-time equipment lessons still play once.
func adopt_legacy_save(day: int) -> void:
	intro_done = true
	last_day_announced = day
	_queue.clear()
	_finish_line()
