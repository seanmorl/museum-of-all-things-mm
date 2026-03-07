extends Node
class_name ChatSystem
## Handles sending and receiving chat messages across all peers.
## Add as a child of Main and call init() with the Main node.

var _main: Node = null


func init(main: Node) -> void:
	_main = main


func send_message(text: String) -> void:
	## Called by ChatHUD when the local player submits a message.
	if not NetworkManager.is_multiplayer_active():
		return

	var peer_id := NetworkManager.get_unique_id()
	var sender_name := NetworkManager.get_player_name(peer_id)
	var pronouns := NetworkManager.get_player_pronouns(peer_id)
	var color := NetworkManager.get_player_color(peer_id)

	# Send to server for rebroadcast (any_peer → server → all)
	if NetworkManager.is_server():
		_rpc_broadcast_chat.rpc(sender_name, pronouns, color.to_html(), text)
	else:
		_rpc_send_chat.rpc_id(1, sender_name, pronouns, color.to_html(), text)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_chat(sender_name: String, pronouns: String, color_html: String, text: String) -> void:
	## Received on server from a client. Rebroadcast to everyone.
	if not NetworkManager.is_server():
		return
	_rpc_broadcast_chat.rpc(sender_name, pronouns, color_html, text)


@rpc("authority", "call_local", "reliable")
func _rpc_broadcast_chat(sender_name: String, pronouns: String, color_html: String, text: String) -> void:
	## Received on all peers including host. Fire the signal.
	var color := Color.html(color_html)
	MultiplayerEvents.emit_chat_message(sender_name, pronouns, text, color)
