import Foundation
import Combine

/// 应用内下载 whisper 模型（优先 hf-mirror.com，失败回退 huggingface.co）
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {

    static let shared = ModelDownloader()

    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var statusText = ""

    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var urls: [URL] = []
    private var urlIndex = 0
    private var targetFileName = ""

    func download(fileName: String) {
        guard !isDownloading else { return }
        targetFileName = fileName
        urls = WhisperModels.downloadURLs(for: fileName)
        urlIndex = 0
        isDownloading = true
        progress = 0
        statusText = "正在连接…"
        startCurrent()
    }

    private func startCurrent() {
        guard urlIndex < urls.count else {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.statusText = "下载失败：所有下载源都无法连接，请检查网络后重试"
            }
            return
        }
        let url = urls[urlIndex]
        session?.finishTasksAndInvalidate()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        DispatchQueue.main.async { self.progress = 0 }
        let task = session.downloadTask(with: url)
        self.task = task
        DispatchQueue.main.async {
            self.statusText = "从 \(url.host ?? "")下载中…"
        }
        task.resume()
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
        DispatchQueue.main.async {
            self.isDownloading = false
            self.statusText = "已取消"
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let mb = Double(totalBytesWritten) / 1_048_576
        let totalMB = Double(totalBytesExpectedToWrite) / 1_048_576
        DispatchQueue.main.async {
            self.progress = p
            self.statusText = String(format: "下载中 %.0f / %.0f MB", mb, totalMB)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let http = downloadTask.response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            // 这个源失败，尝试下一个
            urlIndex += 1
            startCurrent()
            return
        }
        let dest = Paths.modelsDir.appendingPathComponent(targetFileName)
        try? FileManager.default.removeItem(at: dest)
        session.finishTasksAndInvalidate()
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            DispatchQueue.main.async {
                self.isDownloading = false
                self.progress = 1
                self.statusText = "下载完成 ✓"
            }
        } catch {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.statusText = "保存失败：\(error.localizedDescription)"
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        // 网络错误，尝试下一个源
        urlIndex += 1
        startCurrent()
    }
}
