class_name HpBar3D
extends Sprite3D

# Two-layer HP bar (spec 11 §7.3): instant red drop, delayed white "ghost"
# bar that catches up over GHOST_FALL_S. Implementation paints a small
# Image with three horizontal stripes (bg/ghost/current) and sets it as
# the Sprite3D albedo; Sprite3D handles billboarding for free.

const TEX_W := 64
const TEX_H := 8
const GHOST_FALL_S := 0.4   # spec 11 §7.3
const COLOR_BG := Color(0.10, 0.10, 0.10, 0.80)
const COLOR_GHOST := Color(0.95, 0.95, 0.95, 0.85)
const COLOR_CURRENT := Color(0.90, 0.20, 0.20, 1.0)

var _current_ratio: float = 1.0
var _ghost_ratio: float = 1.0
var _ghost_target: float = 1.0
var _ghost_velocity: float = 0.0   # ratio units / second

func _ready() -> void:
	# Billboard / filter enums live on BaseMaterial3D, not SpriteBase3D.
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pixel_size = 0.025
	no_depth_test = true
	shaded = false
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_redraw()

func set_hp(current: int, maximum: int) -> void:
	var ratio := 0.0
	if maximum > 0:
		ratio = clampf(float(current) / float(maximum), 0.0, 1.0)
	# Current bar tracks instantly (red shrinks on the same frame as damage).
	_current_ratio = ratio
	# Ghost target is the new ratio; the actual `_ghost_ratio` lags behind
	# and is animated by _process. On heal (ratio went up) snap ghost up so
	# it doesn't trail the wrong direction.
	if ratio > _ghost_ratio:
		_ghost_ratio = ratio
	_ghost_target = ratio
	_redraw()

func _process(delta: float) -> void:
	if is_equal_approx(_ghost_ratio, _ghost_target):
		return
	# Linear catch-up over GHOST_FALL_S, regardless of damage size — the
	# spec's ~400 ms is a feel constant, not a damage-proportional time.
	var step := delta / GHOST_FALL_S
	if _ghost_ratio > _ghost_target:
		_ghost_ratio = maxf(_ghost_target, _ghost_ratio - step)
	else:
		_ghost_ratio = minf(_ghost_target, _ghost_ratio + step)
	_redraw()

func _redraw() -> void:
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	img.fill(COLOR_BG)
	var ghost_w := int(round(TEX_W * _ghost_ratio))
	var cur_w := int(round(TEX_W * _current_ratio))
	for y in TEX_H:
		for x in ghost_w:
			img.set_pixel(x, y, COLOR_GHOST)
		for x in cur_w:
			img.set_pixel(x, y, COLOR_CURRENT)
	texture = ImageTexture.create_from_image(img)
