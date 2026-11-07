class_name Sfx
extends Node

## All sounds are synthesized by code at startup: noise, sines and envelopes.
## No external audio files.

const RATE := 22050
const VOICES := 16
## Beyond this distance (in cells) from the screen center a sound is not heard.
const HEAR_RANGE := 26.0

var streams := {}
var players: Array[AudioStreamPlayer] = []
var _last := {}
var _rng := RandomNumberGenerator.new()
var muted := false


func _ready() -> void:
	_rng.seed = 7
	streams = {
		"rifle": [_rifle(0), _rifle(1), _rifle(2)],
		"grenade": [_launcher()],
		"cannon": [_cannon(1.0), _cannon(0.9)],
		"turret": [_cannon(1.25)],
		"blast_small": [_explosion(0.7, 1.4), _explosion(0.8, 1.2)],
		"blast_big": [_explosion(1.6, 0.8), _explosion(1.8, 0.7)],
		"build_start": [_build_start()],
		"build_done": [_build_done()],
		"tank_ready": [_tank_ready()],
		"unit_ready": [_unit_ready()],
		"sold": [_sold()],
	}
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)


## Play a sound; dist is the distance from the screen center (in cells), -1 = always loud.
func play(name: String, dist := -1.0, volume_db := 0.0) -> void:
	if muted or not streams.has(name):
		return
	if dist > HEAR_RANGE:
		return
	# The same sound at most ~16 times per second, otherwise a firefight turns into noise.
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -1000)) < 60:
		return
	_last[name] = now
	var db := volume_db
	if dist >= 0.0:
		db -= dist / HEAR_RANGE * 18.0
	var p := _free_player()
	var list: Array = streams[name]
	p.stream = list[_rng.randi() % list.size()]
	p.volume_db = db
	p.pitch_scale = _rng.randf_range(0.94, 1.06)
	p.play()


func _free_player() -> AudioStreamPlayer:
	var oldest := players[0]
	for p in players:
		if not p.playing:
			return p
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	return oldest


