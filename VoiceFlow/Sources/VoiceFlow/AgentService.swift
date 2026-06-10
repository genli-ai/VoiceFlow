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
            DispatchQueue.main.async { completion(nil, tr("未配置 API Key", "No API key configured")) }
            return
        }
        var base = Settings.shared.currentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let url = URL(string: base + "/chat/completions") else {
            DispatchQueue.main.async { completion(nil, tr("Base URL 格式不对", "Invalid base URL")) }
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
                    ? tr("请求超时（已重试，网络到 API 太慢）", "Request timed out (retried — network to the API is slow)")
                    : error.localizedDescription + tr("（已重试）", " (retried)")
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                var detail = ""
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let err = json["error"] as? [String: Any],
                   let msg = err["message"] as? String {
                    detail = "：" + String(msg.prefix(60))
                }
                switch http.statusCode {
                case 401: failure = tr("API Key 无效 (401)", "Invalid API key (401)") + detail
                case 404: failure = tr("模型名不存在 (404)", "Model not found (404)") + detail
                case 429: failure = tr("限流或余额不足 (429)", "Rate limited or out of credit (429)") + detail
                default: failure = tr("接口返回 ", "API returned ") + "\(http.statusCode)" + detail
                }
            } else if let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    failure = tr("模型返回了空内容", "Model returned empty content")
                } else {
                    result = trimmed
                }
            } else {
                failure = tr("返回格式无法解析", "Could not parse the response")
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
        2. 绝不编造具体事实：用户没提供的人名、日期、金额、地址等，用占位符标注——占位符语言跟随输出语言（中文输出用【待补充】，英文输出用 [TBD]）。
        3. 输出语言跟随任务要求；任务没指定时，跟随口述使用的语言。
        4. 如果口述是一个问题，直接给出简洁准确的答案正文。
        5. 按任务类型输出对应的格式，这一点非常重要：
           - 邮件：完整邮件格式——称呼独立一行，正文分段，礼貌收尾加署名。署名占位符跟随邮件语言：中文邮件用【你的名字】，英文邮件用 [Your Name]，其他语言同理；用户提供了姓名就直接用。
           - 列表/提纲/待办/步骤：用条目列表逐行输出。
           - 聊天消息：一段简短自然的话，不要称呼和落款。
           - 翻译/改写：只输出结果文本本身。
           - 文档段落：书面化、结构清晰。
        """
        if scene != .unknown {
            system += "\n当前粘贴目标场景：\(scene.styleHint)"
        }
        // 程序级硬约束：检测到邮件类任务，强制注入格式模板（prompt 规则单独使用时遵守不稳定）
        var userContent = instruction
        let lower = instruction.lowercased()
        if lower.contains("邮件") || lower.contains("email") || lower.contains("mail") {
            userContent += "\n\n[格式硬性要求：按完整邮件格式输出——第一行称呼；空一行；正文分段；空一行；结尾敬语；最后一行署名。署名占位符必须跟随邮件正文的语言：中文邮件写【你的名字】，英文邮件写 [Your Name]。不输出主题行，除非用户明确要求。]"
        }
        LLMClient.chat(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": userContent],
        ], temperature: 0.25, timeout: 40, completion: completion)
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
        var user = "对方消息/上下文：\n\(context)\n\n用户要求：\(req.isEmpty ? "得体地回复" : req)"
        if scene == .email {
            user += "\n\n[格式硬性要求：按完整邮件格式输出——称呼一行、空行、分段正文、空行、结尾敬语、署名行。署名占位符跟随邮件语言：中文写【你的名字】，英文写 [Your Name]。]"
        }
        LLMClient.chat(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ], temperature: 0.3, timeout: 25, completion: completion)
    }
}
