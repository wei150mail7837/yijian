import Foundation

/// Ollama OpenAI 兼容接口客户端（流式输出）
final class OllamaClient {
    static let shared = OllamaClient()

    private(set) var isBusy = false

    /// 翻译：自动判断方向（中文→英，其他→中）
    func translate(text: String,
                   onDelta: @escaping (String) -> Void,
                   onDone: @escaping (Result<String, Error>) -> Void) {
        let target = isMostlyChinese(text) ? "English" : "简体中文"
        let system = """
        You are a translation engine. Translate the user's text into \(target). \
        Output ONLY the translation, no explanations, no quotes. Keep formatting.
        """
        call(system: system, user: text, onDelta: onDelta, onDone: onDone)
    }

    private func isMostlyChinese(_ s: String) -> Bool {
        let cjk = s.filter { $0.unicodeScalars.first?.properties.generalCategory == .otherLetter
            && ("\u{4E00}"..."\u{9FFF}").contains($0) }
        return cjk.count > s.count / 2
    }

    private func call(system: String, user: String,
                      onDelta: @escaping (String) -> Void,
                      onDone: @escaping (Result<String, Error>) -> Void) {
        guard !isBusy else {
            onDone(.failure(NSError(domain: "llm", code: -1, userInfo: [NSLocalizedDescriptionKey: "正在翻译中，请稍候"])))
            return
        }
        guard !Config.model.isEmpty else {
            onDone(.failure(NSError(domain: "llm", code: -1, userInfo: [NSLocalizedDescriptionKey: "请先在设置中填写模型名"])))
            return
        }
        guard let url = URL(string: Config.ollamaURL) else {
            onDone(.failure(NSError(domain: "llm", code: -1, userInfo: [NSLocalizedDescriptionKey: "接口地址无效"])))
            return
        }
        isBusy = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        let body: [String: Any] = [
            "model": Config.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "stream": true,
            "temperature": 0.1
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            self.isBusy = false
            if let error = error {
                onDone(.failure(error)); return
            }
            guard let http = response as? HTTPURLResponse else {
                onDone(.failure(NSError(domain: "llm", code: -1, userInfo: [NSLocalizedDescriptionKey: "无响应"])))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let detail = String(data: data ?? Data(), encoding: .utf8) ?? ""
                onDone(.failure(NSError(domain: "llm", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(detail.prefix(200))"])))
                return
            }
            // 非流式兜底（服务端忽略 stream 时）
            if let object = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
               let choices = object["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                onDelta(content)
                onDone(.success(content))
                return
            }
            // SSE 流式解析
            var full = ""
            let raw = String(data: data ?? Data(), encoding: .utf8) ?? ""
            for line in raw.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("data:") else { continue }
                let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard payload != "[DONE]",
                      let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                      let choices = object["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let piece = delta["content"] as? String else { continue }
                full += piece
                onDelta(piece)
            }
            if full.isEmpty {
                onDone(.failure(NSError(domain: "llm", code: -1, userInfo: [NSLocalizedDescriptionKey: "服务未返回翻译结果"])))
            } else {
                onDone(.success(full))
            }
        }
        task.resume()
    }
}