# --- synthesis ---------------------------------------------------------------

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var fade := mini(samples.size(), int(0.05 * RATE))
	for i in samples.size():
		var g := minf(1.0, float(samples.size() - 1 - i) / fade)
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.9 * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## One-pole low-pass filter; k closer to 0 is more muffled.
func _lowpass(b: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var y := 0.0
	for i in b.size():
		y += (b[i] - y) * k
		b[i] = y
	return b


func _rifle(variant: int) -> AudioStreamWAV:
	var b := _buf(0.22)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * (0.55 - variant * 0.08)
		var crack := n * exp(-t * 160.0)
		var body := lp * exp(-t * 28.0) * 0.8
		var thump := sin(TAU * (180.0 - variant * 20.0) * t) * exp(-t * 40.0) * 0.5
		b[i] = crack + body + thump
	return _wav(b)


func _launcher() -> AudioStreamWAV:
	var b := _buf(0.35)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.2
		var pop := sin(TAU * (120.0 - t * 150.0) * t) * exp(-t * 18.0)
		b[i] = pop * 0.9 + lp * exp(-t * 14.0) * 0.9
	return _wav(b)


func _cannon(pitch: float) -> AudioStreamWAV:
	var b := _buf(0.9)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.12 * pitch
		lp2 += (n - lp2) * 0.5
		var boom := sin(TAU * (70.0 * pitch - t * 30.0) * t) * exp(-t * 6.0)
		var blast := lp * exp(-t * 5.0) * 1.4
		var crack := lp2 * exp(-t * 80.0) * 0.5
		b[i] = boom + blast + crack
	return _wav(_lowpass(b, 0.35))


func _explosion(length: float, bright: float) -> AudioStreamWAV:
	var b := _buf(length + 0.4)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.05 * bright
		lp2 += (n - lp2) * 0.25 * bright
		var env := (1.0 - exp(-t * 300.0)) * exp(-t * 3.2 / length)
		var rumble := lp * 3.0 * env
		var hiss := lp2 * exp(-t * 14.0 / length) * 0.35
		var sub := sin(TAU * (48.0 - t * 18.0) * t) * exp(-t * 4.0 / length) * 0.9
		# Debris: rare short clicks in the tail.
		var debris := 0.0
		if t > 0.15 and _rng.randf() < 0.002:
			debris = _rng.randf_range(-1.0, 1.0) * 0.4
		b[i] = rumble + hiss + sub + debris
	return _wav(_lowpass(_lowpass(b, 0.18), 0.3))


## Metallic hit: a few inharmonic overtones with a fast decay.
func _clank(b: PackedFloat32Array, at: float, base: float, amp: float) -> void:
	var start := int(at * RATE)
	var partials := [1.0, 2.76, 5.4, 8.93]
	for i in range(start, mini(b.size(), start + int(0.4 * RATE))):
		var t := float(i - start) / RATE
		var v := 0.0
		for k in partials.size():
			v += sin(TAU * base * partials[k] * t) * exp(-t * (14.0 + k * 9.0)) / (k + 1)
		v += _rng.randf_range(-1.0, 1.0) * exp(-t * 200.0) * 0.6
		b[i] += v * amp


func _build_start() -> AudioStreamWAV:
	var b := _buf(1.1)
	_clank(b, 0.0, 310.0, 1.0)
	_clank(b, 0.22, 290.0, 0.8)
	_clank(b, 0.42, 330.0, 0.9)
	# Dull thud of a load being set down.
	for i in range(int(0.6 * RATE), b.size()):
		var t := float(i) / RATE - 0.6
		b[i] += sin(TAU * 60.0 * t) * exp(-t * 9.0) * 0.9
	return _wav(_lowpass(b, 0.35))


func _build_done() -> AudioStreamWAV:
	var b := _buf(1.3)
	_clank(b, 0.0, 240.0, 0.6)
	var notes := [[0.12, 523.25], [0.3, 659.25], [0.48, 783.99]]
	for nt in notes:
		var start := int(nt[0] * RATE)
		for i in range(start, b.size()):
			var t := float(i - start) / RATE
			var f: float = nt[1]
			b[i] += (sin(TAU * f * t) + 0.1 * sin(TAU * f * 2.0 * t)) * exp(-t * 6.0) * minf(1.0, t * 200.0) * 0.5
	return _wav(b)


func _tank_ready() -> AudioStreamWAV:
	var b := _buf(1.6)
	var lp := 0.0
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		# Engine: revs rise and fall back to idle.
		var rpm := 28.0 + 40.0 * exp(-pow((t - 0.45) * 3.0, 2.0)) + 6.0 * t
		phase += rpm / RATE
		var saw := fmod(phase, 1.0) * 2.0 - 1.0
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.08
		var env := minf(1.0, t * 6.0) * minf(1.0, (1.6 - t) * 3.0)
		b[i] = (saw * 0.6 + lp * 1.5) * env
	b = _lowpass(b, 0.25)
	_clank(b, 0.02, 180.0, 0.5)
	_clank(b, 1.1, 200.0, 0.35)
	return _wav(b)


func _unit_ready() -> AudioStreamWAV:
	var b := _buf(0.5)
	# Radio click and two short beeps.
	for i in int(0.015 * RATE):
		b[i] = _rng.randf_range(-1.0, 1.0) * 0.6
	var beeps := [[0.05, 880.0], [0.17, 1175.0]]
	for bp in beeps:
		var start := int(bp[0] * RATE)
		for i in range(start, mini(b.size(), start + int(0.09 * RATE))):
			var t := float(i - start) / RATE
			var env := minf(1.0, t * 400.0) * minf(1.0, (0.09 - t) * 300.0)
			b[i] += sign(sin(TAU * bp[1] * t)) * 0.08 * env + sin(TAU * bp[1] * t) * 0.3 * env
	var lp := 0.0
	for i in range(int(0.3 * RATE), b.size()):
		var n := _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.3
		var t := float(i) / RATE - 0.3
		b[i] += lp * 0.25 * exp(-t * 25.0)
	return _wav(_lowpass(b, 0.5))


func _sold() -> AudioStreamWAV:
	var b := _buf(0.6)
	_clank(b, 0.0, 400.0, 0.6)
	var notes := [[0.08, 987.77], [0.2, 1318.5]]
	for nt in notes:
		var start := int(nt[0] * RATE)
		for i in range(start, b.size()):
			var t := float(i - start) / RATE
			b[i] += sin(TAU * nt[1] * t) * exp(-t * 9.0) * 0.5
	return _wav(b)
