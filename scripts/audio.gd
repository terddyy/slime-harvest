extends Node
## Sound effects and music (autoload "Audio").
## Sounds are WAVs made by tools/gen_audio.py:
##   assets/audio/sfx/<name>.wav    -> Audio.play_sfx("<name>")
##   assets/audio/music/<name>.wav  -> Audio.play_music("<name>")
## Keeps running while the game is paused, so end-screen sounds still play.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const SFX_VOLUME_DB := -4.0
const MUSIC_VOLUME_DB := -12.0  # music sits under the effects
const SILENT_DB := -60.0
const SFX_VOICES := 8  # how many effects can play at the same time
const CROSSFADE_TIME := 1.0

var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx := 0
## Two music players so one can fade out while the other fades in.
var _music_players: Array[AudioStreamPlayer] = []
var _music_index := 0
var _music_name := ""
var _music_tween: Tween
## path -> AudioStream (or null when the file is missing, so we only warn once).
var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.volume_db = SFX_VOLUME_DB
		add_child(player)
		_sfx_players.append(player)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.volume_db = SILENT_DB
		add_child(player)
		_music_players.append(player)


## Plays a one-shot effect. pitch_variation 0.1 means a random pitch between 0.9x and 1.1x,
## so repeated sounds (sword, hits) don't feel robotic.
func play_sfx(sound_name: String, pitch_variation := 0.0) -> void:
	var stream := _load(SFX_DIR + sound_name + ".wav")
	if stream == null:
		return
	# Round-robin: if all voices are busy, the oldest sound gets cut off.
	var player := _sfx_players[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx_players.size()
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


## Crossfades to a looping music track. Does nothing if that track is already playing.
func play_music(track_name: String) -> void:
	if track_name == _music_name:
		return
	var stream := _load(MUSIC_DIR + track_name + ".wav") as AudioStreamWAV
	if stream == null:
		return
	_make_loop(stream)
	_music_name = track_name
	var old_player := _music_players[_music_index]
	_music_index = 1 - _music_index
	var new_player := _music_players[_music_index]
	new_player.stream = stream
	new_player.volume_db = SILENT_DB
	new_player.play()
	_fade(old_player, new_player)


## Fades the current music out (e.g. on the end screen).
func stop_music() -> void:
	_music_name = ""
	_fade(_music_players[_music_index], null)


## Pause menu only: freezes the music where it is (paused=true) or continues it.
## Both players are paused so a crossfade in progress resumes cleanly.
func set_music_paused(paused: bool) -> void:
	for player in _music_players:
		player.stream_paused = paused


func _fade(fade_out: AudioStreamPlayer, fade_in: AudioStreamPlayer) -> void:
	if _music_tween != null:
		_music_tween.kill()
	var fading_out := fade_out != null and fade_out.playing
	if fade_in == null and not fading_out:
		return  # nothing to fade (an empty tween is an error)
	_music_tween = create_tween().set_parallel()
	if fade_in != null:
		_music_tween.tween_property(fade_in, "volume_db", MUSIC_VOLUME_DB, CROSSFADE_TIME * 0.5)
	if fading_out:
		_music_tween.tween_property(fade_out, "volume_db", SILENT_DB, CROSSFADE_TIME)
		_music_tween.chain().tween_callback(fade_out.stop)


## WAV files don't loop by default; loop the whole file. The generator makes each
## track end on silence, so the seam has no click.
func _make_loop(stream: AudioStreamWAV) -> void:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)


func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		if ResourceLoader.exists(path):
			_cache[path] = load(path)
		else:
			push_warning("Audio: missing sound '%s'" % path)
			_cache[path] = null
	return _cache[path]
