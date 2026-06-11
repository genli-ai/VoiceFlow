import Foundation

struct HistoryItem {
    let date: Date
    let raw: String
    let polished: String
}

/// 最近的听写记录（保留 20 条，持久化到 UserDefaults）
final class HistoryStore {
    static let shared = HistoryStore()
    private let key = "history"
    private let maxCount = 20

    private(set) var items: [HistoryItem] = []

    private init() {
        load()
    }

    func add(raw: String, polished: String) {
        items.insert(HistoryItem(date: Date(), raw: raw, polished: polished), at: 0)
        if items.count > maxCount {
            items = Array(items.prefix(maxCount))
        }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        let array: [[String: Any]] = items.map {
            ["date": $0.date.timeIntervalSince1970, "raw": $0.raw, "polished": $0.polished]
        }
        UserDefaults.standard.set(array, forKey: key)
    }

    private func load() {
        guard let array = UserDefaults.standard.array(forKey: key) as? [[String: Any]] else { return }
        items = array.compactMap { dict in
            guard let t = dict["date"] as? Double,
                  let raw = dict["raw"] as? String,
                  let polished = dict["polished"] as? String else { return nil }
            return HistoryItem(date: Date(timeIntervalSince1970: t), raw: raw, polished: polished)
        }
    }
}
