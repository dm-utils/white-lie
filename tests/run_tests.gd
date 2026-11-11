extends Node
## Headless test runner, run as a scene so autoloads (Platform, Boot) exist like in the real game.
## Exit code 1 on any failure, so CI fails.
##   godot --headless --path . res://tests/run_tests.tscn

const LOCAL_SEED_2026_11_10 := 1088332463 # FNV-1a over "verstoppertje-daily-2026-11-10", computed independently in Python
const LocalBackend := preload("res://platform/local_backend.gd")
const BootScript := preload("res://boot/boot.gd")
const ContentScript := preload("res://sim/content.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	test_every_script_compiles()
	test_data_loads()
	test_every_text_key_exists()
	test_profile_roundtrip()
	test_debug_args()
	test_profile_merge()
	await test_remote_backend()
	test_fx_and_rng()
	test_sim_rules()
	test_determinism()
	test_golden_traces()
	test_result_bookkeeping()
	test_every_asset_has_credits()
	test_setting_declarations()
	test_every_language_complete()
	test_cutouts_build()
	test_island_view()
	test_fx_draw()
	test_sfx()
	test_daily()
	test_replay()
	test_leaderboard_rows()
	test_sdk_has_what_the_game_calls()
	test_score_check()
	test_names_mastery_profiles()
	await test_my_data()
	test_touch_and_safe_area()
	test_perf_meter()
	test_rewards_season_collection()
	test_rollback()
	test_online_protocol()
	test_ball_mode()
	test_hide_sim()
	print("tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + what)


## A parse error anywhere must fail CI, not only show up in the editor.
func test_every_script_compiles() -> void:
	for path in files_under("res://", [".gd"]):
		if path == "res://tests/run_tests.gd":
			continue
		var s: Script = load(path)
		check(s != null and s.can_instantiate(), "script compiles: " + path)


func test_data_loads() -> void:
	var list: Array = ContentScript.animals()
	check(list.size() >= 3, "animals.json has at least 3 animals")
	for a in list:
		for k in ["id", "name_key", "type", "hp", "attack", "special"]:
			check(a.has(k), "animal %s has %s" % [a.get("id", "?"), k])
		check(a.get("type") in ["land", "water", "flyer"], "animal %s has a known type" % a.get("id"))


## No player-facing string inline: every tr("KEY") in code and every *_key in data must exist in strings.csv
## with a non-empty English text.
func test_every_text_key_exists() -> void:
	var table := read_strings("res://i18n/strings.csv")
	check(table.size() > 0, "strings.csv is readable")
	var used := {}
	var rx := RegEx.create_from_string("tr\\(\"([A-Z0-9_]+)\"\\)")
	for path in files_under("res://", [".gd", ".tscn"]):
		if path.begins_with("res://tests/"):
			continue
		for m in rx.search_all(FileAccess.get_file_as_string(path)):
			used[m.get_string(1)] = path
	var key_rx := RegEx.create_from_string("\"[a-z_]*key\"\\s*:\\s*\"([A-Z0-9_]+)\"")
	for path in files_under("res://data/", [".json"]):
		for m in key_rx.search_all(FileAccess.get_file_as_string(path)):
			used[m.get_string(1)] = path
	check(used.size() > 0, "found text keys in code")
	for key in used:
		check(table.has(key) and str(table[key]).strip_edges() != "", "text key %s (used in %s) exists in strings.csv" % [key, used[key]])


func test_profile_roundtrip() -> void:
	var b = LocalBackend.new()
	b.profile_path = "user://test_profile.json"
	if FileAccess.file_exists(b.profile_path):
		DirAccess.remove_absolute(b.profile_path)
	var p: Dictionary = b.load_profile()
	check(int(p["version"]) == 0, "fresh profile has version 0")
	p["pearls_total"] = 12
	b.save_profile(p)
	var q: Dictionary = b.load_profile()
	check(int(q["pearls_total"]) == 12, "pearls survive save/load")
	check(int(q["version"]) == 1, "save bumps version")
	check(str(q["updated_at"]).ends_with("Z"), "updated_at is UTC")
	DirAccess.remove_absolute(b.profile_path)


func test_debug_args() -> void:
	var a: Dictionary = BootScript.parse(PackedStringArray(["--scene=match", "--seed=42", "ignored"]))
	check(a.get("scene") == "match" and a.get("seed") == "42", "desktop debug args parse")
	var q: Dictionary = BootScript.parse_query("?scene=match&seed=7")
	check(q.get("scene") == "match" and q.get("seed") == "7", "web query parses")


func test_profile_merge() -> void:
	var a := {"pearls_total": 120, "unlocked_animals": ["crab", "octopus"], "selected_animal": "octopus",
		"stats": {"matches": 10, "wins": 2}, "achievements": {"first_win": 1}, "updated_at": "2026-11-10T10:00:00Z",
		"settings": {"music": 0.5}, "version": 4}
	var b := {"pearls_total": 90, "unlocked_animals": ["gull", "crab"], "selected_animal": "gull",
		"stats": {"matches": 12, "wins": 1, "knockouts": 7}, "achievements": {"first_win": 2, "survivor": 1},
		"updated_at": "2026-11-10T11:00:00Z", "settings": {"music": 0.9}, "version": 2}
	var m: Dictionary = ProfileMerge.merge(a, b)
	check(int(m.pearls_total) == 120, "merge: counters take the max")
	check(m.unlocked_animals == ["crab", "gull", "octopus"], "merge: unlocks are the sorted union")
	check(m.stats == {"knockouts": 7, "matches": 12, "wins": 2}, "merge: stats max per key")
	check(m.achievements == {"first_win": 2, "survivor": 1}, "merge: achievements max tier")
	check(m.selected_animal == "gull" and float(m.settings.music) == 0.9, "merge: choices from the newer profile")
	check(int(m.version) == 4, "merge: write counter max")
	var m2: Dictionary = ProfileMerge.merge(b, a)
	check(m2.unlocked_animals == m.unlocked_animals and m2.stats == m.stats and int(m2.pearls_total) == 120,
		"merge: order of arguments does not change counters and unlocks")
	check(ProfileMerge.merge(a, {}) == a, "merge: empty server keeps local")


func test_remote_backend() -> void:
	var server := {"profile": {"pearls_total": 50, "unlocked_animals": ["crab", "puffer"], "updated_at": "2026-01-01T00:00:00Z"}, "version": 3}
	var puts := []
	var handler := func(method, path, _h, body):
		if path == "/auth/start":
			return [200, {"ok": true, "challenge": "c1"}]
		if path == "/auth/verify":
			return [200, {"ok": true, "token": "cs1_" + "a".repeat(43), "userId": "u1"}]
		if path.ends_with("/profile") and method == HTTPClient.METHOD_GET:
			return [200, {"ok": true, "profile": server.profile, "version": server.version}]
		if path.ends_with("/profile") and method == HTTPClient.METHOD_PUT:
			puts.append(body)
			server.version += 1
			server.profile = body.profile
			return [200, {"ok": true, "version": server.version}]
		return [404, {"error": "not_found"}]
	var node = preload("res://addons/st33f/st33f.gd").new()
	node.configure("getij", St33fScriptedTransport.new(handler), St33fTokenStore.new(), "http://test.local", Callable(), "user://st33f/test_queue.json")
	add_child(node)
	var b = preload("res://platform/remote_backend.gd").new(node)
	b.profile_path = "user://test_remote_profile.json"
	if FileAccess.file_exists(b.profile_path):
		DirAccess.remove_absolute(b.profile_path)
	var local: Dictionary = b.load_profile()
	local["pearls_total"] = 80
	b.save_profile(local)
	check(not node.profile_sync.dirty, "signed out: saves stay local")

	await node.sign_in_start("p@example.com")
	await node.sign_in_verify("123456")
	await get_tree().process_frame
	var merged: Dictionary = b.load_profile()
	check(int(merged.pearls_total) == 80 and (merged.unlocked_animals as Array).has("puffer") and (merged.unlocked_animals as Array).has("gull"),
		"after sign-in the cloud copy is merged into the local profile")
	check(node.profile_sync.dirty and node.profile_sync.version == 3, "merged profile is queued for upload on top of server version 3")
	var r: Dictionary = await node.profile_sync.push_now()
	check(r.ok and puts.size() == 1 and int(server.profile.pearls_total) == 80, "upload sends the merged profile")
	DirAccess.remove_absolute(b.profile_path)
	node.queue_free()


func test_fx_and_rng() -> void:
	check(Fx.sin_a(0) == 0 and Fx.sin_a(1024) == 1024 and Fx.cos_a(0) == 1024 and Fx.sin_a(3072) == -1024, "sin table cardinal points")
	var worst := 0
	for a in range(0, 4096, 37):
		worst = maxi(worst, absi(Fx.angle_diff(Fx.atan2_a(Fx.sin_a(a) * 100, Fx.cos_a(a) * 100), a)))
	check(worst <= 2, "atan2 inverts sin/cos within 2 units (worst %d)" % worst)
	check(Fx.isqrt(0) == 0 and Fx.isqrt(15) == 3 and Fx.isqrt(16) == 4 and Fx.isqrt(1_000_000) == 1000, "integer sqrt")
	var r := SimRng.new(1)
	# pinned values: the C++ port must produce exactly these
	check(r.next_u32() == 270369 and r.next_u32() == 67634689, "xorshift32 reference values")


## A two-player sim with both entrants placed by hand.
func _duel(a: String, b: String) -> MatchSim:
	var s := MatchSim.new(42, [a, b])
	s.projs.clear()
	s.snacks.clear()
	s.ents[0].x = 14 * 1000 + 500
	s.ents[0].y = 12 * 1000 + 500
	s.ents[1].x = 14 * 1000 + 500
	s.ents[1].y = 12 * 1000 + 500 + 6000 # 6 tiles south
	return s


func test_sim_rules() -> void:
	var s := _duel("crab", "gull")
	var e0: MatchSim.Ent = s.ents[0]
	var x0 := e0.x
	for i in 5:
		s.step([{"m": 0}, {}])
	check(e0.x - x0 == 5 * (120 * 108 / 100), "land animal on dry sand moves 129 milli-tiles per tick (got %d)" % (e0.x - x0))

	s = _duel("crab", "gull")
	s.ents[0].x = 4 * 1000 + 500
	s.ents[0].y = 4 * 1000 + 500
	var hp := int(s.ents[0].hp)
	for i in 30:
		s.step([{}, {}])
	check(hp - int(s.ents[0].hp) == 30 * 30, "deep water costs a land animal 30 hp-units per tick")

	s = _duel("gull", "crab")
	var shots := 0
	for i in 40:
		var before := s.projs.size()
		s.step([{"a": 1024}, {}])
		if s.projs.size() > before or s.events.any(func(ev): return ev.type == "attack"):
			shots += 1
	check(shots == 3 + 1, "3 charges, then one more after a 29-tick reload within 40 ticks (got %d)" % shots)

	s = _duel("gull", "crab")
	var target_hp := int(s.ents[1].hp)
	for i in 15:
		s.step([{"a": 1024} if i == 0 else {}, {}])
	check(target_hp - int(s.ents[1].hp) == 2100 and int(s.ents[0].special) == 1, "a hit deals the attack damage and charges the special")

	s = _duel("gull", "crab")
	s.ents[1].hp = 1
	for i in 15:
		s.step([{"a": 1024} if i == 0 else {}, {}])
	check(not s.ents[1].alive and s.ents[1].place == 2 and s.ents[0].place == 1 and s.ents[0].kos == 1 and s.finished == 1,
		"knockout: places 1 and 2, KO credited, match finished")

	s = _duel("crab", "gull")
	var lvl := s.level
	var rose := false
	for i in int(s.rules.tide.phase_ticks):
		s.step([{}, {}])
		rose = rose or s.events.any(func(ev): return ev.type == "tide_rise")
	check(s.level == lvl + 1 and rose, "the tide rises one level per phase")

	s = _duel("crab", "gull")
	s.ents[0].hp = 5000
	s.snacks.append([s.ents[0].x + 300, s.ents[0].y])
	s.step([{}, {}])
	check(int(s.ents[0].hp) == 5000 + 3000 and s.snacks.is_empty(), "a snack heals 30 and disappears")

	s = _duel("octopus", "crab")
	s.ents[0].special = 4
	s.step([{"s": 1024}, {}])
	check(s.clouds.size() == 1, "octopus special drops an ink cloud")


func test_determinism() -> void:
	var a := Match.create(777, "", 6, "easy")
	var b := Match.create(777, "", 6, "easy")
	var c := Match.create(778, "", 6, "easy")
	for i in 900:
		a.step()
		b.step()
		c.step()
	check(a.sim.state_hash() == b.sim.state_hash(), "same seed -> same state after 900 ticks")
	check(a.sim.state_hash() != c.sim.state_hash(), "different seed -> different state")

	var snap := a.sim.snapshot()
	for i in 600:
		a.step()
	var d := Match.create(777, "", 6, "easy")
	d.sim.restore(snap)
	for i in 600:
		d.step()
	check(a.sim.state_hash() == d.sim.state_hash(), "snapshot + restore continues identically")


## Golden traces: fixed seeds, all bots, fixed number of ticks -> fixed state hash.
## An unintended change to rules, data or bots fails here. After an intended change, record new values:
##   godot --headless --path . res://tests/run_tests.tscn -- --update-golden
func test_golden_traces() -> void:
	var path := "res://tests/golden/traces.json"
	var update := OS.get_cmdline_user_args().has("--update-golden")
	var cases := [{"seed": 1, "ticks": 1800}, {"seed": 2026, "ticks": 3600}, {"seed": 31337, "ticks": 6000},
		{"seed": 4242, "ticks": 3000, "mode": "ball"}]
	var recorded: Variant = Content.load_json(path) if FileAccess.file_exists(path) else null
	var out: Array = []
	for i in cases.size():
		var cs: Dictionary = cases[i]
		var m := Match.create(int(cs.seed), "", 6, "easy", str(cs.get("mode", "")))
		for t in int(cs.ticks):
			m.step()
		var row := {"seed": cs.seed, "ticks": cs.ticks, "hash": m.sim.state_hash(), "alive": m.sim.alive_count(), "level": m.sim.level}
		out.append(row)
		if not update:
			var ok: bool = recorded is Array and i < recorded.size() and int(recorded[i].hash) == int(row.hash)
			check(ok, "golden trace seed %d after %d ticks (hash %d, recorded %s)" % [cs.seed, cs.ticks, row.hash,
				str(recorded[i].hash) if recorded is Array and i < recorded.size() else "none"])
	if update:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/golden"))
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  ", false, true) + "\n")
		print("golden traces updated: ", out)


func test_result_bookkeeping() -> void:
	var backend = Platform.backend
	var saved_path: String = backend.profile_path
	backend.profile_path = "user://test_result_profile.json"
	if FileAccess.file_exists(backend.profile_path):
		DirAccess.remove_absolute(backend.profile_path)
	var RS := preload("res://ui/result_screen.gd")
	var o: Dictionary = RS.apply_result({"place": 1, "kos": 3, "animal": "gull"})
	check(int(o.earned) == 60 + 30 and int(o.after) == 90, "win with 3 KOs earns 60 + 3 x 10 pearls")
	o = RS.apply_result({"place": 2, "kos": 1, "animal": "gull"})
	check(int(o.after) == 145 and o.unlocked.size() == 1 and str(o.unlocked[0].id) == "shell", "crossing 100 unlocks the first reward")
	for i in 3:
		o = RS.apply_result({"place": 1, "kos": 0, "animal": "crab"})
	var p: Dictionary = Platform.load_profile()
	check((p.unlocked_animals as Array).has("puffer") and int(p.pearls_total) == 325, "crossing 250 adds the pufferfish to the unlocked animals")
	check(int(p.stats.matches) == 5 and int(p.stats.wins) == 4 and int(p.mastery.gull.matches) == 2, "stats and mastery counted")
	# Strandbal: a draw (counts as 2nd place) with 2 goals and 1 KO
	o = RS.apply_result({"mode": "ball", "place": 2, "outcome": "draw", "kos": 1, "goals": 2, "animal": "crab"})
	p = Platform.load_profile()
	check(int(o.earned) == 45 + 10 + 20, "Strandbal: a draw with 2 goals and 1 KO earns 45 + 10 + 2 x 10 pearls (got %d)" % int(o.earned))
	check(int(p.stats.ball_matches) == 1 and int(p.stats.goals) == 2 and int(p.mastery.crab.goals) == 2 and int(p.stats.wins) == 4,
		"Strandbal: goals counted in stats and crab mastery; a draw is no win")
	DirAccess.remove_absolute(backend.profile_path)
	backend.profile_path = saved_path


## Every slice animal builds from its rig; part names the code binds to exist; looks build too.
func test_cutouts_build() -> void:
	for id in Match.SLICE_ANIMALS:
		var c := Cutout.new()
		c.build(id)
		check(c.joints.has("body") and c.joints.size() >= 7, "%s builds from its rig (%d parts)" % [id, c.joints.size()])
		for j in c.joints.values():
			var sprite: Sprite2D = j.get_child(0)
			check(sprite.texture != null, "%s/%s has a texture" % [id, j.name])
		c.trigger("attack")
		c._process(0.1)
		c.free()
	for look in [["crab", "crab_sunset"], ["octopus", "octopus_midnight"]]:
		var c := Cutout.new()
		c.build(look[0], look[1])
		check((c.joints.body.get_child(0) as Sprite2D).texture != null, "look %s builds" % look[1])
		c.free()


## The island shader gets the sim's heights exactly (one texel per tile), and the shown tide eases to the sim's.
func test_island_view() -> void:
	var img := IslandView.height_image(3, 2, [0, 1, 2, 3, 9, 10])
	var ok := true
	for i in 6:
		var v := roundi(img.get_pixel(i % 3, i / 3).r * 255.0 / IslandView.HEIGHT_SCALE)
		ok = ok and v == [0, 1, 2, 3, 9, 10][i]
	check(ok and img.get_format() == Image.FORMAT_R8, "island heights survive the round trip through the texture")
	var m := Match.create(123, "crab", 6, "easy")
	var view := IslandView.new().setup(m.sim, 80.0)
	check(view.material is ShaderMaterial and (view.material as ShaderMaterial).get_shader_parameter("atlas") != null, "island has its shader and atlas")
	m.sim.level += 1
	view._process(IslandView.RISE_S / 2.0)
	check(view.shown_level > m.sim.level - 1 and view.shown_level < m.sim.level, "water rises gradually on screen")
	view._process(IslandView.RISE_S)
	check(is_equal_approx(view.shown_level, float(m.sim.level)), "and then matches the sim")
	view.free()
	var world: Dictionary = Content.load_json("res://data/palette.json").world
	# styleguide: shallow and deep water must also differ in brightness (colour-blind players)
	check(Color(str(world.shallow)).get_luminance() - Color(str(world.deep)).get_luminance() > 0.25, "shallow is clearly lighter than deep")


## Effects are view-only and finish by themselves.
func test_fx_draw() -> void:
	var fx := FxDraw.new()
	fx.splash(Vector2(100, 100), 1.5)
	fx.ripple(Vector2(50, 50))
	check(fx.drops.size() > 5 and fx.rings.size() == 3, "a splash makes droplets and rings")
	for i in 60:
		fx.update(1.0 / 30.0)
	check(fx.is_idle(), "splashes are gone after two seconds")


## Every sound the game asks for is defined in data/sfx.json; in CI (after sfx.py --ffmpeg) every sound exists.
func test_sfx() -> void:
	var spec: Dictionary = Content.load_json("res://data/sfx.json")
	var sounds: Dictionary = spec.sounds
	var wanted := ["tap", "hit", "ko", "snack", "boom", "tide", "win", "splash", "dash", "ink", "dive", "kick", "whistle", "cheer"]
	wanted.append_array(preload("res://view/match_view.gd").ATTACK_SOUNDS.values())
	var missing := wanted.filter(func(n): return not sounds.has(n))
	check(missing.is_empty(), "every sound the game plays is in sfx.json (missing: %s)" % ", ".join(missing))
	check(float(spec.peak_dbfs) <= -3.0, "effects are normalised to a peak <= -3 dBFS")
	check(AudioServer.get_bus_index("Sfx") != -1 and AudioServer.get_bus_effect_count(0) > 0, "Sfx bus and a limiter on the master")
	check(Sfx.attenuation_db(0.0, 1920.0) == 0.0 and Sfx.attenuation_db(1920.0, 1920.0) < -10.0 and Sfx.attenuation_db(4000.0, 1920.0) <= -60.0, "sounds fade with distance")
	if OS.has_environment("CI"):
		var absent := sounds.keys().filter(func(n): return not Sfx.has_sound(n))
		check(absent.is_empty(), "every sound was built and imported (missing: %s)" % ", ".join(absent))


## The daily challenge: UTC day and countdown, a stable local seed, same animal for everyone, score and best.
func test_daily() -> void:
	var t := 1794315600.0 # 2026-11-10 13:00:00 UTC
	check(Daily.day_of(t) == "2026-11-10" and Daily.seconds_left(t) == 11 * 3600 and Daily.countdown(t) == "11:00:00", "UTC day and countdown")
	check(Daily.day_of(t + 11 * 3600) == "2026-11-11", "a new day at midnight UTC")
	var s := Daily.local_seed("2026-11-10")
	check(s == LOCAL_SEED_2026_11_10, "local seed is the same on every platform (got %d)" % s)
	check(s != Daily.local_seed("2026-11-11") and s >= 1 and s <= 2000000000, "local seed changes daily, in range")
	check(Match.SLICE_ANIMALS.has(Daily.animal_for(s)) and Daily.animal_for(s) == Daily.animal_for(s), "the animal follows from the seed")
	var win := Daily.score({"place": 1, "kos": 2, "survived_s": 100})
	var last := Daily.score({"place": 6, "kos": 0, "survived_s": 30})
	check(win == 1000 + 600 + 200 and last == 100 + 60, "score = place + knockouts + seconds (got %d, %d)" % [win, last])
	var r := Daily.record({"pearls_total": 5}, "2026-11-10", 800)
	check(r.best == 800 and r.improved and r.profile.pearls_total == 5, "first daily score")
	r = Daily.record(r.profile, "2026-11-10", 300)
	check(r.best == 800 and not r.improved and r.profile.daily.plays == 2, "a worse try keeps the best")
	r = Daily.record(r.profile, "2026-11-11", 300)
	check(r.best == 300 and r.profile.daily.plays == 1, "a new day starts over")


## A replay plays the whole match again: same commands, same result and state hash. Anything changed is caught.
func test_replay() -> void:
	# a "player" who only reads the sim, like real input (BotBrain draws from sim.rng, so it can't stand in)
	var m := Match.create(4242, "crab", 6, "normal")
	while not (m.finished() or m.human_out()):
		m.step(_player_cmd(m.sim, m.sim.ents[m.human]))
	var claimed := m.human_result()
	var rep := Replay.encode(m.replay)
	check(rep.ticks == m.replay.size() and rep.rle.size() <= rep.ticks, "replay is run-length encoded (%d ticks, %d runs, %d bytes)" % [rep.ticks, rep.rle.size(), JSON.stringify(rep).length()])
	check(JSON.stringify(rep).length() * 5400 / maxi(1, rep.ticks) < 256 * 1024, "a 3-minute replay fits the 256 KB limit of the service")
	check(Replay.decode(rep).size() == rep.ticks, "decode gives one command per tick")
	var t0 := Time.get_ticks_msec()
	var ok := Replay.check(4242, "crab", "normal", rep, claimed)
	var ms := Time.get_ticks_msec() - t0
	check(ok.ok and ok.hash == m.sim.state_hash(), "replay gives the same result and state hash (%s, %d ms for %d ticks)" % [ok.reason, ms, rep.ticks])
	var wrong := claimed.duplicate()
	wrong.kos = int(claimed.kos) + 1
	check(Replay.check(4242, "crab", "normal", rep, wrong).reason == "result_mismatch", "a claimed extra knockout is caught")
	check(not Replay.check(4243, "crab", "normal", rep, claimed).ok, "another seed does not give the same match")
	check(not Replay.check(4242, "gull", "normal", rep, claimed).ok, "another animal does not give the same match")
	var short := Replay.encode(m.replay.slice(0, m.replay.size() - 40))
	check(Replay.check(4242, "crab", "normal", short, claimed).reason == "match_not_over", "a cut replay is caught")
	var long := Replay.encode(m.replay + [[-1, -1, -1, -1]])
	check(Replay.check(4242, "crab", "normal", long, claimed).reason == "replay_after_end", "commands after the end are caught")
	var tampered := rep.duplicate(true)
	tampered.ticks += 1
	check(Replay.check(4242, "crab", "normal", tampered, claimed).reason == "bad_replay", "ticks that do not add up are caught")
	check(Replay.check(4242, "shark", "normal", rep, claimed).reason == "bad_setup", "unknown animal is refused")


## Test player: heads for the middle of the island, attacks the nearest animal, uses the special now and then.
func _player_cmd(sim: MatchSim, me: MatchSim.Ent) -> Dictionary:
	var target: MatchSim.Ent = null
	var best := 1 << 40
	for e in sim.ents:
		if e.alive and e.id != me.id:
			var d: int = (e.x - me.x) * (e.x - me.x) + (e.y - me.y) * (e.y - me.y)
			if d < best:
				best = d
				target = e
	var cx := sim.width * MatchSim.TILE / 2
	var cy := sim.height * MatchSim.TILE / 2
	var cmd := {"m": Fx.atan2_a(cy - me.y, cx - me.x) if absi(cx - me.x) + absi(cy - me.y) > 3000 else (sim.tick * 7) % Fx.ANGLES, "a": -1, "s": -1}
	if target != null:
		var aim := Fx.atan2_a(target.y - me.y, target.x - me.x)
		cmd.a = aim
		if sim.tick % 240 == 0:
			cmd.s = aim
			cmd["sd"] = Fx.dist(target.x - me.x, target.y - me.y)
	return cmd


## The leaderboard: one row per entry, own place added below the top when it is not in it, pending marked.
func test_leaderboard_rows() -> void:
	var screen = preload("res://ui/leaderboard_screen.gd").new()
	screen._list = VBoxContainer.new()
	screen._status = Label.new()
	var data := {"board": "day:2026-11-10", "players": 30, "me": {"rank": 31, "player": "ffff0000", "score": 90, "pending": true},
		"entries": [{"rank": 1, "player": "aaaa1111", "score": 2200, "pending": false}, {"rank": 2, "player": "bbbb2222", "score": 1800, "pending": true}]}
	screen.fill(data)
	check(screen._list.get_child_count() == 4, "two entries, a gap and my own place (%d rows)" % screen._list.get_child_count())
	var pending_rows := 0
	for row in screen._list.get_children():
		for l in row.get_children():
			if l is Label and l.text == tr("BOARD_PENDING"):
				pending_rows += 1
	check(pending_rows == 2, "pending scores are marked")
	data.me = {"rank": 2, "player": "bbbb2222", "score": 1800, "pending": true}
	screen.fill(data)
	for c in screen._list.get_children():
		screen._list.remove_child(c)
		c.free()
	screen.fill(data)
	check(screen._list.get_child_count() == 2, "inside the top: no extra row")
	screen.fill({"entries": [], "players": 0, "me": null})
	check(screen._status.text.begins_with(tr("BOARD_EMPTY")), "empty board says so")
	for c in screen._list.get_children():
		c.free()
	screen._list.free()
	screen._status.free()
	screen.free()


## Every St33f client call the game makes exists in the copied SDK (a stale copy only fails at runtime otherwise).
func test_sdk_has_what_the_game_calls() -> void:
	var rx := RegEx.create_from_string("St33f[.]client[.]([a-z_]+)[(]")
	var missing := []
	for path in files_under("res://", [".gd"]):
		if str(path).begins_with("res://addons/") or str(path).begins_with("res://tests/"):
			continue
		for m in rx.search_all(FileAccess.get_file_as_string(path)):
			if not St33f.client.has_method(m.get_string(1)):
				missing.append("%s in %s" % [m.get_string(1), path])
	check(missing.is_empty(), "SDK has every client call the game makes (missing: %s)" % ", ".join(missing))


## The replay check: board rules first, then the whole match again. Also writes a sample for the headless scene.
func test_score_check() -> void:
	var seed_value := 777001
	var animal := Daily.animal_for(seed_value)
	var m := Match.create(seed_value, animal, 6, Daily.BOTS)
	while not (m.finished() or m.human_out()):
		m.step(_player_cmd(m.sim, m.sim.ents[m.human]))
	var r := m.human_result()
	var claimed := {"place": r.place, "kos": r.kos, "survived_s": r.survived_s}
	var rep := Replay.encode(m.replay)
	var other: String = Match.SLICE_ANIMALS[(Match.SLICE_ANIMALS.find(animal) + 1) % Match.SLICE_ANIMALS.size()]
	var lie := claimed.duplicate()
	lie.place = 1 if int(claimed.place) != 1 else 2
	var pending := {"scores": [
		{"id": "sc_good", "board": "day:2026-11-10", "seed": seed_value, "animal": animal, "bots": "normal", "claimed": claimed, "replay": rep},
		{"id": "sc_animal", "board": "day:2026-11-10", "seed": seed_value, "animal": other, "bots": "normal", "claimed": claimed, "replay": rep},
		{"id": "sc_bots", "board": "week:2026-W46", "seed": seed_value, "animal": animal, "bots": "normal", "claimed": claimed, "replay": rep},
		{"id": "sc_lie", "board": "day:2026-11-10", "seed": seed_value, "animal": animal, "bots": "normal", "claimed": lie, "replay": rep},
	]}
	var out := ScoreCheck.run(pending)
	var by := {}
	for v in out.verdicts:
		by[v.id] = v
	check(by.sc_good.ok, "an honest daily score is verified (%s)" % by.sc_good.reason)
	check(not by.sc_animal.ok and by.sc_animal.reason == "not_the_animal_of_the_day", "another animal on the day board is rejected")
	check(not by.sc_bots.ok and by.sc_bots.reason == "wrong_bots_for_week", "week board with harder-to-check bots is rejected")
	check(not by.sc_lie.ok and by.sc_lie.reason == "result_mismatch", "a better place than played is rejected")
	# replays recorded on Windows (tests/golden/replays_windows.json) must give the same verdicts on every platform
	var golden: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/replays_windows.json"))
	var gv := ScoreCheck.run(golden)
	check(gv.verdicts.size() == 4 and gv.verdicts[0].ok and gv.verdicts.slice(1).all(func(v): return not v.ok),
		"replays recorded on Windows verify the same here (%s)" % JSON.stringify(gv.verdicts))
	var f := FileAccess.open("user://verify_sample.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(pending))
	f.close()


## Names from word lists (in the player's language), mastery tiers, merge keeps the name, the public profile.
func test_names_mastery_profiles() -> void:
	var name := {"a": 0, "n": 0, "num": 42}
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var en := PlayerName.text(name)
	TranslationServer.set_locale("nl")
	var nl := PlayerName.text(name)
	TranslationServer.set_locale(locale)
	check(en == "Swift Otter 42" and nl == "Snelle Otter 42", "names read in the player's language (%s / %s)" % [en, nl])
	check(PlayerName.valid(name) and not PlayerName.valid({"a": 99, "n": 0, "num": 1}) and not PlayerName.valid("Captain"), "name validity")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ok := true
	for i in 200:
		ok = ok and PlayerName.valid(PlayerName.random(rng))
	check(ok, "random names are always valid")
	check(PlayerName.text({"a": 500, "n": 1, "num": 3}).begins_with("?"), "a name from a newer word list still reads")

	check(Mastery.tier({}) == 0 and Mastery.tier({"matches": 5}) == 1 and Mastery.tier({"matches": 30, "wins": 4}) == 1, "bronze needs matches; silver also wins")
	check(Mastery.tier({"matches": 25, "wins": 5}) == 2 and Mastery.tier({"matches": 80, "wins": 20}) == 3, "silver and gold")
	var prof := {"mastery": {"gull": {"matches": 26, "wins": 6}, "crab": {"matches": 5, "wins": 0}, "octopus": {"matches": 1}}, "unlocked_animals": ["crab", "gull"], "selected_animal": "gull"}
	check(Mastery.badges(prof) == ["crab:1", "gull:2"], "badges sorted, only reached tiers (%s)" % str(Mastery.badges(prof)))
	var pub := PublicProfile.from(prof)
	check(PlayerName.valid(pub.name) and pub.animal == "gull" and pub.badges.size() == 2 and pub.collection.size() == 2, "public profile from the save")
	check(not pub.has("pearls_total") and not pub.has("settings") and not pub.has("stats"), "only public fields leave the device")

	var merged := ProfileMerge.merge({"updated_at": "2026-11-11", "unlocked_animals": ["crab"]}, {"updated_at": "2026-11-10", "name": name, "unlocked_animals": ["crab"]})
	check(merged.get("name") == name, "a fresh device does not drop the player's name")

	var screen = preload("res://ui/leaderboard_screen.gd").new()
	var body := VBoxContainer.new()
	screen.fill_profile(body, {"player": "0123456789abcdef", "name": name, "animal": "gull", "badges": ["gull:2"], "collection": ["crab", "gull"]})
	check(body.get_child_count() == 5, "profile dialog: name, favourite, heading, one badge, collection (%d)" % body.get_child_count())
	for c in body.get_children():
		body.remove_child(c)
		c.free()
	screen.fill_profile(body, {})
	check(body.get_child_count() == 1, "no public profile says so")
	for c in body.get_children():
		body.remove_child(c)
		c.free()
	screen.fill_friends(body, {}, "")
	check(body.get_child_count() == 2 and (body.get_child(1) as Label).text == tr("FRIENDS_SIGN_IN"), "friends: signed out says how to sign in")
	for c in body.get_children():
		body.remove_child(c)
		c.free()
	screen.fill_friends(body, {"code": "ABCD2345", "friends": [{"player": "0123456789abcdef", "name": name}, {"player": "fedcba9876543210", "name": null}]}, "")
	var list: VBoxContainer = body.get_child(body.get_child_count() - 1)
	var code_row: HBoxContainer = body.get_child(1)
	check((code_row.get_child(1) as Label).text == "ABCD-2345", "own code shown in two halves (easy to read out)")
	check(list.get_child_count() == 2, "two friends listed")
	check(((list.get_child(1) as HBoxContainer).get_child(0) as Label).text.begins_with(tr("BOARD_PLAYER").format({"id": "fedcba"})), "a friend without a name shows the short id")
	for c in body.get_children():
		c.free()
	body.free()
	screen.free()


## "Download my data": signed out it holds what is on this device; the file is written where the player finds it.
func test_my_data() -> void:
	var data: Dictionary = await MyData.gather()
	check(data.device is Dictionary and data.platform == null and data.game == "verstoppertje", "signed out: the device profile, no platform part")
	var text := JSON.stringify(data, "  ")
	check(not text.contains("cs1_"), "no session token in the export")
	var path := MyData.save(text)
	check(path != "" and FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == text, "export file written (%s)" % path)
	if path != "":
		DirAccess.remove_absolute(path)
	for i in range(1, 8):
		check(tr("PRIVACY_P%d" % i) != "PRIVACY_P%d" % i, "privacy paragraph %d has a text" % i)


## Phone: two thumbs at once (move + attack), dead zone, the special button keeps its touches; safe-area insets.
func test_touch_and_safe_area() -> void:
	var t := TouchControls.new()
	t.size = Vector2(1920, 1080)
	var ev := func(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
		var e := InputEventScreenTouch.new()
		e.index = index
		e.position = pos
		e.pressed = pressed
		return e
	var drag := func(index: int, pos: Vector2) -> InputEventScreenDrag:
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = pos
		return e
	t.handle(ev.call(0, Vector2(300, 700), true))
	t.handle(drag.call(0, Vector2(310, 700)))
	check(t.move == Vector2.ZERO, "a resting thumb does not walk (dead zone)")
	t.handle(drag.call(0, Vector2(600, 700)))
	check(is_equal_approx(t.move.x, 1.0) and is_zero_approx(t.move.y), "joystick: full speed to the right, capped")
	t.handle(ev.call(1, t.attack_center() + Vector2(20, 10), true))
	check(t.attacking and t.move.x > 0.9, "second thumb attacks while the first keeps moving")
	t.handle(ev.call(0, Vector2(600, 700), false))
	check(t.move == Vector2.ZERO and t.attacking, "lifting the move thumb stops walking, attack holds")
	t.handle(ev.call(1, Vector2.ZERO, false))
	check(not t.attacking, "lifting the attack thumb stops attacking")
	var special := Button.new()
	special.size = Vector2(220, 110)
	special.position = Vector2(100, 100)
	t.add_child(special)
	t.blocked.append(special)
	t.handle(ev.call(2, Vector2(150, 150), true))
	t.handle(drag.call(2, Vector2(450, 150)))
	check(t.move == Vector2.ZERO, "a touch on the special button is left to the button")
	t.handle(ev.call(3, Vector2(1500, 300), true))
	t.handle(drag.call(3, Vector2(1800, 300)))
	check(t.move == Vector2.ZERO, "the right half does not start a joystick")
	t.free()

	var keys := preload("res://view/match_view.gd")
	check(keys.choose_controls({}, {}, true) == "touch" and keys.choose_controls({}, {}, false) == "keys", "touchscreen picks touch by default")
	check(keys.choose_controls({"settings": {"controls": "mouse"}}, {}, true) == "mouse", "the player's choice wins")
	check(keys.choose_controls({}, {"controls": "touch"}, false) == "touch", "debug argument controls=touch")

	var i := SafeArea.from_rects(Rect2(88, 0, 2400 - 88 - 88, 1080 - 63), Vector2(2400, 1080), Vector2(1920, 1080))
	check(is_equal_approx(i.left, 70.4) and is_equal_approx(i.right, 70.4) and is_zero_approx(i.top) and is_equal_approx(i.bottom, 63.0), "notch + home bar as insets in viewport units (%s)" % str(i))
	check(SafeArea.from_rects(Rect2(0, 0, 1920, 1080), Vector2(1920, 1080), Vector2(1920, 1080)).left == 0.0, "desktop: no insets")
	check(SafeArea.parse("40,20,40,30").bottom == 30.0, "debug safe=l,t,r,b")


## Frame times: average and p95 over a rolling window (the slow frames are what you feel).
func test_perf_meter() -> void:
	var p := PerfMeter.new()
	for i in 300:
		p.add(1.0 / 60.0 if i % 10 != 0 else 0.05) # every 10th frame is a 50 ms hitch (10 % > the 5 % above p95)
	var s := p.stats()
	check(absf(s.p95_ms - 50.0) < 0.01, "p95 sees the hitches (%.1f ms)" % s.p95_ms)
	check(s.avg_ms > 19.0 and s.avg_ms < 20.5 and s.fps > 45.0, "average and fps (%.1f ms, %.0f fps)" % [s.avg_ms, s.fps])
	p.free()


## Every reward kind is kept; the season path fills alongside; looks are chosen per animal; the collection shows all.
func test_rewards_season_collection() -> void:
	var p := {"unlocked_animals": ["crab"], "selected_animal": "crab"}
	for rew in [{"kind": "look", "id": "crab_sunset"}, {"kind": "badge", "id": "beachcomber"}, {"kind": "avatar", "id": "shell"}, {"kind": "animal", "id": "gull"}, {"kind": "look", "id": "crab_sunset"}]:
		Rewards.grant(p, rew)
	check(p.looks.owned == ["crab_sunset"] and p.badges == ["beachcomber"] and p.avatars == ["shell"] and p.unlocked_animals.has("gull"), "every reward kind is kept, no doubles")
	check(Rewards.equipped_look(p, "crab") == "", "standard colours until a look is chosen")
	Rewards.equip(p, "crab", "crab_sunset")
	Rewards.equip(p, "gull", "gull_storm") # not owned
	check(Rewards.equipped_look(p, "crab") == "crab_sunset" and Rewards.equipped_look(p, "gull") == "", "only owned looks are worn")

	var nov12 := 1794488400.0 # 2026-11-12 13:00 UTC
	var s := Season.active(nov12)
	check(str(s.get("id", "")) == "storm-2026" and Season.days_left(s, nov12) == 81, "Storm Season runs, days left (%d)" % Season.days_left(s, nov12))
	check(Season.active(1794315600.0 - 86400.0).is_empty(), "no season before it starts")
	var q := {}
	var r := Season.add_pearls(q, 210, nov12)
	check(int(r.after) == 210 and q.seasons["storm-2026"].pearls == 210 and r.unlocked.size() == 2 and (q.looks.owned as Array).has("gull_storm"), "season pearls unlock the season rewards")
	check(int(r.next.at) == 350, "next season reward")

	var merged := ProfileMerge.merge({"updated_at": "b", "unlocked_animals": ["crab"], "seasons": {"storm-2026": {"pearls": 50}}, "badges": ["a"]},
		{"updated_at": "a", "unlocked_animals": ["crab"], "seasons": {"storm-2026": {"pearls": 210}}, "badges": ["b"]})
	check(merged.seasons["storm-2026"].pearls == 210 and merged.badges == ["a", "b"], "merge: season pearls max, badges union")

	var screen = preload("res://ui/collection_screen.gd").new()
	var all: Array = screen.entries()
	check(all.size() == 8 and all.filter(func(e): return not e.built).size() == 5, "collection: 3 animals to play, 5 coming soon")
	var crab_looks: Array = screen.looks_for("crab")
	check(crab_looks.size() == 2 and crab_looks.any(func(l): return l.id == "crab_storm" and str(l.source).contains("350")), "crab looks with where to get them")
	var box := VBoxContainer.new()
	var shade := Control.new()
	screen.fill_detail(box, "crab", shade)
	check(box.get_child_count() >= 8, "detail: name, kind, attack, special, mastery, looks, buttons (%d)" % box.get_child_count())
	for c in box.get_children():
		c.free()
	screen.fill_detail(box, "otter", shade)
	check((box.get_child(1) as Label).text == tr("COLLECTION_SOON_LONG"), "an animal that isn't built yet says so")
	for c in box.get_children():
		c.free()
	box.free()
	shade.free()
	screen.free()


## Online: six screens over a laggy, jittery network end in exactly the same state as one run with all input known.
func test_rollback() -> void:
	for setup in [{"players": 2, "lag": [1, 3]}, {"players": 6, "lag": [2, 9]}, {"players": 4, "lag": [1, 6], "leaver": 2, "leave_at_step": 150},
			{"players": 4, "lag": [1, 6], "mode": "ball"}]:
		var mode := str(setup.get("mode", ""))
		var n: int = setup.players
		var seed_value := 90210
		var animals: Array = []
		for i in n:
			animals.append(Match.SLICE_ANIMALS[i % 3])
		var clients: Array = []
		for i in n:
			clients.append(Rollback.new(Match.create_online(seed_value, animals, 6, "normal", mode), i))
		var net := RandomNumberGenerator.new()
		net.seed = 7
		var in_flight: Array = [] # [arrive_at_step, to, from, tick, cmd]
		var ticks := 360
		var step := 0
		var leave_tick := -1
		var t0 := Time.get_ticks_msec()
		var players: Array = range(n).filter(func(i): return not setup.has("leaver") or i != setup.leaver)
		while players.any(func(i): return clients[i].tick < ticks) and step < ticks * 4:
			step += 1
			for msg in in_flight.filter(func(x): return x[0] <= step):
				if msg[2] == -1:
					clients[msg[1]].leave(msg[4], msg[3])
				else:
					clients[msg[1]].remote_input(msg[2], msg[3], msg[4])
			in_flight = in_flight.filter(func(x): return x[0] > step)
			# a player who quits: the relay tells the rest from which tick a bot plays that seat
			if setup.has("leaver") and step == int(setup.leave_at_step):
				var gone: Rollback = clients[setup.leaver]
				leave_tick = gone.tick + gone.delay # = the tick after the last input it sent
				for j in n:
					if j != setup.leaver:
						in_flight.append([step + net.randi_range(setup.lag[0], setup.lag[1]), j, -1, leave_tick, setup.leaver])
			for i in n:
				var c: Rollback = clients[i]
				if setup.has("leaver") and i == setup.leaver and step >= int(setup.leave_at_step):
					continue
				if c.tick >= ticks or not c.can_advance():
					continue
				# each player reacts to what they see on their own screen (predictions included)
				c.local_input(Match.cmd_to(_player_cmd(c.m.sim, c.m.sim.ents[i])))
				for out in c.outbox:
					for j in n:
						if j != i:
							in_flight.append([step + net.randi_range(setup.lag[0], setup.lag[1]), j, i, out[0], out[1]])
				c.outbox.clear()
				c.advance()
		for msg in in_flight: # the network delivers the rest
			if msg[2] == -1:
				clients[msg[1]].leave(msg[4], msg[3])
			else:
				clients[msg[1]].remote_input(msg[2], msg[3], msg[4])
		var hashes: Array = players.map(func(i): return clients[i].settle())
		var inputs: Dictionary = clients[players[0]].confirmed_inputs(ticks)
		var ref := Match.create_online(seed_value, animals, 6, "normal", mode)
		for t in ticks:
			if t == leave_tick:
				ref.to_bot(setup.leaver)
			var cmds := {}
			for s in ref.humans:
				cmds[s] = inputs[s][t]
			ref.step_many(cmds)
		var same := hashes.all(func(h): return h == hashes[0])
		var total_rb := 0
		var total_resim := 0
		for i in players:
			var c: Rollback = clients[i]
			total_rb += c.rollbacks
			total_resim += c.resimulated
		var what := ("Strandbal: " if mode != "" else "") + ("one quits at tick %d; " % leave_tick if leave_tick >= 0 else "") + "%d players, lag %s ticks: every screen ends identical to the reference (%d rollbacks, %d ticks replayed, %d ms for %d screens x %d ticks)" % [
			n, str(setup.lag), total_rb, total_resim, Time.get_ticks_msec() - t0, n, ticks]
		print("rollback: " + what)
		check(same and hashes[0] == ref.sim.state_hash(), what)
		check(total_rb > 0, "%d players: predictions really were corrected (the test exercises rollback)" % n)


## The online protocol: own input in batches of up to 8 consecutive ticks; relay messages land in the rollback.
func test_online_protocol() -> void:
	var outbox: Array = []
	for t in range(2, 13):
		outbox.append([t, [t, -1, -1, -1]])
	var msgs := OnlineClient.batch(outbox)
	check(msgs.size() == 2 and msgs[0].t == 2 and msgs[0].cs.size() == 8 and msgs[1].t == 10 and msgs[1].cs.size() == 3, "batches of up to 8 ticks")
	var m := Match.create_online(5, ["crab", "gull"], 6, "normal")
	var rb := Rollback.new(m, 0)
	check(OnlineClient.apply(rb, {"type": "start", "players": 2, "left": {}}) == "start", "start")
	# JSON gives floats: they must become ints, or a correct prediction would look wrong
	check(OnlineClient.apply(rb, {"type": "in", "s": 1.0, "t": 2.0, "cs": [[1024.0, -1.0, -1.0, -1.0], [1024.0, -1.0, -1.0, -1.0]]}) == "in", "input")
	check(rb.waiting_since() == 0 or rb.confirmed_inputs(4)[1][3] == [1024, -1, -1, -1], "input stored as ints for the right seat and ticks")
	check(OnlineClient.apply(rb, {"type": "leave", "s": 1, "t": 4}) == "leave", "leave")
	for i in 20:
		rb.local_input([-1, -1, -1, -1])
		rb.advance()
	check(not m.humans.has(1) and m.sim.ents[1].is_bot == 1 and rb.tick == 20, "after the leave tick a bot plays the seat and nobody waits for it")
	check(OnlineClient.apply(rb, {"type": "desync", "t": 60}) == "desync" and OnlineClient.apply(rb, {"type": "?"}) == "", "desync and unknown")


## A new key goes into every language in the same change, with the same placeholders ({count} etc.).
func test_every_language_complete() -> void:
	var f := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	var header := f.get_csv_line()
	var langs := []
	for i in range(1, header.size()):
		if not header[i].begins_with("_"):
			langs.append(i)
	check(langs.size() >= 2, "strings.csv has at least two languages (%s)" % ", ".join(header))
	var rx := RegEx.create_from_string("\\{[a-z_]+\\}")
	var problems := []
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0] == "":
			continue
		var en_ph := _placeholders(rx, row[1])
		for i in langs:
			var text: String = row[i] if i < row.size() else ""
			if text.strip_edges() == "":
				problems.append("%s has no %s text" % [row[0], header[i]])
			elif _placeholders(rx, text) != en_ph:
				problems.append("%s: placeholders differ in %s" % [row[0], header[i]])
	check(problems.is_empty(), "every key translated with matching placeholders: " + "; ".join(problems))
	TranslationServer.set_locale("nl")
	check(tr("MENU_PLAY") == "SPELEN", "the Dutch translation is loaded")
	TranslationServer.set_locale("en")
	check(tr("MENU_PLAY") == "PLAY", "English is back")


func _placeholders(rx: RegEx, text: String) -> Array:
	var out := []
	for m in rx.search_all(text):
		out.append(m.get_string())
	out.sort()
	return out


## The same checks the server applies when CI pushes the declarations, so a bad one fails here first.
func test_setting_declarations() -> void:
	var d: Dictionary = Content.load_json("res://data/settings_defs.json")
	var key_rx := RegEx.create_from_string("^[a-z][a-z0-9_]{0,47}$")
	for def in d.defs:
		var ok_type := false
		match str(def.type):
			"bool": ok_type = typeof(def.default) == TYPE_BOOL
			"int": ok_type = typeof(def.default) == TYPE_FLOAT and float(def.default) == floor(float(def.default))
			"float": ok_type = typeof(def.default) == TYPE_FLOAT
			"string": ok_type = typeof(def.default) == TYPE_STRING
		check(key_rx.search(str(def.key)) != null and ok_type and str(def.get("description", "")) != "",
			"setting %s: valid key, default matches type, has a description" % def.key)
	check(Platform.get_config("show_daily", false) == true and Platform.get_config("event_banner", "x") == "",
		"get_config falls back to the declared defaults")


## Asset policy: no file under assets/ without a credits row (source, author, licence, date).
func test_every_asset_has_credits() -> void:
	var credits := FileAccess.get_file_as_string("res://assets/credits.csv")
	# a row may name a file, or a folder ending in "/" for generated sets (e.g. cutout parts)
	var folders: Array = []
	for line in credits.split("\n"):
		var first := line.split(",")[0]
		if first.ends_with("/"):
			folders.append(first)
	for path in files_under("res://assets/", [".svg", ".png", ".jpg", ".webp", ".ttf", ".otf", ".ogg", ".wav", ".glb", ".gltf"]):
		var rel: String = str(path).trim_prefix("res://")
		var covered := credits.contains("\n" + rel + ",") or folders.any(func(f): return rel.begins_with(f))
		check(covered, "credits row for " + rel)
	# cutout parts are imported at 2x so the big menu animal stays sharp
	for path in files_under("res://assets/animals/", [".svg.import"]) + files_under("res://assets/looks/", [".svg.import"]):
		check(FileAccess.get_file_as_string(path).contains("svg/scale=2.0"), "imported at 2x: " + str(path))


# --- helpers ---

func read_strings(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var header := f.get_csv_line()
	var en := header.find("en")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > en and row[0] != "":
			out[row[0]] = row[en]
	return out


func files_under(dir: String, exts: Array) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		out.append_array(files_under(dir.path_join(sub), exts))
	for file in d.get_files():
		for e in exts:
			if file.ends_with(e):
				out.append(dir.path_join(file))
	return out


## Strandbal (phase 14): rules, goals, own goals, bounces, teams, washing away and coming back, golden goal.
func test_ball_mode() -> void:
	var m := Match.create(3, "crab", 6, "normal", "ball")
	var s := m.sim
	check(s.mode == "ball" and str(s.rules.island) == "strand" and int(s.rules.tide.max_level) == 6
		and int(s.rules.attack.charges) == int(MatchSim.rules_for("").attack.charges), "mode rules merge over the normal rules")
	check(str(MatchSim.rules_for("").island) == "cove", "the normal rules are untouched by the merge")
	var teams: Array = s.ents.map(func(e): return e.team)
	check(teams == [0, 1, 0, 1, 0, 1], "teams alternate by seat: %s" % str(teams))
	var c := s.field_center()
	check(s.bx == c.x and s.by == c.y and s.kickoff > 0, "the ball starts in the middle with a kickoff pause")
	var blue_left := s.ents.all(func(e): return (e.x < c.x) == (e.team == 0))
	check(blue_left, "blue starts on the left half, orange on the right")

	var idle: Array = []
	for i in 6:
		idle.append({})
	# a shot into the right goal by a blue animal: blue scores, the scorer gets the goal, kickoff resets
	s.kickoff = 0
	var mid := (s.mouth[0] + s.mouth[1]) / 2
	s.bx = s.field[2] - 300
	s.by = mid
	s.bvx = 500
	s.bvy = 0
	s.btouch = 0
	s.step(idle)
	check(s.score_0 == 1 and s.score_1 == 0 and s.ents[0].goals == 1, "a shot into the right goal counts for blue and for the scorer")
	check(s.bx == c.x and s.by == c.y and s.bvx == 0 and s.kickoff > 0, "after a goal the ball is back in the middle")
	var goal_ev := s.events.filter(func(ev): return ev.type == "goal")
	check(goal_ev.size() == 1 and int(goal_ev[0].team) == 0 and int(goal_ev[0].by) == 0, "a goal event names the team and scorer")
	# an own goal: orange's last touch into the right goal still counts for blue, nobody gets the goal
	s.kickoff = 0
	s.bx = s.field[2] - 300
	s.by = mid
	s.bvx = 500
	s.btouch = 1
	s.step(idle)
	check(s.score_0 == 2 and s.ents[1].goals == 0, "an own goal counts for the other team and credits nobody")
	# outside the mouth the ball bounces off the end line
	s.kickoff = 0
	s.bx = s.field[2] - 500
	s.by = s.mouth[0] - 2000
	s.bvx = 600
	s.bvy = 0
	s.step(idle)
	check(s.score_0 == 2 and s.bvx < 0 and s.bx < s.field[2], "outside the goal mouth the ball bounces back")
	# friendly fire is off: a blue shot passes a blue animal and hits an orange one
	s.kickoff = 0
	s.bx = c.x
	s.by = s.field[1] + 1000
	s.bvx = 0
	s.bvy = 0
	var a: MatchSim.Ent = s.ents[0]
	var mate: MatchSim.Ent = s.ents[2]
	var foe: MatchSim.Ent = s.ents[1]
	a.x = 10000
	a.y = mid
	mate.x = 11200
	mate.y = mid
	foe.x = 12600
	foe.y = mid
	var mate_hp := mate.hp
	var foe_hp := foe.hp
	var shoot := idle.duplicate(true)
	shoot[0] = {"a": 0}
	s.step(shoot)
	for i in 12:
		s.step(idle)
	check(mate.hp == mate_hp, "a teammate is not hurt by your shot")
	check(foe.hp < foe_hp, "an opponent behind them is")
	# washed away: gone for a while, then back at their own spawn with full health
	foe.hp = 1
	foe.x = s.field_center().x
	foe.y = s.field[1] + 200 # the side line is deep water at this tide? make sure with a direct hit
	s._damage(foe, 100000, 0)
	s.step(idle)
	check(foe.alive == 0 and foe.respawn > 0 and not s.finished, "an animal at 0 washes away; the match goes on")
	for i in int(s.rules.ball.respawn_ticks):
		s.step(idle)
	check(foe.alive == 1 and foe.hp == foe.max_hp and foe.x > c.x, "after the respawn time it is back on its own half with full health")
	check(not m.human_out(), "in Strandbal the player is never out for good")
	# golden goal: a draw at full time plays on, the next goal wins
	s.score_0 = 1
	s.score_1 = 1
	s.kickoff = 0
	s.tick = int(s.rules.ball.match_ticks) - 1
	s.step(idle)
	check(s.golden == 1 and not s.finished and s.level == int(s.rules.tide.max_level), "a draw at full time goes to golden goal at the highest tide")
	s.kickoff = 0
	s.bx = s.field[0] + 300
	s.by = mid
	s.bvx = -500
	s.btouch = 1
	s.step(idle)
	check(s.finished == 1 and s.score_1 == 2 and s.ents[1].place == 1 and s.ents[0].place == 3, "the golden goal wins it")
	var r := m.human_result()
	check(r.mode == "ball" and r.outcome == "lost" and r.place == 4 and r.score == [1, 2], "result for the player: %s" % str(r))

	# determinism, snapshot and restore in this mode
	var x := Match.create(55, "", 6, "normal", "ball")
	var y := Match.create(55, "", 6, "normal", "ball")
	for i in 1500:
		x.step()
		y.step()
	check(x.sim.state_hash() == y.sim.state_hash(), "Strandbal: same seed -> same state")
	var snap := x.sim.snapshot()
	for i in 900:
		x.step()
	var z := Match.create(55, "", 6, "normal", "ball")
	z.sim.restore(snap)
	for i in 900:
		z.step()
	check(x.sim.state_hash() == z.sim.state_hash() and x.sim.score_0 == z.sim.score_0, "Strandbal: snapshot + restore continues identically")

	# a light balance check (the full one: tests/ball_balance.tscn, 120 matches)
	var bal := BallBalanceRunner.run(8, "normal", 11)
	print("ball: light balance, 8 matches: %.1f goals per match, 0-0 %.0f %%" % [bal.avg_goals, bal.nil_pct])
	check(bal.avg_goals >= 1.0 and bal.avg_goals <= 8.0 and bal.nil_pct <= 40.0, "bots score in Strandbal (%.1f goals per match)" % bal.avg_goals)


## Verstoppertje (phase 2): roles, freezing, disguise, tells, taps, rounds, determinism, rollback, balance.
func test_hide_sim() -> void:
	var m := HideMatch.create(21, "crab", 6, "normal")
	var s := m.sim
	var seekers: Array = []
	for r in 3:
		seekers.append(range(6).filter(func(i): return s.role_for(i, r) == HideSim.SEEKER))
	check(seekers == [[2, 5], [1, 4], [0, 3]], "2 seekers per round and every seat seeks once: %s" % str(seekers))
	check(s.phase == HideSim.PHASE_HIDE and s.ents[0].role == HideSim.HIDER, "the session starts hiding; the player (seat 0) hides first")
	var idle: Array = []
	for i in 6:
		idle.append({})
	# seekers can't move while the others hide
	var seeker: HideSim.Ent = s.ents[2]
	var sx := seeker.x
	var go := idle.duplicate(true)
	go[2] = {"m": 0}
	s.step(go)
	check(seeker.x == sx, "a seeker is frozen in the office during the hide phase")
	# disguise: a hider next to a prop turns into that kind; standing still makes it look like one
	var hider: HideSim.Ent = s.ents[1]
	var prop: Array = []
	for p in s.props:
		if s.tile_at(p[1] - 900, p[2]) == 2 and s.walkable(p[1] - 900, p[2]): # a prop on sand with sand to its left
			prop = p
			break
	check(not prop.is_empty(), "the map has props on sand")
	hider.x = prop[1] - 900
	hider.y = prop[2]
	var act := idle.duplicate(true)
	act[1] = {"a": 0} # towards the prop (east)
	s.step(act)
	check(hider.disguise == int(prop[0]), "a hider becomes the prop it aims at (kind %d)" % hider.disguise)
	for i in int(s.rules.still_ticks):
		s.step(idle)
	check(s.looks_like(hider) == int(prop[0]), "standing still it looks exactly like that prop")
	# moving leaves tells: footprints on sand
	var walk := idle.duplicate(true)
	walk[1] = {"m": 2048} # west, on the sand
	for i in 20:
		s.step(walk)
	check(s.looks_like(hider) == -1 and s.tells.any(func(t): return t.kind == 0), "a moving hider wobbles and leaves footprints on sand")
	# seek phase: a tap on the hider finds it, a tap on a real prop makes the seeker dizzy
	s.phase_left = 1
	s.step(idle)
	check(s.phase == HideSim.PHASE_SEEK, "after the hide time the seek phase starts")
	seeker.x = hider.x - 1000
	seeker.y = hider.y
	seeker.cooldown = 0
	var tap := idle.duplicate(true)
	tap[2] = {"a": 0, "sd": 1000}
	s.step(tap)
	check(hider.role == HideSim.GULL and hider.found_by == 2 and seeker.points == int(s.rules.points.seeker_find), "a tap on the hider: found, it becomes a gull, the seeker scores")
	var other: Array = s.props[0]
	for p in s.props:
		if s.walkable(p[1] - 1000, p[2]) and Fx.dist(p[1] - hider.x, p[2] - hider.y) > 3000 and not s.ents.any(func(e): return e.role == HideSim.HIDER and Fx.dist(e.x - p[1], e.y - p[2]) < 1500):
			other = p
			break
	seeker.x = other[1] - 1000
	seeker.y = other[2]
	seeker.cooldown = 0
	var before := seeker.points
	s.step(tap)
	check(seeker.dizzy > 0 and seeker.points == maxi(0, before + int(s.rules.points.seeker_miss)), "a tap on a real prop: dizzy and a point less")
	# everyone found -> reveal straight away, seekers get the bonus
	for e in s.ents:
		if e.role == HideSim.HIDER:
			e.role = HideSim.GULL
			e.found_tick = s.tick
	s.step(idle)
	check(s.phase == HideSim.PHASE_REVEAL, "when every hider is found the round ends at once")
	# the session ends after 3 rounds with places by points
	var guard := 0
	while not m.finished() and guard < 40000:
		m.step({})
		guard += 1
	var res := s.result()
	var places: Array = res.map(func(r): return int(r.place))
	places.sort()
	check(m.finished() and s.round_no == 2 and places == [1, 2, 3, 4, 5, 6], "3 rounds, then places 1-6 by points")
	check(m.human_result().mode == "hide" and m.human_result().has("points"), "a result for the player")

	# determinism and snapshot/restore
	var a := HideMatch.create(77, "", 6, "normal")
	var b := HideMatch.create(77, "", 6, "normal")
	for i in 2500:
		a.step()
		b.step()
	check(a.sim.state_hash() == b.sim.state_hash(), "Verstoppertje: same seed -> same state")
	var snap := a.sim.snapshot()
	for i in 1500:
		a.step()
	var c := HideMatch.create(77, "", 6, "normal")
	c.sim.restore(snap)
	for i in 1500:
		c.step()
	check(a.sim.state_hash() == c.sim.state_hash(), "Verstoppertje: snapshot + restore continues identically")

	# rollback: 4 screens with lag end identical to a reference run with all input known
	var n := 4
	var animals := ["crab", "octopus", "gull", "crab"]
	var clients: Array = []
	for i in n:
		clients.append(Rollback.new(HideMatch.create_online(5150, animals, 6, "normal"), i))
	var net := RandomNumberGenerator.new()
	net.seed = 3
	var flight: Array = []
	var ticks := 900
	var stp := 0
	while clients.any(func(cl): return cl.tick < ticks) and stp < ticks * 4:
		stp += 1
		for msg in flight.filter(func(x): return x[0] <= stp):
			clients[msg[1]].remote_input(msg[2], msg[3], msg[4])
		flight = flight.filter(func(x): return x[0] > stp)
		for i in n:
			var cl: Rollback = clients[i]
			if cl.tick >= ticks or not cl.can_advance():
				continue
			cl.local_input([(stp * 97 + i * 1000) % 4096, 0 if stp % 40 == 0 else -1, -1, -1]) # walk around, act now and then
			for out in cl.outbox:
				for j in n:
					if j != i:
						flight.append([stp + net.randi_range(1, 7), j, i, out[0], out[1]])
			cl.outbox.clear()
			cl.advance()
	for msg in flight:
		clients[msg[1]].remote_input(msg[2], msg[3], msg[4])
	var hashes: Array = clients.map(func(cl): return cl.settle())
	var inputs: Dictionary = clients[0].confirmed_inputs(ticks)
	var ref := HideMatch.create_online(5150, animals, 6, "normal")
	for t in ticks:
		var cmds := {}
		for st in ref.humans:
			cmds[st] = inputs[st][t]
		ref.step_many(cmds)
	var rbs: int = clients.reduce(func(acc, cl): return acc + cl.rollbacks, 0)
	check(hashes.all(func(h): return h == ref.sim.state_hash()), "Verstoppertje rollback: 4 screens with lag end identical to the reference (%d rollbacks)" % rbs)
	check(rbs > 0, "Verstoppertje rollback: predictions really were corrected")

	var bal := HideBalanceRunner.run(6, "normal", 3)
	print("hide: light balance, 6 sessions: %.2f of 4 found per round" % bal.avg_found)
	check(bal.avg_found >= 1.0 and bal.avg_found <= 3.6, "bots find hiders in Verstoppertje (%.2f per round)" % bal.avg_found)
