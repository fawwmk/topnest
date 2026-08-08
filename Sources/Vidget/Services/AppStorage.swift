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

    @discardableResult
    static func preserveCorruptFile(at url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let timestamp = Int(Date().timeIntervalSince1970)
        var backup = url.appendingPathExtension("corrupt-\(timestamp)")
        if FileManager.default.fileExists(atPath: backup.path) {
            backup = url.appendingPathExtension("corrupt-\(timestamp)-\(UUID().uuidString)")
        }
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            return backup
        } catch {
            NSLog(
                "TopNest: не удалось сохранить повреждённый файл %@: %@",
                url.lastPathComponent,
                error.localizedDescription
            )
            return nil
        }
    }
}
