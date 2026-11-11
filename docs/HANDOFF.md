# 译见 YiJian 全量 Handoff（交接文档）

> 更新：2026-11-11。任何 agent / 人在任何时间点接手本项目，以本文为唯一入口。
> 配套记忆：`~/.zcode/cli/memories/projects/zcode-93268972e54ca965/memory/ttimenative-project.md`

---

## 1. 项目是什么

**译见 YiJian**：macOS 原生（纯 AppKit + Swift，`swiftc` 直编）的轻量截图翻译工具。

- **安装包 1.5 MB**（对照：Electron 版 206M），单进程常驻内存 ~110 MB（对照：Electron 五进程 ~500 MB）
- 全离线：OCR 用 macOS Vision（进程内，数据不出设备）；翻译走用户自配的 OpenAI 兼容接口（本地 Ollama 开箱即用）
- 无遥测、无账户、日志不落用户内容原文（隐私纪律见 §6）
- 交互蓝本：TTime（Electron 应用）。**本仓库全部 Swift 代码为原创，未复制其任何源码**，详见 `THIRD-PARTY-NOTICES.md`

### 功能面（与 Lite 逐条对齐过，两轮盲测）

输入翻译（双栏、逐字流式、回车/Shift+回车）、截图翻译、截图 OCR（图片预览+识别框叠加+可编辑文本）、
划词翻译（Cmd+C 模拟+剪贴板还原）、129 语种可搜索面板、全局快捷键（全可自定义、实时捕获）、
托盘（可隐藏）、内置截图选区引擎（冻结整屏+放大镜 2.5x）、开机自启、字号/主题/显示位置等设置全集。

### 明确裁剪（不算差距，勿"补齐"）

翻译历史、词典、网络代理设置、AI 提示词自定义页、配置文件页、关于页、托盘外链、多通道并列卡（单源产品）。
来源：两轮逐条盲测（2026-11-10/11）+ 用户确认。相关报告见 §7 工作流记录。

---

## 2. 仓库与版本

