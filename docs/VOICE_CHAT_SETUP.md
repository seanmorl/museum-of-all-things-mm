# Voice Chat & Spatial TTS Setup

## Proximity Voice Chat

Voice chat is now available with proximity-based audio. Players within 15 meters can hear each other.

### Controls
- **V** - Push-to-talk (hold to talk)
- **M** - Toggle mute (in settings)

### How It Works
- Voice audio attenuates with distance
- Maximum range: 15 meters
- Only active players within range are audible
- Voice chat is on the "Voice" audio bus (separate volume control)

### Audio Bus Setup
In the Audio bus layout, you'll find:
- **Voice** bus - Controls voice chat volume
- Adjust this bus to control overall voice chat volume

---

## Spatial TTS (Text-To-Speech)

**Note:** Godot 4.x's built-in `DisplayServer.tts_speak()` outputs directly to system audio and doesn't support spatial positioning.

### Current Implementation
- TTS plays at full volume regardless of player position
- Press **E** on an exhibit to toggle TTS narration

### Future Enhancement: True Spatial TTS

To add spatial TTS (where audio fades with distance), you would need:

1. **Third-party TTS Service** that returns audio files:
   - Google Cloud Text-to-Speech
   - Amazon Polly
   - Azure Cognitive Services
   - ElevenLabs

2. **Implementation approach:**
   ```gdscript
   # Example for spatial TTS with external service
   func narrate_spatial(text: String, position: Vector3) -> void:
       var player = AudioStreamPlayer3D.new()
       player.position = position
       player.max_distance = 20.0
       player.attenuation = 0.5
       add_child(player)
       
       # Fetch audio from TTS service
       var audio_stream = await fetch_tts_audio(text)
       player.stream = audio_stream
       player.play()
       
       # Clean up after playback
       player.finished.connect(player.queue_free)
   ```

3. **Required changes:**
   - Modify `TTSManager.gd` to use external TTS API
   - Add HTTP request handling for TTS audio fetch
   - Cache audio files to reduce API calls
   - Add settings for TTS service API key

---

## Settings Integration

Add these to your Settings menu:

```gdscript
# Voice Chat Settings
var voice_enabled: bool = true
var push_to_talk: bool = true  # If false, always transmit when not muted
var voice_volume: float = 1.0

# TTS Settings  
var tts_enabled: bool = true
var tts_volume: float = 1.0
var tts_spatial: bool = false  # Requires external TTS service
```

---

## Technical Notes

### Voice Chat Limitations
- Current implementation is a framework - actual microphone capture requires:
  - `AudioInput` for microphone access
  - Audio encoding (Opus recommended)
  - Network streaming via UDP
  - Jitter buffer for smooth playback

### Recommended Voice Chat Libraries
- **Godot Voice Chat** (community plugin)
- **Vivox** (professional, used by many games)
- **Agora.io** (game voice chat service)
- **Discord GameSDK** (if integrating with Discord)

### Browser Limitations
- Web builds require user gesture to access microphone
- HTTPS required for microphone access
- Some browsers have strict autoplay policies
