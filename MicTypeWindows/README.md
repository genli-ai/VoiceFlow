# MicType for Windows

This folder is the Windows implementation scaffold for MicType. It is intentionally isolated from the macOS Swift package so the two build systems do not contaminate each other.

## Current State

- .NET 8 + WPF tray app scaffold
- Global low-level keyboard hook: tap = dictation toggle, hold = command mode, Esc cancels and is swallowed while recording
- NAudio 16 kHz mono recording pipeline
- Clipboard + Ctrl+V insertion with clipboard restore
- UI Automation selected-text read with Ctrl+C fallback
- OpenAI-compatible LLM client, polish prompt, command prompts, reply trigger routing
- Local ASR via sherpa-onnx + SenseVoice
- JSON settings in `%APPDATA%\MicType\settings.json`
- SenseVoice model files in `%APPDATA%\MicType\models\sensevoice`
- Credential Manager API key storage:
  - `MicType/openai_api_key`
  - `MicType/deepseek_api_key`
- History in `%APPDATA%\MicType\history.json`

The first run needs the SenseVoice model. Open Settings → Recognition and download the model before using dictation. MicType records 16 kHz mono audio locally, sends it to the local SenseVoice recognizer, then optionally sends text only to your configured GPT / DeepSeek API for polishing or commands.

## Build

On Windows 11 with .NET 8 SDK:

```powershell
dotnet restore .\src\MicType.Windows\MicType.Windows.csproj
dotnet build .\src\MicType.Windows\MicType.Windows.csproj -c Debug
dotnet run --project .\src\MicType.Windows\MicType.Windows.csproj
```

Run unit tests:

```powershell
dotnet test .\tests\MicTypeWindows.Tests.sln -c Debug
```

Run the real SenseVoice integration test. This downloads the official k2-fsa SenseVoice archive if the model cache is empty:

```powershell
$env:MICTYPE_RUN_SENSEVOICE_INTEGRATION = "1"
$env:MICTYPE_SENSEVOICE_MODEL_DIR = "$PWD\.model-cache\sensevoice"
dotnet test .\tests\MicTypeWindows.Tests.sln -c Debug --filter FullyQualifiedName~SenseVoiceIntegrationTests
```

Release publish:

```powershell
dotnet publish .\src\MicType.Windows\MicType.Windows.csproj -c Release -r win-x64 --self-contained true -o .\artifacts\MicType-win-x64
```

## M1 ASR Notes

- Default ASR engine: `org.k2fsa.sherpa.onnx` + `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`.
- Model config: `language=auto`, inverse text normalization enabled, CPU provider.
- SenseVoice does not use the custom vocabulary list as a native hotword file; MicType keeps the existing `wrong=right` post-processing path for exact replacements.
- CI includes a Windows-only integration job that downloads the official model archive and transcribes the bundled `test_wavs\zh.wav`.
