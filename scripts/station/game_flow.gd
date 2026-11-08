extends RefCounted
## Round 34: how the NEXT instance of the station scene should start.
## Set by the main menu / pause menu / workstation before changing scene;
## read once by SaveGame._ready(). A scene instantiated directly (tests,
## tools) sees "" and is left exactly as authored.
##   "new_game" -> the day-1 wake-up in the bunk
##   ""         -> as authored (or a pending load)
static var start_mode: String = ""
## True while the game was entered through the main menu (Esc pause menu
## then offers "Return to Main Menu").
static var from_main_menu: bool = false
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const STATION := "res://scenes/main.tscn"
