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

    /// 录音开始时调用：预热到 API 的连接（DNS + TLS 握手在用户说话期间完成），结果丢弃
    static func prewarm() {
        guard let apiKey = KeychainHelper.loadAPIKey() else { return }
        var base = Settings.shared.currentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let url = URL(string: base + "/models") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request).resume()
    }

    /// 调用 chat/completions。completion 在主线程回调：(结果, 失败原因)。
    /// model：润色传 currentPolishModel（快），指令传 currentCommandModel（强）。
    static func chat(messages: [[String: String]],
                     temperature: Double,
                     timeout: TimeInterval,
                     model: String,
                     completion: @escaping (String?, String?) -> Void) {
        perform(messages: messages, temperature: temperature, timeout: timeout, model: model) { result, failure in
            // 推理系模型（gpt-5.5 / *-pro 等）只接受默认 temperature：被拒时去掉该参数重试一次
            if result == nil, let failure = failure, failure.lowercased().contains("temperature") {
                perform(messages: messages, temperature: nil, timeout: timeout, model: model, completion: completion)
            } else {
                completion(result, failure)
            }
        }
    }

    private static func perform(messages: [[String: String]],
                                temperature: Double?,
                                timeout: TimeInterval,
                                model: String,
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

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
        ]
        if let temperature = temperature {
            body["temperature"] = temperature
        }
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

/// 有选区时统一指令的意图分类（模型自判）
enum SelectionAction: String {
    case modify = "MODIFY"   // 加工选中文本本身 → 替换选区
    case reply = "REPLY"     // 代用户回复选中的消息 → 草稿进剪贴板
    case new = "NEW"         // 写新内容/回答问题 → 粘贴到光标处
}

enum AgentService {

    /// 专有词汇表提示：口述指令里的人名、术语按词汇表纠正
    private static func vocabHint() -> String? {
        let vocab = Settings.shared.vocabularyTerms
        guard !vocab.isEmpty else { return nil }
        var joined = vocab.joined(separator: "、")
        if joined.count > 400 { joined = String(joined.prefix(400)) }
        return "\n用户的专有词汇表：" + joined + "。口述中出现近音/错写时，优先按这些词理解和纠正。"
    }

