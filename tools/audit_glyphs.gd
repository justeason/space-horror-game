extends SceneTree
## Round 37 Priority 9: which non-ASCII symbols used in UI strings can the
## game's font chain actually draw (default font + the CJK system fallback
## from localization.gd)? Needs a real display (system fonts):
##   godot --path . --script tools/audit_glyphs.gd
func _init() -> void:
	preload("res://scripts/ui/localization.gd").setup()
	var font: Font = ThemeDB.fallback_font
	var chars := {}
	for dir in ["res://scripts/ui/", "res://scripts/interactables/", "res://scripts/station/", "res://scripts/player/"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var txt: String = FileAccess.get_file_as_string(dir + f)
			for line in txt.split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				for i in line.length():
					var c: int = line.unicode_at(i)
					if c > 127 and not (c >= 0x4E00 and c <= 0x9FFF) and not (c >= 0x3000 and c <= 0x303F) and not (c >= 0xFF00 and c <= 0xFFEF):
						if not chars.has(c):
							chars[c] = f
	var missing: Array = []
	for c in chars:
		if not _has(font, c):
			missing.append("%s U+%04X (%s)" % [String.chr(c), c, chars[c]])
	print("non-ASCII UI symbols: %d, missing from the font chain: %d" % [chars.size(), missing.size()])
	for m in missing:
		print("  MISSING ", m)
	print("ALL GLYPHS PRESENT" if missing.is_empty() else "SOME GLYPHS MISSING")
	quit()


func _has(font: Font, c: int) -> bool:
	if font.has_char(c):
		return true
	for fb in font.fallbacks:
		if fb.has_char(c):
			return true
	return false
