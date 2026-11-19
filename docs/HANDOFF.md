# TTime 产品线 Handoff（译见 YiJian 主力 + TTime Lite 归档）

> 更新：2026-11-19 09:20。覆盖**除图标应用任务外**的全部现状。新会话接手以本文为唯一入口。
> 范围说明：图标已定稿（`assets/icon_yijian.swift`）但**应用该图标这一步被用户明确搁置**，本文不含其执行细节，仅标注状态。

---

## 1. 产品线全景

| 产品 | 仓库 | 平台 | 当前角色 |
|---|---|---|---|
| **译见 YiJian**（原生） | `~/Zcode/ttime-native` → 公开仓 [wei150mail7837/yijian](https://github.com/wei150mail7837/yijian)（MIT） | macOS only | **日常主力**，运行中 |
| **TTime Lite**（Electron） | `~/Zcode/TTime-community` → 私仓 [wei150mail7837/ttime-lite](https://github.com/wei150mail7837/ttime-lite)（Apache 2.0+附加条款） | mac + win 双平台 | **归档待命**——源码/Release 完整，随时可重启用 |
| TTime 官方原版 0.9.15 | 曾装 `/Applications/TTime.app`，**用户已自行卸载** | — | 已退场 |

两版共同点：全离线（OCR + 翻译均本地/用户自配接口）、无遥测、日志不落翻译原文、渠道与云依赖全部裁剪、翻译走用户自配 OpenAI 兼容接口（Ollama 开箱即用）。

**背景一句话**：官方 TTime 0.9.3 起闭源 → 以公开的 0.9.2 源码（Ruizhi-Deng/TTime Community）为基础做精简分叉 Lite → 后按"轻量+体验追平"做 AppKit 原生重写 YiJian → 用户实测两版均满意，YiJian 为日常主力，Lite 归档。

---

## 2. 译见 YiJian（原生版）现状

### 基本信息
- 装机：`/Applications/YiJian.app`（1.5M），配置域 `app.yijian.translate`，数据目录 `~/Library/Application Support/YiJian/`（日志在 `logs/`）
- 仓库：源码 + handoff + 图标定稿源码均已推送远端
- 引擎：mac Vision 进程内 OCR（无外置 helper）；翻译 = OllamaClient 真逐字 SSE 流式
- 隐私：零遥测；日志只记事件与长度，**不落翻译原文**（隐私审计后立规）

### 架构速览（~3000 行 Swift，零第三方依赖）
```
Sources/
  main.swift           入口 + --selftest-ocr / --selftest-translate CLI 门禁
  AppDelegate.swift    托盘（可隐藏）、快捷键注册、截图流程编排、单实例、自启（SMAppService）
  MainWindow.swift     双栏主窗（无边框毛玻璃悬浮）、打字机、IconButton/SidebarItem、toast 堆叠
  OCRWindow.swift      截图 OCR 窗（图预览+识别框+可编辑文本+图钉/设置/复制反馈）
  SelectionOverlay.swift 内置选区：逐屏冻结→框选→放大镜→松手即裁剪（坐标系论证注释在裁剪处，勿"修"Y 轴）
  VisionOCR.swift      Vision 进程内 OCR：行排序、段落合并
  OllamaClient.swift   OpenAI 兼容客户端：真逐字 SSE、语种检测（NLLanguageRecognizer）、自动方向
  LanguagePanel.swift  129 语种自绘面板（搜索+chips）
  LanguageList.swift   129 语种表（对齐 Lite aiLanguageList.ts）
  Services.swift       ScreenshotService（引擎分派）、SelectionReader（划词）、日志
  Settings.swift       设置窗（主题/位置/划词延迟/字号/自启/托盘隐藏/快捷键实时捕获）
  Config.swift         UserDefaults（键名=Lite 名；含旧域迁移）
assets/icon_yijian.swift  图标定稿源码（双圆交叠成眼，瞳点+睑弧）——**待应用，见 §2 遗留项 1**
```

### 当前已知状态与遗留
1. **图标应用任务——用户明确搁置**。定稿设计：双圆交叠成眼（vesica）+ 瞳点 + 睑弧，源码 `assets/icon_yijian.swift`。应用时：改写 `make_icon.swift` 用此设计出 icns，托盘 template 同步换眼形母题，重新构建装机。**非本期任务。**
2. 多显示器截图选区：代码支持逐屏冻结，**未实测**。
3. 错误呈现与 Lite 仍有细节差距（toast 已堆叠化，但样式细节未逐像素对齐）——可接受。
4. 单实例行为：重复 `open` 会经 DistributedNotification 转发 reopen 到在跑实例。

### 运维 runbook
```bash
# 构建（Node16 不需要——原生版纯 swiftc）
cd ~/Zcode/ttime-native && ./build.sh
# 门禁（OCR 行序断言 + 翻译非空断言；需 Ollama 运行）
./scripts/gate.sh
# 装机（先逐 PID 杀旧实例——单实例锁场景勿用 pkill -f；勿用 pkill -f 直接 open）
for p in $(pgrep -f YiJian); do kill $p; done; sleep 1
cp -R YiJian.app /Applications/ && xattr -cr /Applications/YiJian.app
open /Applications/YiJian.app
# 启动门禁
tail ~/Library/"Application Support"/YiJian/logs/$(date +%Y-%m-%d).log   # 零 error
```

---

## 3. TTime Lite（Electron 归档版）现状

- 仓库 `~/Zcode/TTime-community`，**lite 分支**，远端私仓已同步
- Release [v1.0.1](https://github.com/wei150mail7837/ttime-lite/releases/tag/v1.0.1)：**双平台三资产**（win setup 107M + mac DMG 108M + mac zip 105M），公开可下载
- 本地源码目录已瘦身为 84M（删 node_modules/dist/out/模型缓存；`npm install` + `prepare:ocr` 可恢复构建能力）
- **Windows 构建链已由用户在真 Win 机器验证**（产物即 `TTime Lite-1.0.1-setup.exe`，NSIS 结构完整性已审计）；构建手册 `BUILD-Windows.md`
- mac 版 OCR 引擎注意：**lite 分支的 mac 构建走 PP-OCR 链（onnxruntime），不是 Vision**——Vision 是 YiJian 原生版独有的路线。Lite mac DMG 的 OCR 引擎表现即用户最初不满的那条 PP-OCR 链，如回用 Lite 需知晓
- 仓库 README 已重写为本 fork 发布口径（全离线定位/双平台差异/隐私声明），已随公开展示

### 重启用 runbook
```bash
cd ~/Zcode/TTime-community
export PATH=~/Zcode/node16/bin:$PATH        # 必须 Node 16（~/Zcode/node16）
npm install                                  # 恢复 node_modules（~794M）
npm run prepare:ocr                          # 下载 PP-OCR 模型到 ocr/（~26M）
npm run build:mac
# 产物 dist/；装机同上 xattr -cr 后 cp
```

---

## 4. 关键决策史（勿重新讨论）

| 决策 | 依据 |
|---|---|
| 官方 TTime 0.9.3+ 闭源，不再跟随官方 | releases 标签是假指针（全部指向 2023 同一老提交） |
| OCR 弃 PP-OCR 改 Vision（仅 YiJian） | 实测 PP-OCR 对清晰大字只检出 1 框置信 0.62；Vision 零模型、准确率满分、省 102M |
| Lite 双词典/历史/TTS 等裁剪 | 用户确认"实时字幕加历史多余"、功能冗余 |
| 翻译仅 OpenAI 兼容单源 | 全离线闭环（Ollama 本地）；不接传统云翻译 API |
| YiJian 图标定稿双圆成眼（vesica+瞳点） | 用户确认大方向；**应用动作搁置** |
| 两个 GitHub 仓库均公开 | 发版审计通过（无密钥/无个人信息/无上游代码复制） |

---

## 5. 事故教训档案（防复发）

1. **隐式引用误删**（Electron 时期三连：opencv.js / clipper-lib / TTimeInfo.ts）：删除前全量 grep require/import/Selector 链。
2. **设置键名断裂**（两轮盲测 3+1 处）：新增设置时先 grep 主窗读取键，写入用同一键。
3. **rsync --delete 跨平台合并**（2026-11-16）：单侧覆盖式同步误删 4 个 mac 特有文件。**合并前后必须 `git ls-tree` 双向比对**。
4. **装机实例过期**：构建/清理流程只更新仓库目录；**报障先核对装机版本 == HEAD**。
5. **pkill 漏杀**：单实例锁场景 `open` 会把请求转给旧实例；杀进程逐 PID `kill`。
6. **会话 shell ENOENT**：ZCode 会话偶发 `/bin/zsh ENOENT`（进程环境损坏），重启会话即愈；**报障先确认 shell 可用**。
7. **世界坐标假镜像**（终审误判 Y 轴）：Cocoa y 向下与 CGImage 左上原点一致；论证写在 SelectionOverlay 裁剪处注释，勿再"修"。

---

## 6. 隐私纪律（不可违反）

- 日志只记事件与长度，禁止记录用户翻译/OCR 原文（已全线脱敏）
- 禁止引入遥测/上传端点；OCR 全进程内
- 网络出口唯一合法点 = 用户配置的翻译接口地址

---

## 7. 交接检查清单

1. `cd ~/Zcode/ttime-native && git pull && ./scripts/gate.sh` — 门禁应全绿（需 Ollama 运行）
2. `open /Applications/YiJian.app` — 日常版本应在跑
3. 待办优先级：①用户实测反馈的体验问题 ②图标应用（用户拍板后）③多显示器选区实测
4. **不要**：引入第三方依赖、加遥测、回退已裁剪功能、把 Lite 的 PP-OCR 引擎带回 YiJian、提醒用户卸载软件
5. Lite 重启用 runbook 见 §3

---

## 8. 文件索引

| 路径 | 内容 |
|---|---|
| `~/Zcode/ttime-native/` | YiJian 源码仓（本 handoff 所在） |
| `~/Zcode/ttime-native/docs/HANDOFF.md` | 本文档 |
| `~/Zcode/ttime-native/docs/ttime-lite-build.md` | 旧 mac 构建手册（历史参考，部分已被 YiJian 架构取代） |
| `~/Zcode/TTime-community/` | Lite 源码仓（84M，归档待命） |
| `~/Zcode/TTime-community/BUILD-Windows.md` | Windows 构建手册（用户实测版） |
| `~/Zcode/TTime-community/docs/community-branch.md` | 上游 Community 分支说明 |
| `~/Zcode/node16/` | Node 16（Lite 构建专用） |
| GitHub | 公开 [yijian](https://github.com/wei150mail7837/yijian) · 私有 [ttime-lite](https://github.com/wei150mail7837/ttime-lite) |
