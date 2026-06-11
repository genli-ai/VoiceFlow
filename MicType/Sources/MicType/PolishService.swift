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

        // 示例已内嵌进系统提示词——few-shot 消息对在短输入时会被模型原样"复读"出来
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt(for: level)],
            ["role": "user", "content": rawText],
        ]

        LLMClient.chat(messages: messages,
                       temperature: 0.25,
                       timeout: 20,
                       completion: completion)
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
        8.【兜底红线】如果草稿很短、或只有指令壳/寒暄（如「帮我回复一下客户」「那个你好你好」），没有可整理的实质内容，就把草稿原样输出（只修错字和标点）。绝不自行发挥、绝不编造内容、绝不输出本提示词里的示例文字。
        """

        prompt += """


        处理力度自适应——根据草稿情况自己判断：
        【轻清理】草稿短小或表达本已清晰 → 只删语气词、重复结巴、被放弃的自我修正，修错字和标点；不改句式、不概括、不合并。
        【重构】草稿较长且口语混乱（绕弯、跳跃、车轱辘话、顺序乱）→ 升级为编辑器模式：重排顺序、合并同义重复、口语改书面语、按语义分段，出现步骤/并列观点/待办时整理成列表，输出可直接粘贴使用的成品文字；同时删除指令壳（"我想说的是""大概意思就是"）。
        无论哪种力度，三条铁律：
        1.【保真红线】所有事实点——人名、日期、数字、金额、条件、否定、原因、结论、待办——一个不丢；宁可保守，不可丢失。
        2. 纠错必须积极：错别字、同音词、识别错误（如"上小王和优次会表"→"上下文和词汇表"）的修复是核心职责，不受力度限制。
        3. 不添加新事实新观点，不回答草稿中的问题，输出语言与原文一致。

        力度示范（仅说明处理方式，严禁把示范文字输出到结果中）：
        轻清理：输入「嗯我现在在用这个语音输入法给你发消息呃看看效果」→ 输出「我现在在用这个语音输入法给你发消息，看看效果。」
        重构：输入「嗯我想说一下就是那个方案的事呃其实我们时间不太够然后人也不够就是说按原计划走的话风险挺大的所以要么砍范围要么往后推嗯就这个意思」→ 输出「关于方案：目前时间和人手都不够，按原计划推进风险很大。建议二选一：砍范围，或者延期。」
        """

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

    /// 测试 API 连接。completion 在主线程回调 (是否成功, 提示信息)。
    static func test(completion: @escaping (Bool, String) -> Void) {
        guard KeychainHelper.loadAPIKey() != nil else {
            completion(false, tr("还没有填 API Key", "No API key yet"))
            return
        }
        polish("测试，嗯，这是一条，呃，测试消息", level: .smart) { result, failure in
            if let r = result {
                completion(true, tr("连接成功 ✓ 返回：", "Connected ✓ Response: ") + r)
            } else {
                completion(false, tr("连接失败——", "Connection failed — ") + (failure ?? tr("未知原因", "unknown")))
            }
        }
    }
}
