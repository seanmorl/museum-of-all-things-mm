## This is a GDscript Node which gets automatically added as Autoload while installing the addon.
## 
## It can run in the background to communicate with Discord.
## You don't need to use it. If you remove it make sure to run [code]DiscordRPC.run_callbacks()[/code] in a [code]_process[/code] function.
##
## @tutorial: https://github.com/vaporvee/discord-rpc-godot/wiki
extends Node

func _ready() -> void:
	pass

func  _process(_delta) -> void:
	pass
