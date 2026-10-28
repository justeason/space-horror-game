extends SubViewport
## The laptop's ENTIRE SESSION LOG interface -- both the read-only
## "just looking at it" display and the actual interactive text editor
## -- rendered as one real texture applied to the laptop's physical
## screen material (scripts/interactables/laptop.gd's
## set_screen_texture()). The same "SubViewport as a physical screen's
## live feed" pattern already used by
## scripts/surveillance/surveillance_camera.gd, extended here from a 3D
## camera feed to an interactive 2D UI tree.
##
## M7.2: this REPLACES the old projected full-screen 2D overlay
## (scripts/ui/session_log.gd, now deleted) entirely -- there is no
## camera-space HUD anymore. The log genuinely only exists as a
## texture on the laptop mesh; turning your head moves it exactly like
## any other physical object, because it IS one.
##
## Input routing (validated empirically before integrating -- see the
## M7.2 investigation notes -- rather than assumed): this SubViewport
## is not inside a SubViewportContainer (it never appears as on-screen
## 2D UI; it is only ever read as a texture), so Godot's automatic
## mouse-forwarding for embedded viewports does not apply. Keyboard
## input instead has to be explicitly forwarded by the caller via
## forward_key(), which calls push_input() on this viewport directly --
## confirmed to correctly route typing, backspace, and caret movement
## to whichever child Control currently has focus within THIS
## viewport, independent of the main scene's own input tree. There is
## deliberately no mouse-click forwarding: see scripts/player/
## sleep_state.gd, which uses dedicated keys (T/Esc/Ctrl+S) for every
## action instead, sidestepping the much larger problem of mapping a
## 3D raycast hit point to this viewport's 2D coordinates.

@onready var _entry_field: TextEdit = $Control/VBox/EntryField
@onready var _hint_label: Label = $Control/VBox/HintLabel
@onready var _edit_hint_label: Label = $Control/VBox/EditHintLabel


func _ready() -> void:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_entry_field.editable = false
	_set_hint_for_viewing()


func get_feed_texture() -> Texture2D:
	return get_texture()


func show_entry(text: String) -> void:
	_entry_field.text = text


func get_entry_text() -> String:
	return _entry_field.text


## editable=true also grabs keyboard focus (so forward_key() reaches
## it immediately); editable=false releases focus so no stray
## forwarded key can land in it while just viewing.
func set_editing(editable: bool) -> void:
	_entry_field.editable = editable
	if editable:
		_entry_field.grab_focus()
		_set_hint_for_editing()
	else:
		_entry_field.release_focus()
		_set_hint_for_viewing()


## Forwards a real keyboard InputEvent into this viewport so whichever
## Control has focus (the entry field, while editing) receives it as
## if it had been typed directly into this viewport.
func forward_key(event: InputEventKey) -> void:
	push_input(event)


## The editing hint is a SEPARATE label (not a reused/repurposed text
## swap on HintLabel) so it can be styled much more visibly (brighter
## color, larger font) than the dim ordinary-viewing hint -- the dim
## styling was confirmed to read as "no visible indication Esc exits"
## in actual play even though the hint text was technically present.
func _set_hint_for_viewing() -> void:
	_hint_label.visible = true
	_hint_label.text = "T: Edit Entry     F: Close Laptop"
	_edit_hint_label.visible = false


func _set_hint_for_editing() -> void:
	_hint_label.visible = false
	_edit_hint_label.visible = true
