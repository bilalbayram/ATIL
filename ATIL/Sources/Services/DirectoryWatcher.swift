import Foundation

final class DirectoryWatcher: @unchecked Sendable {
    private let path: String
    private let onChange: @Sendable () -> Void
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    init(path: String, onChange: @escaping @Sendable () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        guard source == nil, FileManager.default.fileExists(atPath: path) else { return }

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [onChange] in
            onChange()
        }
        source.setCancelHandler { [fileDescriptor] in
            if fileDescriptor >= 0 {
                close(fileDescriptor)
            }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    deinit {
        stop()
    }
}
