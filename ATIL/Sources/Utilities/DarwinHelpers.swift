import Darwin

/// Extracts a Swift String from a C char tuple (e.g. `proc_bsdinfo.pbi_name`).
/// These fields are fixed-size C arrays that appear as tuples in Swift.
func stringFromTuple<T>(_ tuple: T, maxLength: Int) -> String {
    withUnsafePointer(to: tuple) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: maxLength) { cStr in
            String(cString: cStr)
        }
    }
}
