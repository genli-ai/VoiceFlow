# VoiceFlow 🎤 — Mac 语音输入法

在任何应用里，按一下快捷键开口说话，再按一下，一段干净、带标点、没有口头禅的文字就出现在光标处。参考 Typeless / 豆包语音输入的体验，为你的 Mac 量身定制。

## 工作原理

```
按下 右⌥ → 说话 → 再按 右⌥
   ↓
本地 Whisper 识别（离线，Metal 加速，录音不上传）
   ↓
GPT 润色（去掉"嗯、呃、那个"，加标点，修错别字）
   ↓
文字自动输入到当前光标处
```

## 安装（一次搞定）

双击 **`Install VoiceFlow.command`**，等它跑完即可。脚本会自动：

1. 检查/引导安装 Xcode 命令行工具（Apple 官方，首次约 5 分钟）
2. 下载预编译的 whisper.cpp 引擎（约 46MB）
3. 编译并打包 VoiceFlow.app
4. 下载语音识别模型（Apple Silicon 用 large-v3-turbo，约 547MB，只需一次）
5. 安装到「应用程序」并启动

> 如果双击提示无法运行：右键脚本 → 打开；或在终端执行
> `chmod +x "Install VoiceFlow.command"` 后再双击。

### 首次启动要授权两个权限

| 权限 | 用途 | 怎么开 |
|------|------|--------|
| 麦克风 | 录音 | 弹窗点「允许」 |
| 辅助功能 | 全局快捷键 + 自动输入文字 | 系统设置 → 隐私与安全性 → 辅助功能 → 打开 VoiceFlow |

### 填入你的 OpenAI Key

菜单栏 🎤 → 设置 → **AI 润色** → 粘贴 API Key →「保存 Key 到钥匙串」→「测试连接」。

Key 存在 macOS 钥匙串里，不落明文。不填 Key 也能用（输出未润色的原始识别文本）。

## 使用

- **轻点 右 Option (⌥)**：开始录音；**再点一下**：结束并输出文字
- **Esc**：录音中随时取消
- 屏幕底部有悬浮指示器：🔴 波形 = 正在听 → 识别中 → 润色中 → ✓ 已输入
- 菜单栏 🎤 图标：开始/停止、最近 10 条记录（点击复制）、AI 润色开关、设置

### 设置项一览

- **通用**：快捷键（右⌥/右⌘/右⌃）、触发方式（轻点切换 / 按住说话）、提示音、登录自启
- **识别**：语言（自动检测/中英日韩法德西）、速度优先解码、模型选择与下载、**专有词汇表**（人名、品牌、术语——识别和润色都会参考，强烈建议填）
- **AI 润色**：三档润色（仅识别/标准/深度重组）、**智能档位**（按当前应用自动选档：聊天→标准、文档→深度、代码→仅识别，默认关闭）、API Key、Base URL（支持任何 OpenAI 兼容中转）、模型名（默认 gpt-5.4-mini）、**自定义润色规则**（如"邮件场景用正式语气"）

## 隐私

- 录音和语音识别 **100% 在本机完成**，不联网
- 只有开启 AI 润色时，识别出的 **文本**（不是录音）会发给你自己配置的 API
- API Key 存放在 macOS 钥匙串

## 常见问题

**按快捷键没反应？** 检查 系统设置 → 隐私与安全性 → 辅助功能 里 VoiceFlow 是否打开；改过 App 后需要先移除再重新添加。

**识别是繁体/不准？** 设置 → 识别 里确认语言为"中文"；把常用词加进专有词汇表；Apple Silicon 建议用 large-v3-turbo 模型。

**润色失败？** 设置 → AI 润色 → 测试连接，检查 Key / Base URL / 模型名 / 网络（直连 api.openai.com 可能需要代理，或改用中转 Base URL）。

**文字没有输入到目标应用？** 处理期间切走窗口的话，VoiceFlow 会自动把目标应用拉回前台再粘贴；如果还是丢了，菜单栏 → 最近记录 里点一下即可复制找回。个别应用（如密码框）禁止粘贴；其余情况基本都是辅助功能权限没开。小技巧：设置 → 通用 关闭「恢复剪贴板」，输入的文字会一直留在剪贴板里，随时 ⌘V。

**模型下载慢？** 默认走 hf-mirror.com 国内镜像；也可手动下载模型文件放进 `~/Library/Application Support/VoiceFlow/models/`。

**编译时报 `Invalid manifest` / `PackageDescription` 链接错误？** 你的 Xcode 命令行工具安装损坏了（多见于系统升级后），双击 `scripts/Fix Build Tools.command` 重装即可。

**重新安装后快捷键失效？** 重新编译后签名会变化，去 系统设置 → 辅助功能 把 VoiceFlow 删除后重新添加。

## 卸载

双击 `Uninstall VoiceFlow.command`。

## 技术栈

原生 Swift（菜单栏 App，SwiftUI 设置界面）· whisper.cpp v1.8.4 官方预编译 XCFramework（Metal GPU 加速）· OpenAI Chat Completions 润色 · 无任何第三方运行时依赖。

目录结构：

```
VoiceFlow/
├── Package.swift              # Swift Package 定义（链接 whisper.xcframework）
├── Sources/VoiceFlow/         # 全部源码（约 1800 行）
│   ├── main.swift             # 入口
│   ├── AppDelegate.swift      # 菜单栏与组装
│   ├── DictationController.swift  # 录音→识别→润色→输入 主流程
│   ├── HotkeyManager.swift    # 全局快捷键（轻点/按住，Esc 取消）
│   ├── AudioRecorder.swift    # 16kHz 录音与音量监测
│   ├── WhisperService.swift   # 本地 whisper.cpp 推理
│   ├── PolishService.swift    # OpenAI 润色
│   ├── TextInserter.swift     # 剪贴板 + ⌘V 注入，自动恢复剪贴板
│   ├── Overlay.swift          # 底部悬浮指示器
│   ├── SettingsView.swift     # 设置窗口
│   ├── ModelDownloader.swift  # 应用内模型下载（hf-mirror 优先）
│   └── …
├── Resources/                 # Info.plist、图标
└── Frameworks/                # whisper.xcframework（安装脚本下载，不入库）

scripts/                       # 修复工具等辅助脚本
Install VoiceFlow.command      # 一键安装
Uninstall VoiceFlow.command    # 一键卸载
```

## 致谢与许可

本项目从需求分析、架构设计、全部代码到调试排错，均通过与 [Claude](https://claude.com)（Cowork 模式）对话完成。基于 [whisper.cpp](https://github.com/ggml-org/whisper.cpp) 的官方预编译框架。MIT License。
