extends Node
class_name ChatSystem
## Handles sending and receiving chat messages across all peers.
## Add as a child of Main and call init() with the Main node.
##
## Host chat commands:
##   !hint           — reveal next hint to all players
##   !hint PlayerName — reveal next hint privately to a specific player

var _main: Node = null


func init(main: Node) -> void:
	_main = main


func send_message(text: String) -> void:
	## Called by ChatHUD when the local player submits a message.
	if not NetworkManager.is_multiplayer_active():
		return

	# Host-only commands — handled locally, never broadcast
	if NetworkManager.is_server() and text.begins_with("!"):
		_handle_host_command(text.strip_edges())
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


func _handle_host_command(cmd: String) -> void:
	## Parse and execute host-only commands.
	if not RaceManager.is_race_active():
		_show_system_message("⚠ No race in progress.")
		return

	if cmd == "!hint":
		# Reveal to all players
		var revealed := RaceManager.reveal_hint_now()
		if not revealed:
			_show_system_message("⚠ No hints available.")
	elif cmd.begins_with("!hint "):
		var target_name := cmd.substr(6).strip_edges()
		var target_peer := _find_peer_by_name(target_name)
		if target_peer == -1:
			_show_system_message("⚠ Player \"%s\" not found." % target_name)
		else:
			RaceManager.reveal_hint_to_peer(target_peer)
			_show_system_message("💡 Hint sent privately to %s." % target_name)
	else:
		_show_system_message("⚠ Unknown command. Try: !hint  or  !hint PlayerName")


func _find_peer_by_name(player_name: String) -> int:
	## Returns peer ID for a player name, or -1 if not found.
	for pid in NetworkManager.get_connected_peers():
		if NetworkManager.get_player_name(pid).strip_edges().to_lower() == player_name.strip_edges().to_lower():
			return pid
	return -1


func _show_system_message(text: String) -> void:
	## Shows a local system message only to the host (not broadcast).
	MultiplayerEvents.emit_chat_message("[System]", "", text, Color(0.6, 0.6, 0.6))


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
