import Foundation

final class HelperDelegate: NSObject, NSXPCListenerDelegate, ATILHelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: ATILHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: ATILAppProtocol.self)
        newConnection.resume()
        return true
    }

    func sendSignal(_ signal: Int32, toPID pid: Int32, withReply reply: @escaping (Bool, String?) -> Void) {
        if kill(pid, signal) == 0 {
            reply(true, nil)
        } else {
            reply(false, String(cString: strerror(errno)))
        }
    }

    func disableLaunchdJob(label: String, domain: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let (success, message) = runLaunchctl(arguments: ["disable", "\(domain)/\(label)"])
        reply(success, message)
    }

    func bootoutLaunchdJob(label: String, domain: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let serviceTarget = "\(domain)/\(label)"
        let (success, message) = runLaunchctl(arguments: ["bootout", serviceTarget])
        reply(success, message)
    }

    func enableLaunchdJob(
        label: String,
        domain: String,
        plistPath: String,
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        let serviceTarget = "\(domain)/\(label)"
        let (enableSuccess, enableMessage) = runLaunchctl(arguments: ["enable", serviceTarget])
        guard enableSuccess else {
            reply(enableSuccess, enableMessage)
            return
        }

        let (bootstrapSuccess, bootstrapMessage) = runLaunchctl(arguments: ["bootstrap", domain, plistPath])
        reply(bootstrapSuccess, bootstrapMessage)
    }

    func getLaunchdJobInfo(label: String, withReply reply: @escaping (Data?) -> Void) {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/\(label)"]
        task.standardOutput = pipe

        do {
            try task.run()
        } catch {
            reply(nil)
            return
        }

        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            reply(nil)
            return
        }

        reply(pipe.fileHandleForReading.readDataToEndOfFile())
    }

    func deletePlistFile(atPath path: String, withReply reply: @escaping (Bool, String?) -> Void) {
        guard path.hasSuffix(".plist") else {
            reply(false, "Path must end with .plist")
            return
        }

        let allowedPrefixes = ["/Library/LaunchDaemons/", "/Library/LaunchAgents/"]
        guard allowedPrefixes.contains(where: { path.hasPrefix($0) }) else {
            reply(false, "Path must be under /Library/LaunchDaemons/ or /Library/LaunchAgents/")
            return
        }

        guard path == (path as NSString).standardizingPath else {
            reply(false, "Path must not contain relative components")
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            reply(false, "File does not exist at path")
            return
        }

        do {
            try FileManager.default.removeItem(atPath: path)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    private func runLaunchctl(arguments: [String]) -> (Bool, String?) {
        let task = Process()
        let errorPipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            return (false, error.localizedDescription)
        }

        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (false, message?.isEmpty == false ? message : "launchctl failed")
        }

        return (true, nil)
    }
}

let listener = NSXPCListener(machServiceName: "com.bilalbayram.ATIL.Helper")
let delegate = HelperDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