    /// 用户上下文：「关于我」+ 自定义偏好，注入所有指令 prompt（弥补相对 ChatGPT 缺失的个人记忆）
    private static func userContextHint() -> String {
        var hint = ""
        let about = Settings.shared.aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !about.isEmpty {
            hint += "\n关于用户（落款、署名、语气等写作时参考）：" + about
        }
        let custom = Settings.shared.customPolishRules.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            hint += "\n用户附加偏好：" + custom
        }
        return hint
    }

    /// 邮件格式硬约束：要"动词 + 邮件"组合才注入；用户明确拒绝格式时不注入。
    /// （prompt 规则单独使用时模型遵守不稳定，故程序级补一刀）
    private static func emailFormatRequirement(for instruction: String) -> String? {
        let lower = instruction.lowercased()
        let refusals = ["不要邮件格式", "别用邮件格式", "不用邮件格式", "不要用邮件格式", "no email format"]
        if refusals.contains(where: { lower.contains($0) }) { return nil }
        let nouns = ["邮件", "email", "mail"]
        let verbs = ["写", "草拟", "拟", "回", "发", "draft", "write", "reply", "send", "compose"]
        guard nouns.contains(where: { lower.contains($0) }),
              verbs.contains(where: { lower.contains($0) }) else { return nil }
        return "\n\n[格式硬性要求：按完整邮件格式输出——第一行称呼；空一行；正文分段；空一行；结尾敬语；最后一行署名。署名占位符必须跟随邮件正文的语言：中文邮件写【你的名字】，英文邮件写 [Your Name]。不输出主题行，除非用户明确要求。若用户明确要求不用邮件格式，则按用户要求执行。]"
    }

    /// 技能：有选区时的统一入口——模型先判意图（改写/回复/新写）再直接执行，单次调用。
    /// completion(意图, 正文, 失败原因)：正文非 nil 即成功；意图为 nil 表示首行解析失败，调用方走剪贴板兜底。
    static func runOnSelection(_ selection: String, instruction: String,
                               completion: @escaping (SelectionAction?, String?, String?) -> Void) {
        var system = """
        你是语音指令执行器。用户选中了一段文本，并对它口述了一条指令。你先判断意图，再直接执行。
        第一行只输出意图词本身，三选一：
        MODIFY——指令是要加工选中文本本身（改写、翻译、缩短、扩写、换语气、改格式等）。
        REPLY——选中文本是别人发来的消息或邮件，指令是要代用户起草一条回复（如「回复他/这个人…」「跟他说…」「答应/拒绝/谢谢他」）。
        NEW——指令是要写新内容或回答问题，选中文本只是参考材料，或与任务无关。
        判断依据：指令的动作落在「这段文字」上→MODIFY；落在「发来这段文字的人」上→REPLY；都不是→NEW。
        从第二行起输出执行结果，规则按意图执行：
        - MODIFY：严格按指令修改；指令未涉及的部分保持原样；保持原文语言（除非指令明确要求翻译）；保留人名、日期、数字、条件、否定等事实。
        - REPLY：代用户口吻起草可直接发送的回复，自然得体、不卑不亢；口述里的具体要求（同意/拒绝/要点/语气）必须严格体现；不编造用户没表达的承诺；语言与对方消息一致，除非用户另有要求。
        - NEW：如果是问题，像优秀的 AI 助手一样给出完整、准确的回答，可以展开解释；如果是代用户写东西，输出可直接使用的成品——你不知道的关键事实（具体人名、日期、金额）不要编造，用占位符（中文【待补充】，英文 [TBD]），常识性内容正常发挥。
        除第一行的意图词和之后的结果正文外，不要"好的""以下是"之类的前后缀。
        """
        if let vocab = vocabHint() { system += vocab }
        system += userContextHint()
        var user = "指令：\(instruction)\n\n选中文本：\n\(selection)"
        if let email = emailFormatRequirement(for: instruction) { user += email }
        LLMClient.chat(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ], temperature: 0.35, timeout: 40, model: Settings.shared.currentCommandModel) { result, failure in
            guard let result = result else {
                completion(nil, nil, failure)
                return
            }
            let (action, body) = parseSelectionResult(result)
            if let body = body {
                completion(action, body, nil)
            } else {
                completion(action, nil, tr("模型没有返回内容", "Model returned no content"))
            }
        }
    }

    /// 解析首行意图词 + 正文。首行不是意图词时整体当正文（action = nil，调用方兜底）。
    private static func parseSelectionResult(_ result: String) -> (SelectionAction?, String?) {
        var lines = result.components(separatedBy: "\n")
        let head = lines.removeFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = head.uppercased()
        var action: SelectionAction?
        for candidate in [SelectionAction.modify, .reply, .new] {
            guard upper.hasPrefix(candidate.rawValue) else { continue }
            let rest = head.dropFirst(candidate.rawValue.count)
            let trimmedRest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedRest.isEmpty {
                action = candidate
            } else if let first = trimmedRest.first, ":：—-".contains(first) {
                // 容错："MODIFY：正文" 写在同一行
                action = candidate
                let body = trimmedRest.dropFirst().trimmingCharacters(in: .whitespaces)
                if !body.isEmpty { lines.insert(body, at: 0) }
            }
            break
        }
        if action == nil { lines.insert(head, at: 0) }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (action, body.isEmpty ? nil : body)
    }

    /// 技能：自由指令（无选区）——把口述当作给大模型的任务（草拟邮件、翻译、列提纲、解释等），
    /// 输出可直接粘贴使用的成品文本
    static func freeform(instruction: String,
                         completion: @escaping (String?, String?) -> Void) {
        var system = """
        你是一个语音驱动的写作助手。用户口述一个任务——草拟邮件、翻译一段话、改写、起标题、列提纲、回答问题等——你直接给出可用的结果。
        规则：
        1. 写作类任务只输出成品正文，不加"好的""以下是"之类的前后缀。代用户落款、承诺时间金额等你不知道的关键事实时不要编造——用占位符标注（中文输出用【待补充】，英文输出用 [TBD]）；常识性内容正常发挥，不必缩手缩脚。
        2. 问答类任务：像优秀的 AI 助手一样给出完整、准确的回答，可以展开解释、分点说明，不受"只输出正文"限制。
        3. 输出语言跟随任务要求；任务没指定时，跟随口述使用的语言。
        4. 按任务类型输出对应的格式，这一点非常重要：
           - 邮件：完整邮件格式——称呼独立一行，正文分段，礼貌收尾加署名。署名占位符跟随邮件语言：中文邮件用【你的名字】，英文邮件用 [Your Name]，其他语言同理；用户提供了姓名就直接用。
           - 列表/提纲/待办/步骤：用条目列表逐行输出。
           - 聊天消息：一段简短自然的话，不要称呼和落款。
           - 翻译/改写：只输出结果文本本身。
           - 文档段落：书面化、结构清晰。
        """
        if let vocab = vocabHint() { system += vocab }
        system += userContextHint()
        var userContent = instruction
        if let email = emailFormatRequirement(for: instruction) { userContent += email }
        LLMClient.chat(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": userContent],
        ], temperature: 0.5, timeout: 40, model: Settings.shared.currentCommandModel, completion: completion)
    }

    /// 技能：根据选中的对方消息草拟回复（显式触发词「帮我回复」等直通此处）
    static func replyDraft(context: String, instruction: String,
                           completion: @escaping (String?, String?) -> Void) {
        var system = """
        你是一个回复草拟助手。用户给你一段"对方发来的消息/上下文"，你代表用户起草一条可以直接发送的回复。
        规则：
        1. 口吻自然得体，像用户本人写的，不卑不亢。
        2. 用户口述里若有具体要求（同意/拒绝/要点/语气），必须严格体现。
        3. 不编造用户没有表达的承诺或事实；信息不足时用开放但明确的表述。
        4. 使用与对方消息一致的语言，除非用户另有要求。
        5. 只输出回复正文，不解释。
        """
        if let vocab = vocabHint() { system += vocab }
        system += userContextHint()
        let req = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        var user = "对方消息/上下文：\n\(context)\n\n用户要求：\(req.isEmpty ? "得体地回复" : req)"
        if let email = emailFormatRequirement(for: instruction) { user += email }
        LLMClient.chat(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ], temperature: 0.4, timeout: 25, model: Settings.shared.currentCommandModel, completion: completion)
    }
}
