extends Node
## Manual Twitch Service Configuration
## Add this as an autoload or child of Main if you want explicit control

@export var client_id: String
@export var client_secret: String
@export var redirect_url: String = "http://localhost:17428/oauth/callback"
@export var channel_name: String

var twitch_service: TwitchService = null
var is_connected: bool = false

func _ready() -> void:
	# Try to get existing TwitchService instance
	twitch_service = TwitchService.instance
	
	if twitch_service == null:
		# Create new service if doesn't exist
		var service_scene := load("res://addons/twitcher/twitch_service.tscn")
		if service_scene:
			twitch_service = service_scene.instantiate()
			add_child(twitch_service)
			print("TwitchSetup: Created new TwitchService instance")
		else:
			print("TwitchSetup: Twitcher addon not found!")
			return
	
	# Configure OAuth settings
	if twitch_service.oauth_setting == null:
		twitch_service.oauth_setting = OAuthSetting.new()
	
	twitch_service.oauth_setting.client_id = client_id
	# Note: client_secret should be stored securely, not in plain text
	
	# Set required scopes for chat voting
	if twitch_service.scopes == null:
		twitch_service.scopes = OAuthScopes.new()
	
	# Required scopes for chat voting
	twitch_service.scopes.add_scope("chat:read")
	twitch_service.scopes.add_scope("chat:edit")


func connect_to_twitch() -> void:
	## Call this to initiate Twitch connection
	if twitch_service == null:
		print("TwitchSetup: TwitchService not available")
		return
	
	print("TwitchSetup: Starting Twitch authentication...")
	var success := await twitch_service.setup()
	
	if success:
		is_connected = true
		var user := await twitch_service.get_current_user()
		if user:
			print("TwitchSetup: Connected as ", user.display_name)
			print("TwitchSetup: Channel ID: ", user.id)
	else:
		is_connected = false
		print("TwitchSetup: Authentication failed")


func disconnect_from_twitch() -> void:
	## Call this to disconnect from Twitch
	if twitch_service:
		await twitch_service.unsetup()
		is_connected = false
		print("TwitchSetup: Disconnected from Twitch")


func get_channel_name() -> String:
	## Get the connected Twitch channel name
	if is_connected and twitch_service:
		var user := await twitch_service.get_current_user()
		if user:
			return user.login
	return channel_name
