extends Node
## Autoload: TwitchManager
## Handles connection to Twitch IRC via WebSocket for chat integrations.

signal connected
signal disconnected
signal message_received(voter_name: String, message: String)
signal color_change_requested(color: Color)

var socket := WebSocketPeer.new()
var channel_name: String = ""
var is_connected: bool = false
var _last_state: int = WebSocketPeer.STATE_CLOSED

func connect_to_twitch(channel: String) -> void:
	if is_connected:
		disconnect_from_twitch()
	
	channel_name = channel.to_lower().strip_edges()
	if channel_name.is_empty():
		return
		
	var err = socket.connect_to_url("wss://irc-ws.chat.twitch.tv:443")
	if err != OK:
		Log.error("Twitch", "Could not connect to Twitch WebSocket: %s" % error_string(err))
		return
	
	Log.info("Twitch", "Connecting to Twitch channel: %s" % channel_name)
	set_process(true)

func disconnect_from_twitch() -> void:
	socket.close()
	is_connected = false
	disconnected.emit()
	Log.info("Twitch", "Disconnected from Twitch")

func _ready() -> void:
	set_process(false)

func _process(_delta: float) -> void:
	socket.poll()
	var state = socket.get_ready_state()
	
	if state != _last_state:
		_on_state_changed(state)
		_last_state = state
		
	if state == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			_handle_message(packet.get_string_from_utf8())

func _on_state_changed(state: int) -> void:
	if state == WebSocketPeer.STATE_OPEN:
		# Login anonymously
		socket.send_text("PASS SCHMOOPIIE") # Twitch's recommended anon password
		socket.send_text("NICK justinfan%d" % (randi() % 100000))
		socket.send_text("JOIN #%s" % channel_name)
		is_connected = true
		connected.emit()
	elif state == WebSocketPeer.STATE_CLOSED:
		is_connected = false
		disconnected.emit()
		set_process(false)

func _handle_message(raw_message: String) -> void:
	# Twitch IRC messages look like: 
	# :user!user@user.tmi.twitch.tv PRIVMSG #channel :message text
	# PING :tmi.twitch.tv
	
	if raw_message.begins_with("PING"):
		socket.send_text("PONG :tmi.twitch.tv")
		return
		
	if "PRIVMSG" in raw_message:
		var parts = raw_message.split("PRIVMSG #%s :" % channel_name)
		if parts.size() < 2: return
		
		var msg_content = parts[1].strip_edges()
		var sender_parts = parts[0].split("!")
		if sender_parts.size() < 1: return
		
		var sender = sender_parts[0].trim_prefix(":")
		
		_parse_command(sender, msg_content)
		message_received.emit(sender, msg_content)

func _parse_command(sender: String, message: String) -> void:
	var msg = message.to_lower()
	
	# 1. Voting (1-5)
	if msg in ["1", "2", "3", "4", "5"]:
		if RaceManager.is_vote_active():
			RaceManager.cast_twitch_vote(sender, msg.to_int() - 1)
			
	# 2. Color Change (!color #ff00ff or !color red)
	if msg.begins_with("!color "):
		var color_str = msg.trim_prefix("!color ").strip_edges()
		var color = Color.html(color_str) if color_str.begins_with("#") else Color.from_string(color_str, Color.WHITE)
		color_change_requested.emit(color)
		
	# 3. Suggest Start (!start Egypt)
	if msg.begins_with("!start "):
		var article = message.trim_prefix("!start ").strip_edges()
		if not article.is_empty() and RaceManager.get_state() == RaceManager.State.IDLE:
			UIEvents.emit_set_custom_door(article)
