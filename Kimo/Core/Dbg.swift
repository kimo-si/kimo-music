import Foundation

enum Dbg {
    static func log(_ message: String) {
        #if DEBUG
        let line = "[dbg] \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/kimo-debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
        #endif
    }
}
