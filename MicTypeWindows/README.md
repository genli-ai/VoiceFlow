# MicType for Windows

This folder is the Windows implementation scaffold for MicType. It is intentionally isolated from the macOS Swift package so the two build systems do not contaminate each other.

## Current State

- .NET 8 + WPF tray app scaffold
- Global low-level keyboard hook: tap = dictation toggle, hold = command mode, Esc cancels and is swallowed while recording
- NAudio 16 kHz mono recording pipeline
- Clipboard + Ctrl+V insertion with clipboard restore
- UI Automation selected-text read with Ctrl+C fallback
- OpenAI-compatible LLM client, polish prompt, command prompts, reply trigger routing
- JSON settings in `%APPDATA%\MicType\settings.json`
- Credential Manager API key storage:
  - `MicType/openai_api_key`
  - `MicType/deepseek_api_key`
- History in `%APPDATA%\MicType\history.json`

The local ASR engine is still a placeholder. Per the technical plan, M0 must be completed on a real Windows 11 machine before wiring sherpa-onnx / whisper.cpp / any Qwen3-ASR Windows runtime.

## Build

On Windows 11 with .NET 8 SDK:

```powershell
dotnet restore .\src\MicType.Windows\MicType.Windows.csproj
dotnet build .\src\MicType.Windows\MicType.Windows.csproj -c Debug
dotnet run --project .\src\MicType.Windows\MicType.Windows.csproj
```

Release publish:

```powershell
dotnet publish .\src\MicType.Windows\MicType.Windows.csproj -c Release -r win-x64 --self-contained true -o .\artifacts\MicType-win-x64
```

## M0 Stop Point

Before replacing `PlaceholderSpeechEngine`, complete `docs/M0-验证报告.md`:

1. Verify whether Qwen3-ASR has a practical Windows runtime.
2. Benchmark sherpa-onnx + SenseVoice and whisper.cpp on the same test set.
3. Validate the low-level keyboard hook on real Windows apps and UAC/fullscreen boundaries.
4. Validate UIA selected-text reading in Word, Chrome, WeChat PC, and fallback behavior.

Do not ship a user-facing Windows build until M0 selects the ASR engine and the M1 dictation loop passes on real hardware.
