import Foundation

/// One request per instance. Mutable transfer state is confined to the serial delegate queue
/// after the continuation is installed and before the task is resumed. Cancellation touches
/// only URLSession's thread-safe cancellation API; it never mutates delegate state.
final class HTTPTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int64
    private let destination: URL?
    private let progress: ProgressHandler
    private var continuation: CheckedContinuation<Data, any Error>?
    private var output: FileHandle?
    private var data = Data()
    private var count: Int64 = 0
    private var expected: Int64?
    private var failure: (any Error)?

    init(limit: Int64, destination: URL? = nil, progress: @escaping ProgressHandler = { _ in }) {
        self.limit = limit; self.destination = destination; self.progress = progress
    }

    func run(_ request: URLRequest, configuration: URLSessionConfiguration = .ephemeral) async throws -> Data {
        try Task.checkCancellation()
        if let destination {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw LibraryError.message("Could not create the temporary download. Check available storage.")
            }
            output = try FileHandle(forWritingTo: destination)
        }
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Never forward a token to a redirect target, even on the same host. Require the
        // configured URL to address the instance directly (also avoids login-page downloads).
        failure = LibraryError.message("RomM redirected the request. Use its final instance URL and check the reverse proxy.")
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            failure = LibraryError.message("RomM returned an invalid response.")
            completionHandler(.cancel); return
        }
        guard response.statusCode == 200 else {
            if failure == nil {
                switch response.statusCode {
                case 401, 403:
                    failure = LibraryError.message("RomM denied access. Check the API token and its roms.read permission.")
                case 404: failure = LibraryError.message("RomM could not find this item. Refresh the library or check the instance URL.")
                default: failure = LibraryError.message("RomM returned HTTP \(response.statusCode). Try again after checking the server.")
                }
            }
            completionHandler(.cancel); return
        }
        guard response.expectedContentLength <= limit else {
            failure = LibraryError.message("The server response exceeds the allowed size.")
            completionHandler(.cancel); return
        }
        expected = response.expectedContentLength >= 0 ? response.expectedContentLength : nil
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard failure == nil else { return }
        guard Int64(chunk.count) <= limit - count else {
            failure = LibraryError.message("The download exceeds the 64 MiB ROM limit.")
            dataTask.cancel(); return
        }
        do {
            if let output { try output.write(contentsOf: chunk) } else { data.append(chunk) }
            count += Int64(chunk.count)
            progress(TransferProgress(bytes: count, total: expected))
        } catch {
            failure = LibraryError.message("Could not write the download. Check available storage.")
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        do { try output?.close() } catch { failure = failure ?? error }
        output = nil
        let result: Result<Data, any Error>
        if let error = failure ?? error { result = .failure(error) }
        else if let expected, expected != count {
            result = .failure(LibraryError.message("The transfer was incomplete. Retry the download."))
        } else { result = .success(data) }
        continuation?.resume(with: result)
        continuation = nil
    }
}
