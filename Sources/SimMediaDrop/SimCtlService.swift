import Foundation

struct Simulator: Identifiable, Hashable {
    let udid: String
    let name: String
    let state: String
    let runtime: String

    var id: String { udid }

    var isBooted: Bool {
        state.caseInsensitiveCompare("Booted") == .orderedSame
    }

    var displayRuntime: String {
        runtime
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}

enum SimCtlError: LocalizedError {
    case commandFailed(String)
    case noSimulatorsSelected
    case noMediaSelected
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .noSimulatorsSelected:
            return "Select at least one simulator."
        case .noMediaSelected:
            return "Drop or choose at least one media file."
        case .parseFailed:
            return "Could not parse simulator list from simctl."
        }
    }
}

enum SimCtlService {
    private static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tif", "tiff", "webp",
        "mov", "mp4", "m4v", "avi", "mkv",
        "vcf"
    ]

    static func isSupportedMedia(_ url: URL) -> Bool {
        mediaExtensions.contains(url.pathExtension.lowercased())
    }

    static func listDevices() async throws -> [Simulator] {
        let output = try await run(arguments: ["simctl", "list", "devices", "-j"])
        guard let data = output.data(using: .utf8) else {
            throw SimCtlError.parseFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let devicesByRuntime = json?["devices"] as? [String: Any] ?? [:]

        var results: [Simulator] = []

        for (runtime, value) in devicesByRuntime {
            guard let devices = value as? [[String: Any]] else { continue }
            for device in devices {
                let isAvailable = device["isAvailable"] as? Bool ?? true
                guard isAvailable else { continue }
                guard
                    let udid = device["udid"] as? String,
                    let name = device["name"] as? String,
                    let state = device["state"] as? String
                else { continue }

                results.append(
                    Simulator(
                        udid: udid,
                        name: name,
                        state: state,
                        runtime: runtime
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.isBooted != rhs.isBooted {
                return lhs.isBooted && !rhs.isBooted
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func addMedia(paths: [URL], to simulators: [Simulator]) async throws -> String {
        guard !paths.isEmpty else { throw SimCtlError.noMediaSelected }
        guard !simulators.isEmpty else { throw SimCtlError.noSimulatorsSelected }

        var lines: [String] = []

        for simulator in simulators {
            let args = ["simctl", "addmedia", simulator.udid] + paths.map(\.path)
            _ = try await run(arguments: args)
            let names = paths.map(\.lastPathComponent).joined(separator: ", ")
            lines.append("✓ \(simulator.name): \(names)")
        }

        return lines.joined(separator: "\n")
    }

    @discardableResult
    private static func run(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = arguments

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let out = String(data: outData, encoding: .utf8) ?? ""
                    let err = String(data: errData, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: out)
                    } else {
                        let message = err.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(
                            throwing: SimCtlError.commandFailed(
                                message.isEmpty
                                    ? "xcrun \(arguments.joined(separator: " ")) failed (\(process.terminationStatus))"
                                    : message
                            )
                        )
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
