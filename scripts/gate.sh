#!/bin/zsh
# 门禁：OCR 行序/内容 + 翻译非空；任一失败退出非零
# 用法：scripts/gate.sh [模型名] [接口地址]
set -u
cd "$(dirname "$0")/.."
BIN="TTimeNative.app/Contents/MacOS/TTimeNative"
[[ -x "$BIN" ]] || { echo "GATE_FAIL: 缺 $BIN，先 ./build.sh"; exit 2; }
TMP=$(mktemp -d); IMG="$TMP/gate.png"
TLINES=("Hello World Line One" "第二行中文测试文本" "Third line 第三行混排" "最后一行 Final")

cat > "$TMP/gen.swift" <<'S'
import AppKit
let out = CommandLine.arguments[1]
let lines = Array(CommandLine.arguments.dropFirst(2))
let w = 900, h = 80 * lines.count + 40
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]
for (i, l) in lines.enumerated() {
  (l as NSString).draw(at: NSPoint(x: 30, y: CGFloat(h - 70 - i * 80)), withAttributes: attrs)
}
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
S
swift "$TMP/gen.swift" "$IMG" "${TLINES[@]}" || { echo "GATE_FAIL: 生成测试图失败"; exit 3; }

OUT=$("$BIN" --selftest-ocr "$IMG" 2>&1); RC=$?
echo "$OUT"
[[ $RC -eq 0 ]] || { echo "GATE_FAIL: OCR 退出码 $RC"; exit 4; }
TEXT="${OUT#*OCR_RESULT:}"
python3 -I - "$TEXT" "${TLINES[@]}" <<'P' || { echo "GATE_FAIL: OCR 行序/内容不符"; exit 5; }
import sys
got=[l.replace(" ","") for l in sys.argv[1].splitlines() if l.strip()]
exp=[l.replace(" ","") for l in sys.argv[2:]]
print("got:",got); print("exp:",exp)
sys.exit(0 if got==exp else 1)
P
echo "GATE_OK: OCR"

[[ -n "${1:-}" ]] && defaults write com.isa.ttimenative model -string "$1"
[[ -n "${2:-}" ]] && defaults write com.isa.ttimenative ollamaURL -string "$2"
OUT=$("$BIN" --selftest-translate "Hello, world" 2>&1); RC=$?
echo "$OUT"
[[ $RC -eq 0 && "$OUT" == *TRANSLATE_RESULT:?* ]] || { echo "GATE_FAIL: 翻译失败或为空"; exit 6; }
echo "GATE_OK: Ollama 通道翻译"

# 通道二：Web 翻译（免配置，MyMemory）——先记原值，测完还原。
# 故意不清空/不写 model：验证 Config.model 的 "web 通道未填模型 → mymemory" 兜底
SAVED_CH=$(defaults read com.isa.ttimenative translateChannel 2>/dev/null || true)
defaults write com.isa.ttimenative translateChannel -string web
OUT=$("$BIN" --selftest-translate "Hello, world" 2>&1); RC=$?
echo "$OUT"
if [[ -n "$SAVED_CH" ]]; then defaults write com.isa.ttimenative translateChannel -string "$SAVED_CH"; else defaults delete com.isa.ttimenative translateChannel 2>/dev/null; fi
[[ $RC -eq 0 && "$OUT" == *TRANSLATE_RESULT:?* ]] || { echo "GATE_FAIL: Web 通道翻译失败或为空"; exit 7; }
echo "GATE_OK: Web 通道翻译"
echo "GATE_OK: 全部通过"
rm -rf "$TMP"
