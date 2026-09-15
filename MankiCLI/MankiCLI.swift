import Darwin
import Foundation
import MankiAnkiRust

@main
struct MankiCLI {
    static func main() {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            let username = try options.username ?? readLine(prompt: "AnkiWeb username or email: ")
            let password = try readPassword(prompt: "AnkiWeb password: ")
            let data = try callRSLib(options: options, username: username, password: password)
            try printDecks(data)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func callRSLib(options: Options, username: String, password: String) throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        let status = options.collection.path.withCString { collection in
            options.endpoint.withCString { endpoint in
                username.withCString { username in
                    password.withCString { password in
                        manki_anki_fetch_decks(collection, endpoint, username, password, &output, &outputLength)
                    }
                }
            }
        }
        defer { if let output { manki_anki_free_response(output, outputLength) } }
        let data = output.map { Data(bytes: $0, count: outputLength) } ?? Data()
        guard status == 0 else {
            throw CLIError.backend(String(data: data, encoding: .utf8) ?? "Anki rslib failed (status \(status)).")
        }
        return data
    }

    private static func printDecks(_ data: Data) throws {
        guard let decks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CLIError.backend("Anki rslib returned invalid deck JSON.")
        }
        for deck in decks {
            print("\(deck["id"].map(String.init(describing:)) ?? "?")\t\(deck["name"] as? String ?? "")")
        }
    }

    private static func readLine(prompt: String) throws -> String {
        print(prompt, terminator: "")
        guard let value = Swift.readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw CLIError.missingValue
        }
        return value
    }

    private static func readPassword(prompt: String) throws -> String {
        print(prompt, terminator: "")
        fflush(stdout)
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw CLIError.password }
        var hidden = original
        hidden.c_lflag &= ~tcflag_t(ECHO)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &hidden) == 0 else { throw CLIError.password }
        defer { _ = tcsetattr(STDIN_FILENO, TCSANOW, &original); print() }
        guard let password = Swift.readLine(), !password.isEmpty else { throw CLIError.missingValue }
        return password
    }
}

private struct Options {
    var username: String?
    var endpoint = "https://sync.ankiweb.net"
    var collection = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Manki/collection.anki2")

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            if option == "--help" || option == "-h" { throw CLIError.usage }
            index += 1
            guard index < arguments.count else { throw CLIError.optionValue(option) }
            let value = arguments[index]
            switch option {
            case "--username": username = value
            case "--endpoint": endpoint = value
            case "--collection": collection = URL(filePath: value)
            default: throw CLIError.option(option)
            }
            index += 1
        }
    }
}

private enum CLIError: LocalizedError {
    case usage, missingValue, password, option(String), optionValue(String), backend(String)
    var errorDescription: String? {
        switch self {
        case .usage: return "Usage: manki-anki-cli [--username USER] [--endpoint URL] [--collection PATH]\n\nFetches decks through the shared MankiAnkiRust rslib framework. It refuses full uploads and full-sync conflicts; normal sync follows Anki's bidirectional semantics."
        case .missingValue: return "A non-empty value is required."
        case .password: return "Could not hide password input."
        case let .option(value): return "Unknown option: \(value)"
        case let .optionValue(value): return "\(value) requires a value."
        case let .backend(message): return message
        }
    }
}
