import NaturalLanguage
import Foundation

/// 语言定义（对齐 Electron languageUtil：AUTO + 常用语种）
struct TLanguage {
    let code: String   // auto / zh / en / ja / ko / ru / fr / de / es
    let name: String   // 界面显示名
    let prompt: String // 提示词中的语言名

    static let all: [TLanguage] = [
        TLanguage(code: "auto", name: "自动识别", prompt: "auto"),
        TLanguage(code: "zh", name: "中文", prompt: "简体中文"),
        TLanguage(code: "en", name: "英语", prompt: "English"),
        TLanguage(code: "ja", name: "日语", prompt: "日本語"),
        TLanguage(code: "ko", name: "韩语", prompt: "한국어"),
        TLanguage(code: "ru", name: "俄语", prompt: "Русский"),
        TLanguage(code: "fr", name: "法语", prompt: "Français"),
        TLanguage(code: "de", name: "德语", prompt: "Deutsch"),
        TLanguage(code: "es", name: "西班牙语", prompt: "Español")
    ]
    static func find(_ key: String) -> TLanguage {
        // 任意解析：内部 code / 提示词语种名（129 语种表 LanguageList 的 type）/ 界面名都可作为 key；
        // 表外语种动态合成（prompt 直接用该语种名，Ollama 模型可理解自然语言语种名）
        if let m = all.first(where: { $0.code == key || $0.prompt == key || $0.name == key }) { return m }
        return TLanguage(code: key, name: key, prompt: key)
    }
}

/// 内置提示词模板（对齐 aiPrompts.ts：translate/polish/summarize/analyze/code，system+user 双消息）
struct AiPrompt {
    let id: String
    let system: String
    let user: String

    static let builtins: [AiPrompt] = [
        AiPrompt(id: "translate",
                 system: "You are a professional translation engine. Translate the text from {{source}} into {{target}}. Output ONLY the translation, no explanations, no quotes. Keep the original formatting.",
                 user: "{{text}}"),
        AiPrompt(id: "polish",
                 system: "You are a writing assistant. Polish the text in {{target}} to be fluent and natural. Output only the polished text.",
                 user: "{{text}}"),
        AiPrompt(id: "summarize",
                 system: "Summarize the following text concisely in {{target}}. Output only the summary.",
                 user: "{{text}}"),
        AiPrompt(id: "analyze",
                 system: "Analyze the grammar, vocabulary and meaning of the following {{source}} text. Answer in {{target}}.",
                 user: "{{text}}"),
        AiPrompt(id: "code",
                 system: "Explain the following code in {{target}}, concisely.",
                 user: "{{text}}")
    ]

    static func find(_ id: String) -> AiPrompt? { builtins.first { $0.id == id } }
}

/// OpenAI 兼容接口客户端（URLSession.bytes 真流式，逐段回调）
final class OllamaClient {
    static let shared = OllamaClient()

    private var currentTask: Task<Void, Never>?
    var isBusy: Bool { currentTask != nil }

    // MARK: - 语言检测（逐条复刻 languageUtil.ts / LanguageEnum.ts）
    // languageUtil.ts:5-16 only = [eng, cmn, kor, rus, jpn]
    private static let onlyLanguages: [NLLanguage] = [.english, .simplifiedChinese, .korean, .russian, .japanese]

    /// franc(text,{minLength:1, only:[eng,cmn,kor,rus,jpn]}) 的替代：
    /// NLLanguageRecognizer 限定同五语种，返回 franc 语种码；und 返回 nil
    static func francGuess(_ text: String) -> String? {
        let r = NLLanguageRecognizer()
        r.languageConstraints = onlyLanguages
        r.processString(text)
        guard let l = r.dominantLanguage else { return nil }   // und
        switch l {
        case .english: return "eng"
        case .simplifiedChinese: return "cmn"
        case .korean: return "kor"
        case .russian: return "rus"
        case .japanese: return "jpn"
        default: return nil
        }
    }

