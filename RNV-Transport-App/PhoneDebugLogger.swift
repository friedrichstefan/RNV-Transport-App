import Foundation
import os.log

private let _logger = Logger(subsystem: "com.stefanfriedrich.rnvapp", category: "PhoneDebug")
private let _logFile: URL? = {
    FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: "group.com.stefanfriedrich.rnvapp")?
        .appendingPathComponent("phone_debug.log")
}()
private let _logQueue = DispatchQueue(label: "com.stefanfriedrich.rnvapp.debuglog")

func plog(_ msg: String) {
    _logger.debug("\(msg, privacy: .public)")
    guard let url = _logFile else { return }
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    let line = "\(f.string(from: Date())) \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    _logQueue.async {
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

func plogClear() {
    guard let url = _logFile else { return }
    try? FileManager.default.removeItem(at: url)
}
