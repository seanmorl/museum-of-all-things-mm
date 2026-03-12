extends StaticBody3D

func interact() -> void:
	# Block terminal access during daily challenge to prevent cheating
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_node("DailyChallengeManager"):
		var dc_manager := main.get_node("DailyChallengeManager")
		if dc_manager and dc_manager.has_method("is_active") and dc_manager.is_active():
			if main.has_method("_show_system_message"):
				main._show_system_message("⚠ Terminal disabled during Daily Challenge")
			return
	UIEvents.emit_open_terminal_menu()
