import Foundation

enum AppStorage {
    static func supportDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("Vidget", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    static func file(named name: String) throws -> URL {
        try supportDirectory().appendingPathComponent(name, isDirectory: false)
    }
}
