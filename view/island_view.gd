class_name IslandView
extends Node2D
## The island on screen: one rectangle with view/island.gdshader. The sim's tile heights go to the shader as a
## small texture (one texel per tile); the tide level eases towards the sim's level so the water visibly rises.
## Reads the sim, never changes it.

const HEIGHT_SCALE := 25.0 # texel value = height * HEIGHT_SCALE / 255 (heights up to 10 fit)
const MARGIN := 12.0 # tiles of sea around the island
const RISE_S := 0.8 # how long the water takes to rise to a new level on screen
const SHADER := preload("res://view/island.gdshader")
const ATLAS := preload("res://assets/island/atlas.png")

var tile_px := 80.0
var shown_level := 0.0
var _sim # MatchSim, or anything with width, height, heights, level, phase_left, finished and rules.tide
var _mat: ShaderMaterial


## Builds the material for a sim; call once before adding to the tree.
func setup(sim, px_per_tile: float) -> IslandView:
	_sim = sim
	tile_px = px_per_tile
	shown_level = float(sim.level)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("heights", ImageTexture.create_from_image(height_image(sim.width, sim.height, sim.heights)))
	_mat.set_shader_parameter("atlas", ATLAS)
	_mat.set_shader_parameter("grid", Vector2(sim.width, sim.height))
	_mat.set_shader_parameter("margin", MARGIN)
	_mat.set_shader_parameter("height_scale", HEIGHT_SCALE)
	var world: Dictionary = Content.load_json("res://data/palette.json").world
	for key in ["sand_high", "sand", "sand_shade", "wet_sand", "shallow", "deep", "abyss", "foam"]:
		_mat.set_shader_parameter(key, Color(str(world[key])))
	material = _mat
	_apply()
	return self


## One texel per tile, red channel = height (pure function, tested).
static func height_image(width: int, height: int, heights: Array) -> Image:
	var img := Image.create(width, height, false, Image.FORMAT_R8)
	for y in height:
		for x in width:
			img.set_pixel(x, y, Color(clampf(heights[y * width + x] * HEIGHT_SCALE / 255.0, 0.0, 1.0), 0, 0))
	return img


func _process(delta: float) -> void:
	shown_level = move_toward(shown_level, float(_sim.level), delta / RISE_S)
	_apply()


func _apply() -> void:
	var t: Dictionary = _sim.rules.tide
	var warn: bool = _sim.phase_left <= int(t.warn_ticks) and _sim.level < int(t.max_level) and not _sim.finished
	_mat.set_shader_parameter("level", shown_level)
	_mat.set_shader_parameter("warn", 1.0 if warn else 0.0)


func _draw() -> void:
	var m := MARGIN * tile_px
	draw_rect(Rect2(-m, -m, _sim.width * tile_px + 2.0 * m, _sim.height * tile_px + 2.0 * m), Color.WHITE)
