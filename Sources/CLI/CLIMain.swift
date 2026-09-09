import ConsolepilotCore
import Darwin
import Foundation

@main
struct ConsolepilotCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first, command != "--help", command != "-h" else {
            printUsage()
            return
        }
        switch command {
        case "ask":
            let prompt = arguments.dropFirst().joined(separator: " ")
            guard !prompt.isEmpty else {
                output("用法：consolepilot ask <prompt>")
                return
            }
            send(path: "/ask", body: Data("{\"prompt\":\(json(prompt))}".utf8))
        case "open":
            if !send(path: "/open", body: Data("{}".utf8)) { openApplication() }
        case "run":
            guard let action = arguments.dropFirst().first, !action.isEmpty else {
                output("用法：consolepilot run <actionId>")
                return
            }
            let input = arguments.dropFirst(2).joined(separator: " ")
            let inputField = input.isEmpty ? "" : ",\"input\":\(json(input))"
            send(path: "/run", body: Data("{\"actionId\":\(json(action))\(inputField)}".utf8))
        case "tail":
            guard let path = arguments.dropFirst().first, !path.isEmpty else {
                output("用法：consolepilot tail <file>")
                return
            }
            send(path: "/tail", body: Data("{\"path\":\(json(path))}".utf8))
        default:
            output("未知命令：\(command)")
            printUsage()
        }
    }

    private static func printUsage() {
        output("用法：consolepilot <ask|open|run|tail> [options]")
        output("  ask <prompt>       发送一次提问")
        output("  open               唤回 Consolepilot 窗口")
        output("  run <actionId>     执行配置中的 action")
        output("  tail <file>        尾随文件并推送到控制台")
    }

    private static func openApplication() {
        let candidates = [
            "/Applications/Consolepilot.app",
            FileManager.default.currentDirectoryPath + "/dist/Consolepilot.app",
        ]
        guard let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            fputs("未找到 Consolepilot.app，请先运行 make build\n", stderr)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [app]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                output("Consolepilot 窗口唤回请求已发送")
            } else {
                fputs("无法打开 Consolepilot.app（退出码 \(process.terminationStatus)）\n", stderr)
            }
        } catch {
            fputs("无法打开 Consolepilot.app：\(error)\n", stderr)
        }
    }

    @discardableResult
    private static func send(path: String, body: Data) -> Bool {
        let token =
            (try? LocalServerClientConfiguration.resolveToken())
            ?? ProcessInfo.processInfo.environment["CONSOLEPILOT_SERVER_TOKEN"] ?? ""
        guard !token.isEmpty else {
            fputs("未设置 CONSOLEPILOT_SERVER_TOKEN；请先配置本地服务 token\n", stderr)
            return false
        }
        let port = ProcessInfo.processInfo.environment["CONSOLEPILOT_SERVER_PORT"] ?? "8765"
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let semaphore = DispatchSemaphore(value: 0)
        let result = ResponseBox()
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let response { result.set((data, response)) }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        guard let response = result.value, let http = response.1 as? HTTPURLResponse else { return false }
        if http.statusCode == 200 || http.statusCode == 202 {
            output(String(data: response.0, encoding: .utf8) ?? "")
            return true
        }
        fputs("LocalServer HTTP \(http.statusCode): \(String(data: response.0, encoding: .utf8) ?? "")\n", stderr)
        return false
    }

    /// CLI 面向用户的正常输出（规范允许的用户输出路径，不走 Log）。
    private static func output(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    private static func json(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
            let text = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return text
    }

    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: (Data, URLResponse)?

        var value: (Data, URLResponse)? {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func set(_ value: (Data, URLResponse)) {
            lock.lock()
            defer { lock.unlock() }
            storage = value
        }
    }

}
