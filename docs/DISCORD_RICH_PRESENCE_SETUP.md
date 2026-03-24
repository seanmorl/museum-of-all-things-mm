# Discord Rich Presence Setup Guide

## Overview
Discord Rich Presence shows your game activity to friends on Discord, displaying:
- Current state (In Menu, In Lobby, Racing, Exploring)
- Race target article
- Current room being explored
- Party size (number of players)
- Session duration

## ⚠️ IMPORTANT: Complete These Steps First

### 1. Create Discord Developer Team
1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click your profile icon → "Developer Settings"
3. Create a Developer Team if you don't have one

### 2. Create Discord Application
1. In Discord Developer Portal, click "New Application"
2. Name it "Museum of All Things" (or your preferred name)
3. Accept the terms

### 3. Enable Discord Social SDK
1. In your application dashboard, go to "Features" → "Social SDK"
2. Click "Enable"
3. Note your **Application ID** (shown at the top)

### 4. Configure OAuth2
1. Go to "OAuth2" → "General"
2. Add Redirect URI: `http://localhost`
3. Save changes

## Installation

### 1. Update Application ID
1. Open `scenes/util/DiscordRichPresence.gd`
2. Replace line 8 with YOUR Application ID:
   ```gdscript
   const DISCORD_APPLICATION_ID: int = 1234567890123456789  # REPLACE THIS
   ```

### 2. Upload Rich Presence Images
1. In Discord Developer Portal, go to "Features" → "Social SDK" → "Art Assets"
2. Click "Add Image"
3. Upload these images (512x512 recommended):
   - **game_icon** - Main game logo
   - **race** - Racing icon (can be same as game_icon)
4. Names must match exactly (case-sensitive!)

### 3. Test in Game
1. Run the game
2. Make sure Discord is running
3. Check console for `[Discord]` messages
4. Your status should appear in Discord after ~5 seconds

## Expected Console Output

```
[Discord] Initialization started, waiting for authorization...
[Discord] INFO: Connection successful
[Discord] Authorization successful, connecting...
[Discord] Connected successfully!
[Discord] Race started to: Cocaine
```

## Discord Status Examples

### Racing
```
🎮 Museum of All Things
🏁 Racing
Target: Cocaine
00:45 elapsed
In a party of 3/8
```

### Exploring
```
🎮 Museum of All Things
In Lobby
Exploring: Ancient Egypt
In a party of 2/8
```

### Menu
```
🎮 Museum of All Things
In Menu
Session: 00:15:32
```

## Troubleshooting

### "Authorization failed"
- Ensure Discord is running
- Check Application ID is correct (must be integer, not string)
- Verify OAuth2 redirect URI is set to `http://localhost`

### "Connected successfully" but no status shows
- Upload images to Discord Developer Portal
- Wait 1-2 minutes for images to propagate
- Check image names match exactly (case-sensitive)

### No [Discord] messages in console
- Check if DiscordSocialSDK is loaded (check project.godot autoloads)
- SDK may not load in some editor configurations
- Will work properly in exported builds

### Status not updating
- Discord updates presence with ~5 second delay
- Check `_presence_dirty` flag is being set
- Ensure `Discord.run_callbacks()` is being called

## Customization

Edit `scenes/util/DiscordRichPresence.gd`:

### Change Activity Type
```gdscript
# Line ~87
activity.set_type(DiscordActivityTypes.PLAYING)
# Options: PLAYING, STREAMING, LISTENING, WATCHING, COMPETING
```

### Add Custom Buttons (Future Enhancement)
```gdscript
# Requires additional SDK setup
var button := DiscordActivityButton.new()
button.set_label("Join Game")
button.set_url("your_game_url")
activity.add_button(button)
```

### Change Images
```gdscript
# Line ~107
assets.set_large_image("your_image_name")
assets.set_small_image("your_small_image_name")
```

### Modify State Messages
```gdscript
# Line ~137 (race start)
_current_state = "Your Custom State"
```

## API Reference

### Available Methods

```gdscript
# Set current room (auto-called when entering rooms)
DiscordRichPresence.set_room("Room Name")

# Set state to in menu
DiscordRichPresence.set_in_menu()

# Set state to in lobby
DiscordRichPresence.set_in_lobby()

# Force presence update
DiscordRichPresence._update_presence()
```

### Events Automatically Handled
- ✅ Race start/end/cancel
- ✅ Player join/leave
- ✅ Room changes
- ✅ Party size updates
- ✅ Discord connection/disconnection

## Important Notes

1. **Discord Must Be Running** - Rich Presence only works when Discord desktop/mobile app is open

2. **Editor Limitations** - SDK may not fully initialize in Godot editor, but will work in exported builds

3. **Rate Limiting** - Discord limits presence updates to once per 15 seconds (SDK handles this automatically)

4. **Privacy** - Players can disable Rich Presence in their Discord settings

5. **Callbacks Required** - The SDK uses callbacks, not Godot signals. Never remove `Discord.run_callbacks()` from `_process()`

## Support

For SDK issues, see: https://github.com/thiagola92/discord-social-sdk

For game-specific issues, check console logs for `[Discord]` messages.
