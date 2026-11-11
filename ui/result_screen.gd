extends Control
## After a match: place, knockouts, pearls, and the Treasure Path moving on (FO §7).
## Saves through Platform, so the cloud copy follows when signed in.

var _bar: ProgressBar
var _from := 0.0
var _to := 0.0
var _t := 0.0
var _sent: Label


## A counted run: send the result with the replay. The server lists it as pending until the replay check.
func _send_score(r: Dictionary) -> void:
	var res: Dictionary = await St33f.client.submit_score(str(r.run.token), {"place": int(r.place), "kos": int(r.kos), "survived_s": int(r.survived_s)},
		str(r.animal), str(r.get("bots", "easy")), r.replay)
	if not is_instance_valid(_sent):
		return
	if res.ok:
		_sent.text = tr("RESULT_SENT").format({"score": int(res.data.get("score", 0)), "board": tr("BOARD_DAY") if str(r.run.board) == "day" else tr("BOARD_WEEK")})
	elif res.error != null and res.error.code == "network":
		_sent.text = tr("RESULT_SEND_OFFLINE")
	else:
		_sent.text = tr("RESULT_SEND_FAILED").format({"reason": res.error.code if res.error != null else "?"})


func _ready() -> void:
	theme = UiTheme.get_theme()
	Platform.entered("result")
	var bg := TextureRect.new()
	bg.texture = UiTheme.sky_gradient()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var r: Dictionary = Boot.last_result if not Boot.last_result.is_empty() else {"place": 3, "kos": 1, "animal": "octopus", "survived_s": 90, "players": 6}
	var outcome := apply_result(r)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if str(r.get("mode", "")) == "ball": # Strandbal: the score, then won / draw / lost
		var sc: Array = r.get("score", [0, 0])
		box.add_child(_label(tr("BALL_SCORE").format({"blue": int(sc[0]), "orange": int(sc[1])}), UiTheme.heading(150)))
		box.add_child(_label(tr({"won": "BALL_WON", "draw": "BALL_DRAW"}.get(str(r.get("outcome", "")), "BALL_LOST")), UiTheme.heading(56, UiTheme.INK, 0)))
		box.add_child(_label("%s  ·  %s" % [tr("RESULT_BALL_GOALS").format({"count": int(r.get("goals", 0))}), tr("RESULT_KOS").format({"count": r.kos})],
			UiTheme.heading(40, UiTheme.INK, 0)))
	else:
		box.add_child(_label(tr("RESULT_PLACE").format({"place": r.place}), UiTheme.heading(200)))
		var msg := tr("RESULT_WIN") if r.place == 1 else (tr("RESULT_CLOSE") if r.place <= 3 else tr("RESULT_LOST"))
		box.add_child(_label(msg, UiTheme.heading(56, UiTheme.INK, 0)))
		box.add_child(_label("%s  ·  %s" % [tr("RESULT_KOS").format({"count": r.kos}), tr("RESULT_SURVIVED").format({"seconds": r.survived_s})],
			UiTheme.heading(40, UiTheme.INK, 0)))
	if r.has("daily"):
		var d := record_daily(r)
		box.add_child(_label(tr("RESULT_DAILY_SCORE").format({"score": d.score, "best": d.best}), UiTheme.heading(44, UiTheme.GOLD, 8)))
		var why := str(r.daily.get("why", ""))
		if why != "":
			box.add_child(_label(tr("RESULT_DAILY_OFFLINE") if why == "offline" else tr("RESULT_DAILY_SIGN_IN"), UiTheme.heading(32, UiTheme.INK, 0)))
	if r.has("run"):
		_sent = _label(tr("RESULT_SENDING"), UiTheme.heading(32, UiTheme.INK, 0))
		box.add_child(_sent)
		_send_score(r)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	panel.add_child(inner)
	inner.add_child(_label(tr("RESULT_PEARLS").format({"count": outcome.earned}), UiTheme.heading(44, UiTheme.INK, 0)))
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(900, 34)
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("B8A6D9")
	fill.set_corner_radius_all(17)
	var back := StyleBoxFlat.new()
	back.bg_color = Color.WHITE
	back.border_color = UiTheme.INK
	back.set_border_width_all(5)
	back.set_corner_radius_all(17)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	inner.add_child(_bar)
	_from = outcome.progress_before
	_to = outcome.progress_after
	_bar.value = _from * 100.0
	var next_text := tr("PATH_COMPLETE")
	if not outcome.next.is_empty():
		next_text = tr("RESULT_NEXT").format({"reward": tr(str(outcome.next.name_key)), "at": int(outcome.next.at)})
	inner.add_child(_label(next_text, null))
	for rew in outcome.unlocked:
		inner.add_child(_label(tr("RESULT_UNLOCKED").format({"reward": tr(str(rew.name_key))}), UiTheme.heading(36, UiTheme.GOLD, 8)))
	if not (outcome.season as Dictionary).is_empty():
		var sn: Dictionary = outcome.season
		var sname := tr(str(sn.season.name_key))
		var line := tr("RESULT_SEASON").format({"season": sname, "pearls": int(sn.after)})
		if not (sn.next as Dictionary).is_empty():
			line = tr("RESULT_SEASON_NEXT").format({"season": sname, "reward": tr(str(sn.next.name_key)), "at": int(sn.next.at)})
		inner.add_child(_label(line, null))
		for rew in sn.unlocked:
			inner.add_child(_label(tr("RESULT_UNLOCKED").format({"reward": tr(str(rew.name_key))}), UiTheme.heading(36, UiTheme.GOLD, 8)))
	if int(outcome.mastery_up) > 0:
		inner.add_child(_label(tr("RESULT_MASTERY").format({"tier": Mastery.tier_name(int(outcome.mastery_up)),
			"animal": tr(str(Content.animal(str(r.animal)).get("name_key", "")))}), UiTheme.heading(36, UiTheme.GOLD, 8)))
	PublicProfile.publish() # badges and collection may have changed

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	box.add_child(buttons)
	var menu := Button.new()
	menu.text = tr("RESULT_MENU")
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file(Boot.SCENES["menu"]))
	buttons.add_child(menu)
	var again := Button.new()
	again.text = tr("RESULT_AGAIN")
	again.theme_type_variation = "PlayButton"
	again.pressed.connect(func() -> void:
		again.disabled = true
		Daily.start_normal(get_tree()))
	buttons.add_child(again)


