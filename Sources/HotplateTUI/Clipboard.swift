import Foundation

public enum Clipboard {
    public static func copy(_ text: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let pipe = Pipe()
        p.standardInput = pipe
        do {
            try p.run()
            // The throwing variant reports EPIPE (pbcopy gone) as an error instead of raising an ObjC exception.
            try pipe.fileHandleForWriting.write(contentsOf: Data(text.utf8))
            try pipe.fileHandleForWriting.close()
        } catch {}
    }
}
