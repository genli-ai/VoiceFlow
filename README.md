# VoiceFlow 🎤 — Mac 语音输入法

在任何应用里，按一下快捷键开口说话，再按一下，一段干净、带标点、没有口头禅的文字就出现在光标处。参考 Typeless / 豆包语音输入的体验，为你的 Mac 量身定制。

## 工作原理

```
按下 右⌥ → 说话 → 再按 右⌥
   ↓
本地 Qwen3-ASR 识别（离线，MLX/Metal 加速，录音不上传）
   ↓
按档位可选 GPT 润色（去口头禅、加标点、修错别字）
   ↓
文字自动输入到当前光标处
```

## V2：Qwen3-ASR 引擎

V2 使用 **Qwen3-ASR** 作为默认且唯一的语音识别引擎：约 30 种语言 + 22 种中文方言，中文与中英混说表现更强，专有词汇表会作为热词直接送入模型。

要求：**Apple Silicon + macOS 15+ + 完整 Xcode**。MLX 的 Metal 着色器需要 Xcode 编译；Intel/老系统请使用 main 分支的 V1。

安装三步：

1. 双击 `scripts/Generate Qwen Tokenizer.command`（一次性生成 tokenizer 资源）
2. 双击 `Install VoiceFlow V2.command`（首次编译 5-15 分钟，会自动检查 Metal 工具链）
3. 打开 App → 设置 → 识别 → 下载模型（约 860 MB，国内镜像加速）

## 模型更新

设置 → 识别 → **检查更新** 会读取远端模型仓库版本，并和本地下载时记录的版本对比。发现新版本后，点 **重新下载 / 更新** 即可换到新版模型。

有两类“词汇”需要区分：

- **专有词汇表**：你在设置里填的人名、品牌、术语等热词，保存在本机；改完后下次识别立刻生效，不需要等模型更新。
- **模型 tokenizer/vocab**：Qwen 模型自带的分词词表，随上游模型仓库更新；需要重新运行 `scripts/Generate Qwen Tokenizer.command`，再重新安装/发版 App。

## 预编译包

如果已经安装好了 `/Applications/VoiceFlow.app`，可以打一个给别人直接使用的 arm64 包：

```bash
ditto -c -k --keepParent /Applications/VoiceFlow.app VoiceFlow-v2.0-arm64.zip
```

把 `VoiceFlow-v2.0-arm64.zip` 上传到 GitHub Releases 后，用户就可以跳过 Xcode 编译流程。

## 首次启动授权

| 权限 | 用途 | 怎么开 |
|------|------|--------|
| 麦克风 | 录音 | 弹窗点「允许」 |
| 辅助功能 | 全局快捷键 + 自动输入文字 | 系统设置 → 隐私与安全性 → 辅助功能 → 打开 VoiceFlow |

如果系统设置里显示已开启但快捷键仍失效，请在辅助功能列表中删除 VoiceFlow，再重新添加 `/Applications/VoiceFlow.app`。

## AI 润色

菜单栏 🎤 → 设置 → **AI 润色** → 粘贴 API Key →「保存 Key 到钥匙串」→「测试连接」。

Key 存在 macOS 钥匙串里，不落明文。不填 Key 也能用：VoiceFlow 会输出未润色的原始识别文本。

润色档位：

- **仅识别**：完全不联网
- **标准润色**：去口头禅、加标点、修正明显识别错误
- **深度润色**：重组长段表达，合并重复内容，必要时分段列点
- **智能档位**：按当前应用自动选择；聊天 → 标准，文档/邮件 → 深度，代码/终端 → 仅识别

## 使用

- **轻点 右 Option (⌥)**：开始录音；**再点一下**：结束并输出文字
- **Esc**：录音中随时取消
- 屏幕底部有悬浮指示器：录音 → 识别中 → 润色中 → 已输入
- 菜单栏 🎤 图标：开始/停止、最近 10 条记录（点击复制）、润色档位、设置

## 隐私

- 录音和语音识别 **100% 在本机完成**，不上传
- 只有开启 AI 润色时，识别出的 **文本**（不是录音）会发给你配置的 API
- API Key 存放在 macOS 钥匙串

## 常见问题

**按快捷键没反应？** 检查 系统设置 → 隐私与安全性 → 辅助功能 里 VoiceFlow 是否打开；重新编译或覆盖安装后，通常需要删除旧授权再重新添加。

**识别专有名词不准？** 把常用人名、品牌、产品、术语写进 设置 → 识别 → 专有词汇表。它会同时参与 Qwen 热词提示和 AI 润色纠错。

**模型下载慢？** 默认先走 hf-mirror.com，失败后回退 huggingface.co；已下载成功的文件会保留，重试可续传。

**润色失败？** 设置 → AI 润色 → 测试连接，检查 Key / Base URL / 模型名 / 网络。不影响本地识别，失败时会自动输出识别原文。

**文字没有输入到目标应用？** 处理期间切走窗口的话，VoiceFlow 会自动把目标应用拉回前台再粘贴；如果还是丢了，菜单栏 → 最近记录 里点一下即可复制找回。个别应用（如密码框）禁止粘贴。

**编译时报 `Invalid manifest` / `PackageDescription` 链接错误？** Xcode 命令行工具可能损坏了（多见于系统升级后），双击 `scripts/Fix Build Tools.command` 重装即可。

## 卸载

双击 `Uninstall VoiceFlow.command`。

## 技术栈

原生 Swift（菜单栏 App，SwiftUI 设置界面）· Qwen3-ASR / MLXASR · OpenAI 兼容 Chat Completions 润色 · macOS 钥匙串。

目录结构：

```
VoiceFlow/
├── Package.swift              # Swift Package 定义（MLXASR）
├── Sources/VoiceFlow/         # 全部源码
│   ├── main.swift             # 入口
│   ├── AppDelegate.swift      # 菜单栏与组装
│   ├── DictationController.swift  # 录音→识别→润色→输入 主流程
│   ├── HotkeyManager.swift    # 全局快捷键（轻点/按住，Esc 取消）
│   ├── AudioRecorder.swift    # 16kHz 录音与音量监测
│   ├── QwenEngine.swift       # 本地 Qwen3-ASR 推理
│   ├── QwenModelDownloader.swift  # 应用内模型下载与更新检查
│   ├── PolishService.swift    # AI 润色
│   ├── TextInserter.swift     # 剪贴板 + ⌘V 注入，自动恢复剪贴板
│   ├── Overlay.swift          # 底部悬浮指示器
│   └── SettingsView.swift     # 设置窗口
├── Resources/                 # Info.plist、图标、QwenTokenizer
└── Package.resolved           # 锁定依赖版本

scripts/                       # 修复工具、tokenizer 生成工具
Install VoiceFlow V2.command   # 一键安装
Uninstall VoiceFlow.command    # 一键卸载
```

## 致谢与许可

本项目从需求分析、架构设计、全部代码到调试排错，均通过 AI 协作完成。MIT License。