    /// languageUtil.countChineseCharacters：同正则 /[\u4e00-\u9fa5]/g
    static func countChineseCharacters(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + ((0x4E00...0x9FA5).contains($1.value) ? 1 : 0) }
    }

    /// LanguageEnum.languageConversionMap：语种码 → 界面语种名（languageType）
    static let languageConversionMap: [String: String] = [
        "cmn": "中文(简体)",
        "eng": "英语",
        "jpn": "日语",
        "rus": "俄语",
        "kor": "韩语"
    ]
    /// 界面语种名 → 内部 code（TLanguage）
    private static let codeFromType: [String: String] = [
        "中文(简体)": "zh", "英语": "en", "日语": "ja", "俄语": "ru", "韩语": "ko"
    ]

    /// languageUtil.getLanguageNameConversion：输入内容语种（返回界面语种名）
    /// 1) franc 五语种检测  2) 中文字符>2：日语保留，否则强制 cmn  3) und → eng
    static func getLanguageNameConversion(_ translateContent: String) -> String {
        var language = francGuess(translateContent)
        if countChineseCharacters(translateContent) > 2 {
            language = (language == "jpn") ? language : "cmn"
        }
        if language == nil { language = "eng" }   // LanguageEnum.NO → ENGLISH
        return languageConversionMap[language!] ?? "中文(简体)"
    }

    /// languageUtil.getLanguageResultNameConversion：翻译结果语种（返回界面语种名）
    /// 默认中文；und 时保持默认；cmn→eng、eng→cmn、其他→中文
    static func getLanguageResultNameConversion(_ translateContent: String) -> String {
        var language = francGuess(translateContent)
        if countChineseCharacters(translateContent) > 2 {
            language = (language == "jpn") ? language : "cmn"
        }
        var languageResultType = "cmn"
        if language != nil {
            if language == "cmn" {
                languageResultType = "eng"      // 中文输入 → 英文结果
            } else if language == "eng" {
                languageResultType = "cmn"      // 英文输入 → 中文结果
            } else {
                languageResultType = "cmn"      // 其他语言默认中文结果
            }
        }
        return languageConversionMap[languageResultType] ?? "中文(简体)"
    }

    /// languageUtil.isEnglish：/[a-zA-Z]/.test(str)
    static func isEnglish(_ str: String) -> Bool {
        str.range(of: "[a-zA-Z]", options: .regularExpression) != nil
    }

    // 内部便捷封装（返回 TLanguage code）
    static func detect(_ text: String) -> String {
        codeFromType[getLanguageNameConversion(text)] ?? "en"
    }

    /// 结果语言 AUTO：与 getLanguageResultNameConversion 同一条路径（输入是待译文本）；
    /// 兼容传入内部语种码（AppDelegate 旧调用）：按码版规则 cmn→eng、其余→cmn
    static func autoTarget(for text: String) -> String {
        if TLanguage.all.contains(where: { $0.code == text }) {
            // 是内部语种码（auto/zh/en/…），走码版规则
            return text == "zh" ? "en" : "zh"
        }
        return codeFromType[getLanguageResultNameConversion(text)] ?? "zh"
    }

    // MARK: - 翻译入口

    func translate(text: String,
                   source: String = "auto",
                   target: String = "auto",
                   onDelta: @escaping (String) -> Void,
                   onDone: @escaping (Result<String, Error>) -> Void) {
        let src = source == "auto" ? OllamaClient.detect(text) : source
        let tgt = target == "auto" ? OllamaClient.autoTarget(for: text) : target
        let promptId = UserDefaults.standard.string(forKey: "aiPromptId") ?? "translate"
        guard let prompt = AiPrompt.find(promptId) else {
            onDone(.failure(err("请选择可用的本地提示词"))); return
        }
        func fill(_ t: String) -> String {
            t.replacingOccurrences(of: "{{text}}", with: text)
             .replacingOccurrences(of: "{{source}}", with: TLanguage.find(src).prompt)
             .replacingOccurrences(of: "{{target}}", with: TLanguage.find(tgt).prompt)
        }
        call(system: fill(prompt.system), user: fill(prompt.user), onDelta: onDelta, onDone: onDone)
    }

    /// 取消当前请求（被取消的请求不回调错误）
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func err(_ msg: String) -> NSError { OllamaClient.mkErr(msg) }
    static func mkErr(_ msg: String) -> NSError {
        NSError(domain: "llm", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    private func call(system: String, user: String,
                      onDelta: @escaping (String) -> Void,
                      onDone: @escaping (Result<String, Error>) -> Void) {
        // 同一通道再次发起：abort 上一个
        cancel()
        guard !Config.model.isEmpty else { onDone(.failure(err("请先在设置中填写模型名"))); return }
        guard let url = URL(string: Config.ollamaURL) else { onDone(.failure(err("接口地址无效"))); return }

        var body: [String: Any] = [:]
        let rawArgs = (UserDefaults.standard.string(forKey: "requestArguments") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawArgs.isEmpty {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(rawArgs.utf8)) as? [String: Any] else {
                onDone(.failure(err("Request Arguments 必须是有效的 JSON 对象"))); return
            }
            body = obj
        } else {
            body["temperature"] = 0.1
        }
        body["model"] = Config.model
        body["messages"] = [["role": "system", "content": system], ["role": "user", "content": user]]
        body["stream"] = true

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = UserDefaults.standard.string(forKey: "appKey"), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        var task: Task<Void, Never>!
        task = Task.detached { [weak self] in
            var full = ""
            var sawDone = false
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { throw OllamaClient.mkErr("无响应") }
                if !(200..<300).contains(http.statusCode) {
                    var data = Data()
                    for try await b in bytes { data.append(b); if data.count > 2000 { break } }
                    throw OllamaClient.mkErr("HTTP \(http.statusCode): \(String(decoding: data, as: UTF8.self).prefix(300))")
                }
                let isSSE = (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("event-stream")
                if !isSSE {
                    // 非流式兜底：服务端忽略 stream 时一次性赋值
                    var data = Data()
                    for try await b in bytes { data.append(b) }
                    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = object["choices"] as? [[String: Any]],
                       let message = choices.first?["message"] as? [String: Any],
                       let content = message["content"] as? String, !content.isEmpty {
                        full = content; sawDone = true
                        onDelta(content)
                    } else {
                        // 也可能是未标注类型的 SSE 文本
                        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                            if OllamaClient.handle(line: String(line), full: &full, sawDone: &sawDone, onDelta: onDelta) { break }
                        }
                    }
                } else {
                    for try await line in bytes.lines {
                        if Task.isCancelled { return }
                        if OllamaClient.handle(line: line, full: &full, sawDone: &sawDone, onDelta: onDelta) { break }
                    }
                }
                if Task.isCancelled { return }
                if full.isEmpty { throw OllamaClient.mkErr("服务未返回文本结果") }
                if !sawDone { throw OllamaClient.mkErr("流式响应提前结束") }
                self?.finish(task)
                onDone(.success(full))
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError { return }
                self?.finish(task)
                onDone(.failure(error))
            }
        }
        currentTask = task
    }

    private func finish(_ task: Task<Void, Never>?) {
        DispatchQueue.main.async { if self.currentTask == task { self.currentTask = nil } }
    }

    /// 解析一行 SSE；返回 true 表示收到 [DONE]
    private static func handle(line: String, full: inout String, sawDone: inout Bool,
                               onDelta: (String) -> Void) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return false }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { sawDone = true; return true }
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]] else { return false }
        if let reason = choices.first?["finish_reason"] as? String, !reason.isEmpty { sawDone = true }
        guard let delta = choices.first?["delta"] as? [String: Any],
              let piece = delta["content"] as? String, !piece.isEmpty else { return false }
        full += piece
        onDelta(piece)
        return false
    }
}
