import Foundation

/// 调用 OpenAI（或兼容接口）对识别文本做润色
enum PolishService {

    /// 润色。completion 在主线程回调：(润色结果, 失败原因)。
    /// 结果为 nil 时调用方降级用原文，失败原因用于提示用户。
    static func polish(_ rawText: String, level: PolishLevel,
                       completion: @escaping (String?, String?) -> Void) {
        guard level != .off else {
            DispatchQueue.main.async { completion(rawText, nil) }
            return
        }
        guard let apiKey = KeychainHelper.loadAPIKey() else {
            DispatchQueue.main.async { completion(nil, "未配置 API Key") }
            return
        }

        var base = Settings.shared.openaiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let url = URL(string: base + "/chat/completions") else {
            DispatchQueue.main.async { completion(nil, "Base URL 格式不对") }
            return
        }

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt(for: level)]
        ]
        messages.append(contentsOf: examplePair(for: level))
        messages.append(["role": "user", "content": rawText])

        let body: [String: Any] = [
            "model": Settings.shared.chatModel,
            "temperature": level == .deep ? 0.4 : 0.2,
            "messages": messages,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // 超时就直接输出识别原文，不让用户干等；深度润色给更多时间
        request.timeoutInterval = level == .deep ? 25 : 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // 网络抖动（连接中断/超时等）自动重试一次
        send(request, retriesLeft: 1, completion: completion)
    }

    /// 这些网络错误值得重试（连接被重置、超时、DNS 失败等瞬时故障）
    private static let retryableCodes: Set<Int> = [
        NSURLErrorTimedOut,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorCannotFindHost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorSecureConnectionFailed,
    ]

    private static func send(_ request: URLRequest, retriesLeft: Int,
                             completion: @escaping (String?, String?) -> Void) {
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            var result: String? = nil
            var failure: String? = nil

            if let error = error {
                let nsError = error as NSError
                if retryableCodes.contains(nsError.code), retriesLeft > 0 {
                    // 0.5 秒后自动重试
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        send(request, retriesLeft: retriesLeft - 1, completion: completion)
                    }
                    return
                }
                failure = nsError.code == NSURLErrorTimedOut
                    ? "请求超时（已重试，网络到 API 太慢）"
                    : error.localizedDescription + "（已重试）"
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                var detail = ""
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let err = json["error"] as? [String: Any],
                   let msg = err["message"] as? String {
                    detail = "：" + String(msg.prefix(60))
                }
                switch http.statusCode {
                case 401: failure = "API Key 无效 (401)" + detail
                case 404: failure = "模型名不存在 (404)" + detail
                case 429: failure = "限流或余额不足 (429)" + detail
                default: failure = "接口返回 \(http.statusCode)" + detail
                }
            } else if let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    failure = "模型返回了空内容"
                } else {
                    result = trimmed
                }
            } else {
                failure = "返回格式无法解析"
            }
            DispatchQueue.main.async { completion(result, failure) }
        }
        task.resume()
    }

    // MARK: - 提示词

    private static func systemPrompt(for level: PolishLevel) -> String {
        var prompt = """
        你是一个语音输入润色引擎。用户发来的是语音识别的原始文本，你输出处理后的文本。通用规则：
        1.【最重要】绝对禁止翻译！说话人用什么语言，就输出什么语言——中文、English、日本語、한국어、Français 或任何语言都一样；多语言混合就保持混合，逐句跟随原文语言。这是语音输入工具，说话人怎么说就怎么写。
        2. 删除口头禅、语气词（各语言的都算：嗯、呃、那个、um、uh、えーと、euh 等）和无意义的重复、结巴。
        3. 标点跟随语言：西文句子用半角标点（. , ?），中文日文句子用全角标点（。，？）。中文一律简体。
        4. 修正同音错别字和识别错误。中英混合口述常见错误要重点修复：英文单词被错写成发音相近的中文（如 "拍森" → "Python"）、英文拼写错误。结合上下文恢复说话人原本想说的英文，但禁止把已经正确的英文改成中文。
        5. 同一短语被无意义地重复多次是识别故障，只保留一次。
        6. 如果口述里带有自我修正（如"不对，应该是…""刚才那句删掉"），按说话人最终意图执行修正。
        7. 不回答问题、不解释、不添加新内容，只输出最终文本，不要任何前后缀。
        """

        switch level {
        case .off, .light:
            prompt += """


            本次任务档位：标准润色。删除的范围有严格边界，只允许删除以下三类：
            (a) 语气词和口头禅；(b) 无意义的重复和结巴；(c) 自我修正中被说话人放弃的部分。
            边界之外的每一句话、每一个信息点都必须保留，不概括、不合并、不改写句式。
            特别注意：这条边界只约束"删除"，绝不约束"纠错"——规则 4 的错别字修正、同音词纠正、
            识别错误恢复（如"上小王和优次会表"→"上下文和词汇表"）必须积极执行，这是你的核心职责。
            """
        case .deep:
            prompt += """


            本次任务档位：深度润色。在通用规则之上，重新组织整段表达：
            - 理顺逻辑顺序，把跳跃、绕弯的口语整理成条理清晰的表达
            - 合并重复表达的观点，删掉车轱辘话
            - 内容较多时合理分段，必要时用序号列点
            - 保持说话人的本意、立场和语气，不添加新观点、不丢失实质内容
            - 重组后的输出语言必须与原文一致：原文是哪种语言（或几种语言混合），整理结果就用哪种语言，绝不翻译
            """
        }

        let vocab = Settings.shared.vocabularyTerms
        if !vocab.isEmpty {
            prompt += "\n\n用户的专有词汇表：" + vocab.joined(separator: "、") + "。识别文本中出现近音/错写时，优先纠正为这些词。"
        }
        let custom = Settings.shared.customPolishRules.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            prompt += "\n用户附加规则：" + custom
        }
        return prompt
    }

    /// 一组示例对话，固定"保留中英混合、不翻译"的行为
    private static func examplePair(for level: PolishLevel) -> [[String: String]] {
        switch level {
        case .deep:
            return [
                ["role": "user", "content": "嗯我想说一下就是那个项目的事情呃首先吧其实我们时间不太够然后人也不够 deadline 也很紧就是说如果要按原计划上线的话呃风险挺大的所以我觉得要么砍需求要么延期嗯对就是这个意思"],
                ["role": "assistant", "content": "关于项目的事情，我的看法是：目前时间和人手都不够，deadline 也很紧，按原计划上线风险很大。所以建议二选一：要么砍需求，要么延期。"],
            ]
        default:
            return [
                ["role": "user", "content": "嗯我现在在用这个语音输入法给你发消息呃 I'm trying to use both English and Chinese to test然后看看效果怎么样"],
                ["role": "assistant", "content": "我现在在用这个语音输入法给你发消息。I'm trying to use both English and Chinese to test. 看看效果怎么样。"],
            ]
        }
    }

    /// 测试 API 连接。completion 在主线程回调 (是否成功, 提示信息)。
    static func test(completion: @escaping (Bool, String) -> Void) {
        guard KeychainHelper.loadAPIKey() != nil else {
            completion(false, "还没有填 API Key")
            return
        }
        polish("测试，嗯，这是一条，呃，测试消息", level: .light) { result, failure in
            if let r = result {
                completion(true, "连接成功 ✓ 返回：\(r)")
            } else {
                completion(false, "连接失败——\(failure ?? "未知原因")")
            }
        }
    }
}
