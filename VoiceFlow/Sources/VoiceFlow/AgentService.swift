import Foundation

// MARK: - 统一的大模型调用层
// PolishService 与各技能共用：OpenAI 兼容接口 + 自动重试

enum LLMClient {

    /// 这些网络错误值得重试（连接被重置、超时、DNS 失败等瞬时故障）
    private static let retryableCodes: Set<Int> = [
        NSURLErrorTimedOut,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorCannotFindHost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorSecureConnectionFailed,
    ]

    /// 调用 chat/completions。completion 在主线程回调：(结果, 失败原因)。
    static func chat(messages: [[String: String]],
                     temperature: Double,
                     timeout: TimeInterval,
                     completion: @escaping (String?, String?) -> Void) {
        guard let apiKey = KeychainHelper.loadAPIKey() else {
            DispatchQueue.main.async { completion(nil, "未配置 API Key") }
            return
        }
        var base = Settings.shared.currentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let url = URL(string: base + "/chat/completions") else {
            DispatchQueue.main.async { completion(nil, "Base URL 格式不对") }
            return
        }

        let body: [String: Any] = [
            "model": Settings.shared.currentChatModel,
            "temperature": temperature,
            "messages": messages,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        send(request, retriesLeft: 1, completion: completion)
    }

    private static func send(_ request: URLRequest, retriesLeft: Int,
                             completion: @escaping (String?, String?) -> Void) {
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            var result: String? = nil
            var failure: String? = nil

            if let error = error {
                let nsError = error as NSError
                if retryableCodes.contains(nsError.code), retriesLeft > 0 {
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
}

// MARK: - 技能执行（V3）

enum AgentService {

    /// 技能：按口述指令修改选中文本
    static func modifySelection(_ selection: String, instruction: String,
                                completion: @escaping (String?, String?) -> Void) {
        let system = """
        你是一个文本修改助手。用户提供一段原文和一条修改指令，你输出修改后的文本。
        规则：
        1. 严格按指令修改；指令未涉及的部分保持原样。
        2. 保持原文语言，除非指令明确要求翻译。
        3. 保留原文中的事实信息：人名、日期、数字、条件、否定。
        4. 只输出修改后的文本，不解释、不加任何前后缀。
        """
        let user = "修改指令：\(instruction)\n\n原文：\n\(selection)"
        LLMClient.chat(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ], temperature: 0.3, timeout: 25, completion: completion)
    }

    /// 技能：自由指令——把口述当作给大模型的任务（草拟邮件、翻译、列提纲、解释等），
    /// 输出可直接粘贴使用的成品文本
    static func freeform(instruction: String, scene: AppScene,
                         completion: @escaping (String?, String?) -> Void) {
        var system = """
        你是一个语音驱动的写作助手。用户口述一个任务——草拟邮件、翻译一段话、改写、起标题、列提纲、回答问题等——你输出可以直接粘贴使用的成品文本。
        规则：
        1. 只输出结果正文，不解释、不加"好的""以下是"之类的前后缀。
        2. 绝不编造具体事实：用户没提供的人名、日期、金额、地址等，用【待补充】占位。
        3. 输出语言跟随任务要求；任务没指定时，跟随口述使用的语言。
        4. 如果口述是一个问题，直接给出简洁准确的答案正文。
        5. 按任务类型输出对应的格式，这一点非常重要：
           - 邮件：完整邮件格式——称呼独立一行，正文分段，礼貌收尾加署名（署名用【你的名字】占位，除非用户提供）；用户要求时可在首行加「主题：…」。
           - 列表/提纲/待办/步骤：用条目列表逐行输出。
           - 聊天消息：一段简短自然的话，不要称呼和落款。
           - 翻译/改写：只输出结果文本本身。
           - 文档段落：书面化、结构清晰。
        """
        if scene != .unknown {
            system += "\n当前粘贴目标场景：\(scene.styleHint)"
        }
        LLMClient.chat(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": instruction],
        ], temperature: 0.4, timeout: 40, completion: completion)
    }

    /// 技能：根据选中的对方消息草拟回复
    static func replyDraft(context: String, instruction: String, scene: AppScene,
                           completion: @escaping (String?, String?) -> Void) {
        var system = """
        你是一个回复草拟助手。用户给你一段"对方发来的消息/上下文"，你代表用户起草一条可以直接发送的回复。
        规则：
        1. 口吻自然得体，像用户本人写的，不卑不亢。
        2. 用户口述里若有具体要求（同意/拒绝/要点/语气），必须严格体现。
        3. 不编造用户没有表达的承诺或事实；信息不足时用开放但明确的表述。
        4. 使用与对方消息一致的语言。
        5. 只输出回复正文，不解释。
        """
        switch scene {
        case .chat:
            system += "\n场景：即时聊天——简短自然，不需要称呼和落款。"
        case .email:
            system += "\n场景：邮件——补全合适的称呼和简洁收尾，但不过度客套。"
        default:
            break
        }
        let req = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = "对方消息/上下文：\n\(context)\n\n用户要求：\(req.isEmpty ? "得体地回复" : req)"
        LLMClient.chat(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ], temperature: 0.4, timeout: 25, completion: completion)
    }
}
