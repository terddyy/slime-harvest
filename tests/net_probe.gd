extends Node
## Test node with two RPCs. The host and the joiner processes both add it at /root/NetProbe.

signal ping_received(from: int, value: int)
signal pong_received(from: int, value: int)


## Host -> joiner.
@rpc("authority", "reliable")
func ping(value: int) -> void:
	ping_received.emit(multiplayer.get_remote_sender_id(), value)
	pong.rpc_id(1, value * 2)


## Joiner -> host.
@rpc("any_peer", "reliable")
func pong(value: int) -> void:
	pong_received.emit(multiplayer.get_remote_sender_id(), value)
