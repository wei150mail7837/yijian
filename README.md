# 译见 YiJian

macOS 原生（AppKit + Swift）实现的轻量翻译工具：**1.5 MB** 安装包，全离线，无遥测。

以 [TTime](https://github.com/inkTimeRecord/TTime) 的交互为蓝本的原生重写——不打包浏览器，不内嵌解释器，整包就是一个 240 KB 的 Swift 二进制加系统资源。

## 功能

- **输入翻译** — 双栏窗口，流式打字机输出，回车翻译 / Shift+回车换行
- **截图翻译** — 框选屏幕区域 → macOS Vision 离线 OCR → 自动回填翻译
- **截图 OCR** — 独立窗口：图片预览 + 识别框叠加 + 可编辑文本
- **划词翻译** — 模拟 Cmd+C 取词，剪贴板自动还原
- **129 种语言** — 可搜索的语言面板，自动检测翻译方向
- **全局快捷键** — 全部可自定义，实时按键捕获（含输入法保护）
- **翻译引擎** — 任意 OpenAI 兼容接口（本地 Ollama 开箱即用）

## 隐私

- OCR 由 macOS Vision 框架**进程内**完成，数据不出设备
- 翻译请求仅发往你自己配置的接口地址（本地 Ollama = 全离线闭环）
- 无遥测、无崩溃上报、无账户体系；日志不记录翻译内容原文

## 构建与运行

要求：macOS 13+，Xcode Command Line Tools（`swiftc`，无需完整 Xcode）。

```bash
git clone <本仓库>
cd ttime-native
./build.sh          # swiftc 直编 → 译见 YiJian.app
open 译见 YiJian.app
```

首次使用：托盘 → 设置 → 填写 Ollama 接口地址与模型名（如 `http://127.0.0.1:11434/v1/chat/completions` + 已拉取的模型）。

划词翻译需要辅助功能授权（系统设置 → 隐私与安全性 → 辅助功能）。

## 门禁

```bash
scripts/gate.sh     # 构建 + Vision OCR 行序断言 + 翻译非空断言
```

## 许可

[MIT](LICENSE) · 交互设计灵感来自 TTime，详见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)
