import Foundation

@testable import ProjectWorkspacesCore

final class InMemoryFileSystem: FileSystem {
    private var files: [String: Data]
    private var directories: Set<String>

    init(files: [String: Data], directories: Set<String> = []) {
        self.files = files
        self.directories = directories
    }

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        let _ = url
        return false
    }

    func readFile(at url: URL) throws -> Data {
        if let data = files[url.path] {
            return data
        }
        throw NSError(domain: "TestFileSystem", code: 1)
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = files[url.path] else {
            throw NSError(domain: "TestFileSystem", code: 2)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        if files.removeValue(forKey: url.path) != nil {
            return
        }
        if directories.remove(url.path) != nil {
            return
        }
        throw NSError(domain: "TestFileSystem", code: 3)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        guard let data = files.removeValue(forKey: sourceURL.path) else {
            throw NSError(domain: "TestFileSystem", code: 4)
        }
        files[destinationURL.path] = data
    }

    func appendFile(at url: URL, data: Data) throws {
        if var existing = files[url.path] {
            existing.append(data)
            files[url.path] = existing
        } else {
            files[url.path] = data
        }
    }

    func writeFile(at url: URL, data: Data) throws {
        files[url.path] = data
    }

    func syncFile(at url: URL) throws {
        if files[url.path] == nil {
            throw NSError(domain: "TestFileSystem", code: 5)
        }
    }
}

final class FixedDateProvider: DateProviding {
    private let date: Date

    init(date: Date = Date(timeIntervalSince1970: 0)) {
        self.date = date
    }

    func now() -> Date {
        date
    }
}
