import Foundation

public enum Clipboard {
    public static func copy(_ text: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let pipe = Pipe()
        p.standardInput = pipe
        do {
            try p.run()
            pipe.fileHandleForWriting.write(Data(text.utf8))
            try pipe.fileHandleForWriting.close()
        } catch {}
    }
}
