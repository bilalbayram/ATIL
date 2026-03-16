import Foundation

struct LaunchdDisabledStateReader: Sendable {
    typealias CommandRunner = @Sendable ([String]) -> String?

    private let commandRunner: CommandRunner

    init(commandRunner: @escaping CommandRunner = LaunchdDisabledStateReader.runLaunchctl) {
        self.commandRunner = commandRunner
    }

    func readDisabledStates() -> [String: [String: Bool]] {
        let domains = [
            "gui/\(getuid())",
            "system",
        ]

        var states: [String: [String: Bool]] = [:]
        for domain in domains {
            guard let output = commandRunner(["print-disabled", domain]) else { continue }
            states[domain] = Self.parse(output)
        }
        return states
    }

    static func parse(_ output: String) -> [String: Bool] {
        var states: [String: Bool] = [:]

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("\""),
                  let arrowRange = line.range(of: "\" => ")
            else { continue }

            let label = String(line[line.index(after: line.startIndex)..<arrowRange.lowerBound])
            let stateValue = line[arrowRange.upperBound...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))

            switch stateValue {
            case "disabled":
                states[label] = true
            case "enabled":
                states[label] = false
            default:
                continue
            }
        }

        return states
    }

    private static func runLaunchctl(arguments: [String]) -> String? {
        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            return nil
        }

        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