| 项 | 值 |
|---|---|
| 仓库 | `~/Zcode/ttime-native`（git，main 分支），远端 `github.com/wei150mail7837/yijian`（**公开**） |
| 发布 | v1.0.0 tag + [Release](https://github.com/wei150mail7837/yijian/releases/tag/v1.0.0)（DMG 1.3M + zip 1.0M，arm64） |
| 装机 | `/Applications/YiJian.app`，配置域 `app.yijian.translate`（UserDefaults） |
| 数据目录 | `~/Library/Application Support/YiJian/`（日志在 `logs/`） |

**历史沿革**（做决策前先读）：
官方 TTime 0.9.3 起闭源 → 基于 TTime Community（Ruizhi-Deng/TTime）源码做了 Electron 精简版
"译见 Lite"（`~/Zcode/TTime-community`，已发布私仓，两版并存）→ 用户要求更轻的方案 →
**AppKit 原生重写**为本项目。两版盲测对比：Lite 行为成熟但五进程 500MB；原生 1.5M/单进程 109MB，
两轮"手感追平"施工后用户满意度可接受，现进入日常使用观察期。

---

## 3. 架构（3058 行 Swift，无第三方依赖）

```
Sources/
  main.swift            入口 + CLI 自检模式（--selftest-ocr / --selftest-translate，门禁用）
  AppDelegate.swift     托盘（可隐藏）、快捷键注册、截图流程编排、单实例、开机自启（SMAppService）
  MainWindow.swift      双栏主窗（无边框透明悬浮+毛玻璃）、IconButton/SidebarItem 组件、
                        toast 堆叠（ToastCardView）、打字机（60Hz Timer+积压加速）、布局重排
  OCRWindow.swift       截图 OCR 窗（图预览+识别框+可编辑文本+图钉/设置）
  SelectionOverlay.swift 内置截图选区：screencapture -x 逐屏冻结→冻结图上框选→放大镜(2.5x 从冻结图采样)
                        →松手即裁剪（坐标系论证见 :170 注释——Cocoa y 向下与 CGImage 左上原点一致，勿"修"）
  Services.swift        ScreenshotService（引擎分派+前置隐藏+0.15s 延时）、SelectionReader（划词）、日志
  VisionOCR.swift       Vision OCR（进程内）：NLLanguageRecognizer 语种检测、行排序、段落合并
  OllamaClient.swift    OpenAI 兼容客户端（真·逐字 SSE 流式）+ 语种检测/自动方向 + 129 语种表解析
  LanguagePanel.swift   语种面板（搜索+chips 网格，手排 frame 无自动布局）
  LanguageList.swift    129 语种表（对齐 Lite aiLanguageList.ts）
  Config.swift          UserDefaults 配置（键名=Lite 名；含旧域迁移逻辑）
build.sh               swiftc 直编 + Info.plist + ad-hoc 签名（无 Xcode 依赖）
scripts/gate.sh        门禁：构建 + OCR 行序断言 + 翻译非空断言
assets/                图标源（make_icon.swift：青蓝渐变+「译」字气泡）与 icns/PNG
docs/HANDOFF.md        本文档
```

### 关键设计事实（改代码前必读）

1. **翻译是真·逐字流式**：`OllamaClient` 用 `URLSession.bytes` 逐 chunk 回调，`MainWindow` 打字机
   以 60Hz Timer 消费（积压越多吐越快）。视口固定+滚动跟随（§5 重构后），勿改回"按内容高度撑窗口"。
2. **内置选区架构 = Lite 同款"冻结整屏"**：`screencapture -x -D n` 逐屏冻结 → 透明全屏窗铺冻结图 →
   框选 → 放大镜从冻结图采样 → 松手即从冻结图裁剪（无二次截图）。坐标系：Cocoa 全局 y 向下、
   `screen.frame.origin.y` = 屏顶的全局 y，`local.y` 就是"距屏顶距离"，与 CGImage 左上原点行方向
   **一致，无需翻转**——终审曾误判为镜像 bug，论证注释在 SelectionOverlay.swift 裁剪与放大镜两处。
3. **配置键名 = Lite 键名**（hideTranslateInput 等）。历史教训：设置写入键与主窗读取键不一致导致
   开关完全失效（两轮盲测抓出 3 处）。**新增设置时：先 grep 主窗读取键，再用同一个键写入。**
4. **UserDefaults 域迁移**：bundle id 曾从 `com.isa.ttimenative` 改为 `app.yijian.translate`，
   `Config.migrated` 会在首次访问时把旧域的 ollamaURL/model/语种拷贝过来。此迁移逻辑保留一版后可删。
5. **Swift 闭包陷阱**：`[weak self]` 后再 `guard let self` 则闭包内 self 已非可选，再写 `self?.x`
   会编译错误；写异步回调链时注意强引用循环（已知用法见 autoHeight 动画完成回调）。

---

## 4. 运维手册（runbook）

### 构建
```bash
cd ~/Zcode/ttime-native && ./build.sh
```
要求：Xcode CLT（swiftc）。**无需完整 Xcode、无第三方依赖**（曾验证 Node16/SwiftPM 等均不涉及——纯 swiftc）。

### 门禁（每次改码后必跑）
```bash
./scripts/gate.sh     # 退出码非 0 即失败：内含构建 + 生成多行中英测试图 + OCR 行序/内容断言 + 翻译非空断言
```
### 装机
```bash
for p in $(pgrep -f YiJian); do kill $p; done; sleep 1          # 旧进程逐 PID 杀（勿用 pkill -f，单实例锁会捣乱）
cp -R YiJian.app /Applications/ && xattr -cr /Applications/YiJian.app
open /Applications/YiJian.app
tail ~/Library/"Application Support"/YiJian/logs/$(date +%Y-%m-%d).log   # 启动门禁：零 error
```

### 发版
```bash
ditto -c -k --keepParent YiJian.app dist/YiJian-<ver>-arm64.zip
hdiutil create -volname "YiJian <ver>" -srcfolder YiJian.app -ov -format UDZO dist/YiJian-<ver>-arm64.dmg
gh release create v<ver> --repo wei150mail7837/yijian --title "译见 YiJian v<ver>" --notes-file <notes>
gh release upload v<ver> dist/*.dmg dist/*.zip --clobber --repo wei150mail7837/yijian
```
注意：world.run/相对路径环境下用**绝对路径**（两次 ENOENT 事故教训）；zsh 对含 `=`/`-` 开头的
文件名参数可能报 no matches found，分两条命令跑（先 create 后 upload）可绕开。

### 回滚
所有改动均 git 提交；`git checkout -- .` 可整体还原工作区。发布包在 GitHub Release 挂着，随时可回退。

---

## 5. 当前已知状态与遗留项

### 已修复（2026-11-11，全部提交）
- P0×4：设置键名断裂×1（hideTranslateInput/LanguageBar）、侧栏高亮 item.tag、录制 Esc 被吞、结果区无滚动
- Y 轴镜像误判：论证+注释（勿再"修"）
- 交互反馈：IconButton 三态（悬停/按压/点击闪烁）、侧栏 SidebarItem 自绘（选中态强受控）、toast 堆叠
- FROM_TOP 公式、129 语种面板、卡头 logo、折叠空守卫、AI 提示词页保留（内置只读）

### 待观察 / 遗留（按优先级）
1. **用户观察期**：用户正在单独日常使用原生版（Lite 已退出未卸载）。验收结论决定 Lite 去留。
2. `/Applications/TTime.app`（官方原版 0.9.15）：**用户明确表示卸载类操作自己做，勿提醒。**
3. `Sources/HotKeys.swift` 已在死代码清理中删除源码，但**审计批次记录里列为批次 1 第 1 项**——若见残留在报告里属历史记录，不是现状。
4. **旧域迁移逻辑**（Config.migrated）：保留一个版本周期后可删（新装用户无旧域）。
5. 多显示器截图选区：代码支持（逐屏冻结），**未实测**。
6. 设置页数字非法输入无 toast 提示（超范围静默按边界收敛）——低优先。

### 事故教训档案（防复发）
- **设置键名断裂**（两轮盲测共 3+1 处）：写键前先 grep 读键。
- **隐式引用误删**（opencv.js/clipper-lib/TTimeInfo.ts 三连，Electron 版时期）：删除前全量 grep require/import/Selector 链。
- **装机实例过期**：构建/清理流程只更新仓库目录，`/Applications` 需手动重装；**每次报障先核对装机版本 == HEAD**。
- **pkill 漏杀**：单实例锁场景 `open` 会把请求转给旧实例；杀进程用 `kill <pid>` 逐个来。
- **world.run 相对路径**：动态工作流的 cwd 可能是子目录，一律用绝对路径。

---

## 6. 隐私纪律（不可违反）

- 日志只记**事件与长度**，禁止记录用户翻译/OCR 内容原文（2026-11-11 隐私审计后立规，logExtend 参数打码）。
- OCR 进程内 Vision 调用，禁止引入任何上传/遥测端点。
- 新增网络路径必须过用户（当前唯一合法出网点 = 用户配置的翻译接口地址）。

---

## 7. 工作流与审计记录索引

| 日期 | 事项 | 记录 |
|---|---|---|
| 11-10/11 | 两轮盲测 + 体验施工（T2/T15/键名断裂等全清单） | GitHub yijian 仓库提交历史 + 《体验对照报告（第二轮）》（工作流 artifact） |
| 11-11 | 隐私审计（日志脱敏、零遥测确认） | 提交 "logging: 截图/OCR 失败路径记录具体错误信息" |
| 11-11 | 死代码清理（19 条审计、3 批执行、复验无回归） | 《清理与盲测报告》（工作流 artifact）+ 复验 findings |
| 11-11 | 升级建议（P0/P1/P2 分级，**暂不动手部分已由"全部"指令消化**） | 《盲测与升级建议报告》（工作流 artifact） |

动态工作流运行记录：`~/Zcode/ttime-native/.zcode/workflow-runs/*.mjs`（含两次路径事故与修复）。
评估类模型会话记录：`~/.zcode/cli/rollout/model-io-sess_dwf-*.jsonl`。

---

## 8. 交接检查清单（新接手者依次执行）

1. `cd ~/Zcode/ttime-native && git pull && git log --oneline -5` — 确认在最新提交
2. 读 §3 架构与 §5 遗留项
3. `./scripts/gate.sh` — 门禁应全绿
4. `open /Applications/YiJian.app` — 应用应已在运行（或重新装机，见 §4）
5. 需要改功能：Read+Edit 源文件 → `./build.sh` → `./scripts/gate.sh` → `git commit` → 重新装机
6. **不要**：引入第三方依赖、加遥测、"修复"选区坐标系、补回已裁剪功能、提醒用户卸载软件
