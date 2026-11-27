extends Node

static func play_one_shot(sound_stream: AudioStream, pitch_variance: float = 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = sound_stream
	play_one_shot_player(player, pitch_variance)

static func play_one_shot_player(player: AudioStreamPlayer, pitch_variance: float = 0.0) -> void:
	if pitch_variance > 0.0:
		player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(player)
	
	player.play()
	player.finished.connect(player.queue_free)
