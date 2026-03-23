# Microsoft TTS - Brian (British English) by Default! 🎙️

## ✅ Using Microsoft Edge Voices (Same as text-to-speech.online)

**High-quality neural voices - completely FREE!**

---

## Default Voice: Brian (British Male)

```gdscript
# Just use it! Brian is the default!
TTSManager.speak("Hello! I'm Brian, your British narrator.")
```

---

## Quick Start

```gdscript
# Basic usage
TTSManager.speak("Welcome to the museum!")

# Change to a different voice
TTSManager.set_voice("Aria")  # American female
TTSManager.speak("Hi there!")

# Change to British female
TTSManager.set_voice("Sonia")
TTSManager.speak("British accent activated!")

# Change speed
TTSManager.set_speed(1.2)  # 20% faster
TTSManager.speak "Speeding up!")

# Back to normal speed
TTSManager.set_speed(1.0)
```

---

## Available Voices

### 🇬🇧 British English (Default)
| Friendly Name | Voice Code | Gender |
|---------------|------------|--------|
| **Brian** ⭐ | `en-GB-RyanNeural` | Male (Default) |
| Sonia | `en-GB-SoniaNeural` | Female |
| Libby | `en-GB-LibbyNeural` | Female |
| Abbi | `en-GB-AbbiNeural` | Female |
| Alfie | `en-GB-AlfieNeural` | Male |
| Bella | `en-GB-BellaNeural` | Female |
| Elliot | `en-GB-ElliotNeural` | Male |
| Ethan | `en-GB-EthanNeural` | Male |
| Hollie | `en-GB-HollieNeural` | Female |
| Maisie | `en-GB-MaisieNeural` | Female |
| Thomas | `en-GB-ThomasNeural` | Male |

### 🇺🇸 American English
| Friendly Name | Voice Code | Gender |
|---------------|------------|--------|
| Aria | `en-US-AriaNeural` | Female |
| Guy | `en-US-GuyNeural` | Male |
| Jenny | `en-US-JennyNeural` | Female |
| Davis | `en-US-DavisNeural` | Male |
| Jane | `en-US-JaneNeural` | Female |
| Jason | `en-US-JasonNeural` | Male |
| Sara | `en-US-SaraNeural` | Female |
| Tony | `en-US-TonyNeural` | Male |
| + 15 more voices | | |

### 🇦🇺 Australian English
- Natasha (Female)
- William (Male)
- + 10 more voices

### 🇪🇺 European Languages
- **German:** Conrad, Katja
- **French:** Henri, Denise
- **Spanish:** Alvaro, Elvira
- **Italian:** Diego, Elsa
- **Portuguese:** Antonio, Francisca (BR), Duarte, Raquel (PT)
- **Dutch:** Colette, Maarten
- **Polish:** Marek, Zofia
- **Swedish:** Mattias, Sofie

### 🇯🇵 Asian Languages
- **Japanese:** Keita (Male), Nanami (Female)
- **Chinese:** Yunxi, Yunjian (Male), Xiaoxiao, Xiaoyi (Female)
- **Korean:** Hyunsu, InJoon (Male), SunHi (Female)

**Total: 100+ voices!**

---

## Usage Examples

### In Your Game:

```gdscript
extends Control

# NPC dialogue with TTS
func _on_npc_talk(npc_name: String, dialogue: String):
    $SubtitleLabel.text = "%s: %s" % [npc_name, dialogue]
    TTSManager.speak(dialogue)

# Voice selector UI
func _on_voice_dropdown_selected(index: int):
    var voices = TTSManager.get_voices()
    if index < voices.size():
        TTSManager.set_voice(voices[index])
        TTSManager.speak("Voice changed to " + voices[index])

# Speed control
func _on_speed_slider_changed(value: float):
    TTSManager.set_speed(value)

# Test button
func _on_test_button_pressed():
    TTSManager.speak("Testing TTS! One two three.")
```

### Using Friendly Names:

```gdscript
# These all work:
TTSManager.set_voice("Brian")           # British Male (default)
TTSManager.set_voice("Sonia")           # British Female
TTSManager.set_voice("Aria")            # American Female
TTSManager.set_voice("en-GB-RyanNeural") # Full code also works
```

---

## API Details

**Using:** Microsoft Edge TTS API (same as text-to-speech.online)

- **Endpoint:** `https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1`
- **Quality:** 16khz 128kbps MP3
- **Cost:** FREE
- **Limits:** None known (generous free tier)
- **Requires:** Internet connection

---

## Features

✅ **High-quality neural voices** (same as Azure Cognitive Services)
✅ **100+ voices** in 40+ languages
✅ **British English by default** (Brian/Ryan)
✅ **Completely FREE** - no credit card, no API key
✅ **Caching** - cached audio plays instantly
✅ **Queue system** - multiple requests handled automatically
✅ **Speed control** - 0.5x to 2.0x

---

## Export for Distribution

**Perfect! Nothing extra needed:**

```
✓ Export from Godot
✓ Distribute your .exe
✓ TTS works for all players!
```

**No bundling, no API keys, no setup!**

---

## Troubleshooting

### "TTS not working"
1. Check internet connection
2. Check firewall allows game
3. Look at console for errors

### "Wrong voice"
Make sure you're using correct voice name:
```gdscript
TTSManager.set_voice("Brian")  # British Male
TTSManager.set_voice("Ryan")   # Also works (same voice)
```

### "Too fast/slow"
```gdscript
TTSManager.set_speed(0.8)  # Slower
TTSManager.set_speed(1.0)  # Normal
TTSManager.set_speed(1.5)  # Faster
```

---

## Comparison with Other Services

| Service | Quality | Cost | Voices | CC Needed? |
|---------|---------|------|--------|------------|
| **Microsoft TTS (This)** | ⭐⭐⭐⭐⭐ | Free | 100+ | ❌ No |
| Azure Cognitive Services | ⭐⭐⭐⭐⭐ | $1/M chars | 100+ | ✅ Yes |
| Amazon Polly | ⭐⭐⭐⭐ | Free tier | 50+ | ✅ Yes |
| Google TTS | ⭐⭐⭐⭐ | Free tier | 30+ | ✅ Yes |
| TTSMP3.com | ⭐⭐⭐ | Free | 20+ | ❌ No |

**This is the best free option!** 🎉

---

## Test It Now!

In Godot, press play:
```gdscript
TTSManager.speak("Hello! I'm Brian, your British narrator. This is Microsoft's high-quality neural TTS - completely free!")
```

Should hear British male voice! 🇬🇧

---

## Migration from Old TTS

```gdscript
# OLD (FreeTTS)
FreeTTS.ttsmp3_voice = "Salli"

# NEW (MicrosoftTTS)
TTSManager.set_voice("Brian")  # or "Salli" etc.

# OLD
TTSManager.set_voicerss_key("key")

# NEW
# Not needed! Microsoft TTS is free, no key required!
```

---

**Enjoy Brian and the 100+ Microsoft voices! 🎙️**
