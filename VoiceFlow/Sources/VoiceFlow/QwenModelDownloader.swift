import Foundation
import Combine

/// Qwen 模型下载器：HF 仓库是多文件目录（safetensors/config/tokenizer…），
/// 先取文件清单再逐个下载。hf-mirror.com 优先，失败回退 huggingface.co。
final class QwenModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {

    static let shared = QwenModelDownloader()

    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var statusText = ""

    private let hosts = ["https://hf-mirror.com", "https://huggingface.co"]
    private var hostIndex = 0
    private var repo = ""
    private var destDir: URL!
    private var files: [(path: String, size: Int64)] = []
    private var fileIndex = 0
    private var completedBytes: Int64 = 0
    private var totalBytes: Int64 = 1
    private var session: URLSession?
    private var currentTask: URLSessionDownloadTask?
    private var cancelled = false

    func download(repo: String) {
        guard !isDownloading else { return }
        self.repo = repo
        self.destDir = QwenModels.localDirectory(for: repo)
        hostIndex = 0
        fileIndex = 0
        completedBytes = 0
        cancelled = false
        isDownloading = true
        progress = 0
        statusText = "正在获取文件清单…"
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        fetchFileList()
    }

    func cancel() {
        cancelled = true
        currentTask?.cancel()
        session?.invalidateAndCancel()
        session = nil
        isDownloading = false
        statusText = "已取消"
    }

    // MARK: - 文件清单

    private func fetchFileList() {
        guard hostIndex < hosts.count else {
            finishWithError("无法获取模型文件清单，请检查网络")
            return
        }
        let url = URL(string: "\(hosts[hostIndex])/api/models/\(repo)/tree/main")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, !self.cancelled else { return }
                guard error == nil,
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data = data,
                      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    self.hostIndex += 1
                    self.fetchFileList()
                    return
                }
                var list: [(String, Int64)] = []
                for item in array {
                    guard (item["type"] as? String) == "file",
                          let path = item["path"] as? String else { continue }
                    // 跳过隐藏文件和文档
                    if path.hasPrefix(".") || path.lowercased().hasSuffix(".md") { continue }
                    let size = (item["size"] as? Int64) ?? Int64((item["size"] as? Int) ?? 0)
                    list.append((path, size))
                }
                guard !list.isEmpty else {
                    self.finishWithError("模型仓库为空或清单格式异常")
                    return
                }
                self.files = list
                self.totalBytes = max(1, list.reduce(0) { $0 + $1.1 })
                self.downloadNextFile()
            }
        }
        task.resume()
    }

    // MARK: - 逐文件下载

    private func downloadNextFile() {
        guard !cancelled else { return }
        guard fileIndex < files.count else {
            isDownloading = false
            progress = 1
            statusText = "下载完成 ✓（\(files.count) 个文件）"
            session?.finishTasksAndInvalidate()
            session = nil
            return
        }
        let file = files[fileIndex]
        let url = URL(string: "\(hosts[hostIndex])/\(repo)/resolve/main/\(file.path)")!

        // 已存在且大小一致的文件直接跳过（断点续传粒度=文件）
        let dest = destDir.appendingPathComponent(file.path)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
           let size = attrs[.size] as? Int64, size == file.size, file.size > 0 {
            completedBytes += file.size
            fileIndex += 1
            progress = Double(completedBytes) / Double(totalBytes)
            downloadNextFile()
            return
        }

        if session == nil {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        }
        statusText = "下载中 (\(fileIndex + 1)/\(files.count))：\(file.path)"
        let task = session!.downloadTask(with: url)
        currentTask = task
        task.resume()
    }

    private func finishWithError(_ message: String) {
        isDownloading = false
        statusText = "失败：\(message)"
        session?.finishTasksAndInvalidate()
        session = nil
    }

    // MARK: - URLSessionDownloadDelegate（delegateQueue = main）

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard !cancelled else { return }
        let done = completedBytes + totalBytesWritten
        progress = min(1, Double(done) / Double(totalBytes))
        let doneMB = Double(done) / 1_048_576
        let totalMB = Double(totalBytes) / 1_048_576
        statusText = String(format: "下载中 (%d/%d) %.0f / %.0f MB",
                            fileIndex + 1, files.count, doneMB, totalMB)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let http = downloadTask.response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            retryOrFail()
            return
        }
        let file = files[fileIndex]
        let dest = destDir.appendingPathComponent(file.path)
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            finishWithError("保存失败：\(error.localizedDescription)")
            return
        }
        completedBytes += max(file.size, 0)
        fileIndex += 1
        downloadNextFile()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        retryOrFail()
    }

    private func retryOrFail() {
        guard !cancelled else { return }
        if hostIndex + 1 < hosts.count {
            // 换镜像源重试当前文件
            hostIndex += 1
            downloadNextFile()
        } else {
            finishWithError("下载源均失败，请检查网络后重试（已完成的文件会保留，重试可续传）")
        }
    }
}
