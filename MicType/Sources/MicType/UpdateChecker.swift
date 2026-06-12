import AppKit

/// 轻量更新检查：查 GitHub Releases latest → 比版本 → 下载 zip 到「下载」文件夹并在 Finder 选中。
/// 不做自动替换（完整自更新留给 Sparkle 阶段），用户拖一下即完成升级。
enum UpdateChecker {

    enum CheckResult {
        case upToDate(String)               // 已是最新（当前版本号）
        case downloaded(String, URL)        // 新版本号、已下载的 zip 路径
        case failed(String)                 // 用户可读的失败原因
    }

    static let releasesPage = URL(string: "https://github.com/genli-ai/MicType/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 主线程回调
    static func checkAndDownload(completion: @escaping (CheckResult) -> Void) {
        let finish: (CheckResult) -> Void = { r in DispatchQueue.main.async { completion(r) } }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/genli-ai/MicType/releases/latest")!,
                                 timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Log.warn("Update check failed: \(error.localizedDescription)")
                finish(.failed(error.localizedDescription))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                Log.warn("Update check: unexpected response")
                finish(.failed(tr("GitHub 返回了无法解析的内容", "Unexpected response from GitHub")))
                return
            }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            Log.info("Update check latest=\(latest) current=\(currentVersion)")
            guard isNewer(latest, than: currentVersion) else {
                finish(.upToDate(currentVersion))
                return
            }

            guard let assets = json["assets"] as? [[String: Any]],
                  let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix("-arm64.zip") == true }),
                  let urlString = asset["browser_download_url"] as? String,
                  let assetName = asset["name"] as? String,
                  let downloadURL = URL(string: urlString) else {
                finish(.failed(tr("新版本没有可下载的 zip 包", "The new release has no downloadable zip")))
                return
            }

            downloadAsset(downloadURL, named: assetName, version: latest, finish: finish)
        }.resume()
    }

    private static func downloadAsset(_ url: URL, named name: String, version: String,
                                      finish: @escaping (CheckResult) -> Void) {
        URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            if let error = error {
                Log.warn("Update download failed: \(error.localizedDescription)")
                finish(.failed(error.localizedDescription))
                return
            }
            guard let tempURL = tempURL else {
                finish(.failed(tr("下载失败", "Download failed")))
                return
            }
            do {
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                let dest = downloads.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)
                Log.info("Update downloaded \(name) -> Downloads")
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
                finish(.downloaded(version, dest))
            } catch {
                finish(.failed(error.localizedDescription))
            }
        }.resume()
    }

    /// 数字分段比较："3.2.12" vs "3.2.9" → true
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
