extends Node
## Headless entry for the replay check: reads the service's pending scores from a file, writes verdicts to a file.
## No network and no keys here: the workflow fetches and posts with curl.
##   godot --headless --path . res://tools/verify/verify_scores.tscn -- --in=pending.json --out=verdicts.json


func _ready() -> void:
	var args := Boot.parse(OS.get_cmdline_user_args())
	var src := str(args.get("in", ""))
	var dst := str(args.get("out", ""))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(src)) if src != "" else null
	if not data is Dictionary:
		printerr("verify: could not read pending scores from '%s'" % src)
		get_tree().quit(2)
		return
	var t0 := Time.get_ticks_msec()
	var result := ScoreCheck.run(data)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		printerr("verify: could not write '%s'" % dst)
		get_tree().quit(2)
		return
	f.store_string(JSON.stringify(result))
	f.close()
	var ok: int = result.verdicts.filter(func(v): return v.ok).size()
	print("verify: %d scores, %d verified, %d rejected, %d ms" % [result.verdicts.size(), ok, result.verdicts.size() - ok, Time.get_ticks_msec() - t0])
	for v in result.verdicts:
		if not v.ok:
			print("verify: rejected %s (%s)" % [v.id, v.reason])
	get_tree().quit(0)
