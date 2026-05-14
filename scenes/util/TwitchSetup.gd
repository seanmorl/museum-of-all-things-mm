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

	# Twitcher addon is not bundled with the project — skip silently
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
