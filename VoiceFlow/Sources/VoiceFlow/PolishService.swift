import Foundation

/// 调用 OpenAI（或兼容接口）对识别文本做润色
enum PolishService {

    /// 润色。completion 在主线程回调：(润色结果, 失败原因)。
    /// 结果为 nil 时调用方降级用原文，失败原因用于提示用户。
    /// scene：当前目标应用的场景分类，仅深度润色用于风格适配。
    static func polish(_ rawText: String, level: PolishLevel, scene: AppScene = .unknown,
                       completion: @escaping (String?, String?) -> Void) {
        guard level != .off else {
            DispatchQueue.main.async { completion(rawText, nil) }
            return
        }

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt(for: level, scene: scene)]
        ]
        messages.append(contentsOf: examplePair(for: level))
        messages.append(["role": "user", "content": rawText])

        LLMClient.chat(messages: messages,
                       temperature: level == .deep ? 0.3 : 0.2,
                       timeout: level == .deep ? 25 : 15,
                       completion: completion)
    }

    // MARK: - 提示词

    private static func systemPrompt(for level: PolishLevel, scene: AppScene = .unknown) -> String {
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


            本次任务档位：深度重构（编辑器模式）。用户给你的是语音口述草稿——可能有口头禅、重复、跳跃、自我修正、半句话和顺序混乱。你的目标是输出一段**可以直接粘贴使用的成品文字**：
            - 先理解说话人最终想表达的意思，再重新组织表达：可以重排句子顺序、合并同义重复、把绕弯表达改成直接表达、口语改书面语、补足必要连接词。
            - 删除指令壳（"我想说的是""帮我写一下""大概意思就是"）和寒暄壳，只保留要表达的内容本身。
            - 【保真红线】必须保留所有事实点：人名、日期、数字、金额、条件、否定、原因、结论、待办。删废话时宁可保守，不可丢失任何真实信息。
            - 不添加新事实、新观点，不替用户做没有表达过的判断，不回答草稿中的问题。
            - 内容较长时按语义分段；出现步骤、并列观点、待办、优缺点时自动整理成列表。
            - 重构后的输出语言必须与原文一致，绝不翻译。
            - 输出就是最终文本：不解释你的修改，不加标题（除非内容天然需要）。
            """
            if scene != .unknown {
                prompt += "\n\n当前输出场景：\(scene.styleHint)"
            }
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
