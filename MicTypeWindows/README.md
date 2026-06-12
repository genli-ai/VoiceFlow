# MicType for Windows

This folder is the Windows implementation scaffold for MicType. It is intentionally isolated from the macOS Swift package so the two build systems do not contaminate each other.

## System Requirements / 系统要求

- **Windows 10 22H2 or Windows 11, 64-bit (x64)** — matches the .NET 8 support matrix; verified on a real Windows 10 22H2 (19045) machine. Windows on ARM is untested and unsupported for now.
- **RAM:** 8 GB+ recommended (the SenseVoice model takes a few hundred MB when loaded).
- **Disk:** ~1 GB (app ~190 MB + speech model ~250 MB).
- **Mic + network:** microphone required; network needed once to download the speech model (~250 MB) and whenever AI polish / voice commands call your GPT/DeepSeek API. Plain dictation runs fully offline after the model is installed.
- **Known dependency:** onnxruntime requires the Microsoft **VC++ 2015-2022 redistributable** — present on almost every machine; on a pristine system a "missing DLL" error means installing it once.

中文：Windows 10 22H2 / Windows 11（64 位 x64）；建议内存 8GB+；磁盘约 1GB（含 250MB 识别模型）；需要麦克风，首次联网下载模型，本地听写下线后完全离线；AI 润色/指令需联网 + API Key。极干净的系统若报缺 DLL，安装一次微软 VC++ 2015-2022 运行库即可。

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
- Rolling debug logs in `%APPDATA%\MicType\logs`
- Credential Manager API key storage:
  - `MicType/openai_api_key`
  - `MicType/deepseek_api_key`
- History in `%APPDATA%\MicType\history.json`

The first run needs the SenseVoice model. Open Settings → Recognition and download the model before using dictation. MicType records 16 kHz mono audio locally, sends it to the local SenseVoice recognizer, then optionally sends text only to your configured GPT / DeepSeek API for polishing or commands.

Use the tray menu item **Open Logs Folder** when remote debugging. Logs include startup environment, display DPI/working-area data, hotkey events, recording metrics, model load/transcription timings, overlay coordinates, and paste outcomes. They do not include API keys, audio, selected text, or transcript contents.

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