func _process(delta: float) -> void:
	_t = minf(1.0, _t + delta / 1.2)
	_bar.value = lerpf(_from, _to, ease(_t, 0.4)) * 100.0


func _label(text: String, settings: LabelSettings) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if settings != null:
		l.label_settings = settings
	return l


## The daily challenge: score this match and keep today's best in the profile. Returns {score, best, improved}.
static func record_daily(r: Dictionary) -> Dictionary:
	var points := Daily.score(r)
	var rec := Daily.record(Platform.load_profile(), str(r.daily.day), points)
	Platform.save_profile(rec.profile)
	return {"score": points, "best": rec.best, "improved": rec.improved}


## Pure bookkeeping, also used by tests: pearls, stats, mastery and newly reached rewards.
static func apply_result(r: Dictionary) -> Dictionary:
	var path: Dictionary = Content.load_json("res://data/path.json")
	var table: Array = path.pearls_for_place
	var earned := int(table[clampi(int(r.place), 1, table.size() - 1)]) + int(r.kos) * int(path.pearls_per_knockout)
	earned += int(r.get("goals", 0)) * int(path.get("pearls_per_goal", 0)) # Strandbal
	var p: Dictionary = Platform.load_profile()
	var before := int(p.get("pearls_total", 0))
	var after := before + earned
	p["pearls_total"] = after
	var stats: Dictionary = p.get("stats", {})
	stats["matches"] = int(stats.get("matches", 0)) + 1
	stats["wins"] = int(stats.get("wins", 0)) + (1 if int(r.place) == 1 else 0)
	stats["knockouts"] = int(stats.get("knockouts", 0)) + int(r.kos)
	if str(r.get("mode", "")) == "ball":
		stats["ball_matches"] = int(stats.get("ball_matches", 0)) + 1
		stats["goals"] = int(stats.get("goals", 0)) + int(r.get("goals", 0))
	p["stats"] = stats
	var mastery: Dictionary = p.get("mastery", {})
	var mine: Dictionary = mastery.get(str(r.animal), {})
	var tier_before := Mastery.tier(mine)
	mine["matches"] = int(mine.get("matches", 0)) + 1
	mine["wins"] = int(mine.get("wins", 0)) + (1 if int(r.place) == 1 else 0)
	if int(r.get("goals", 0)) > 0:
		mine["goals"] = int(mine.get("goals", 0)) + int(r.goals)
	mastery[str(r.animal)] = mine
	p["mastery"] = mastery
	var tier_after := Mastery.tier(mine)
	var w := Rewards.walk(path.rewards, before, after)
	var unlocked: Array = w.unlocked
	var next: Dictionary = w.next
	var prev_at := int(w.prev_at)
	for rew in unlocked:
		Rewards.grant(p, rew) # every kind: animal, look, badge, avatar
	# the season path fills with the same pearls (FO 7: a second free path)
	var season := Season.add_pearls(p, earned, float(r.get("now", Time.get_unix_time_from_system())))
	Platform.save_profile(p)
	var span := float(int(next.get("at", after)) - prev_at)
	var progress_after := 1.0 if next.is_empty() else (after - prev_at) / maxf(1.0, span)
	var progress_before := clampf((before - prev_at) / maxf(1.0, span), 0.0, 1.0) if unlocked.is_empty() else 0.0
	return {"earned": earned, "before": before, "after": after, "unlocked": unlocked, "next": next,
		"mastery_up": tier_after if tier_after > tier_before else 0, "season": season,
		"progress_before": progress_before, "progress_after": progress_after}
