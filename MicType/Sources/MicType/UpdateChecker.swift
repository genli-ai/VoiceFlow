import AppKit

/// 轻量更新检查：查 GitHub Releases latest → 比版本 → 下载安装包到「下载」文件夹并在 Finder 选中。
/// 优先下载公证过的 DMG（应用内更新也零警告）；没有 DMG 时回退 Developer ID 签名的 zip。
/// 不做自动替换（完整自更新留给 Sparkle 阶段），用户拖一下即完成升级。
enum UpdateChecker {

    enum CheckResult {
        case upToDate(String)               // 已是最新（当前版本号）
        case downloaded(String, URL)        // 新版本号、已下载的安装包路径（dmg 或 zip）
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
                fallbackViaRedirect(apiError: error.localizedDescription, finish: finish)
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                // GitHub API 匿名调用在共享出口 IP（国内常见）下极易 403 限流——换无限流的重定向探测
                fallbackViaRedirect(apiError: tr("GitHub API 返回异常（可能是限流）", "Unexpected API response (possibly rate-limited)"),
                                    finish: finish)
                return
            }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            Log.info("Update check latest=\(latest) current=\(currentVersion)")
            guard isNewer(latest, than: currentVersion) else {
                finish(.upToDate(currentVersion))
                return
            }

            // 优先公证过的 DMG（应用内更新也零警告），没有再回退 Developer ID 签名的 zip
            let assets = (json["assets"] as? [[String: Any]]) ?? []
            let pick: (String) -> [String: Any]? = { suffix in
                assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }
            }
            guard let asset = pick("-arm64.dmg") ?? pick("-arm64.zip"),
                  let urlString = asset["browser_download_url"] as? String,
                  let assetName = asset["name"] as? String,
                  let downloadURL = URL(string: urlString) else {
                finish(.failed(tr("新版本没有可下载的安装包", "The new release has no downloadable installer")))
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

    /// API 失败时的兜底：releases/latest 的网页入口会 302 到 /tag/vX.Y.Z——
    /// 从 Location 头解析版本（不经 API、无限流），下载地址按发布命名规矩直接构造
    private static func fallbackViaRedirect(apiError: String, finish: @escaping (CheckResult) -> Void) {
        Log.warn("Update check via API failed: \(apiError) — trying redirect probe")
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        var request = URLRequest(url: releasesPage, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        session.dataTask(with: request) { _, response, _ in
            defer { session.finishTasksAndInvalidate() }
            guard let http = response as? HTTPURLResponse,
                  let location = http.value(forHTTPHeaderField: "Location"),
                  let range = location.range(of: "/tag/", options: .backwards) else {
                finish(.failed(apiError))
                return
            }
            var latest = String(location[range.upperBound...])
            if latest.hasPrefix("v") || latest.hasPrefix("V") { latest.removeFirst() }
            Log.info("Update check (redirect) latest=\(latest) current=\(currentVersion)")
            guard isNewer(latest, than: currentVersion) else {
                finish(.upToDate(currentVersion))
                return
            }
            // 兜底路径（API 被限流时走这里）拿不到资产清单，无法确认 DMG 是否存在——
            // 非公证版本没有 DMG，而 zip 每个版本都有，这里稳妥用 zip；主路径才优先 DMG。
            let name = "MicType-\(latest)-arm64.zip"
            guard let url = URL(string: "https://github.com/genli-ai/MicType/releases/download/v\(latest)/\(name)") else {
                finish(.failed(apiError))
                return
            }
            downloadAsset(url, named: name, version: latest, finish: finish)
        }.resume()
    }

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
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
