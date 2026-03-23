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

	# Set required scopes
	if twitch_service.scopes == null:
		twitch_service.scopes = OAuthScopes.new()

	twitch_service.scopes.add_scope("chat:read")
	twitch_service.scopes.add_scope("chat:edit")
