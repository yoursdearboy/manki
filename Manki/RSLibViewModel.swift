import Foundation

@MainActor
final class RSLibViewModel: ObservableObject {
    @Published private(set) var isStarting = false
    @Published private(set) var result: EngineResult?
    private var backend: AnkiRSLibBackend?

    func startEngine() {
        isStarting = true
        result = nil
        defer { isStarting = false }

        do {
            backend = try AnkiRSLibBackend()
            result = .success(
                "Anki rslib is running",
                details: "The native Anki backend initialized successfully. Collection and sync requests are dispatched as Anki protobuf RPCs."
            )
        } catch {
            result = .failure(error.localizedDescription)
        }
    }
}

struct EngineResult {
    let isSuccess: Bool
    let message: String
    let details: String?

    var symbolName: String { isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill" }

    static func success(_ message: String, details: String?) -> EngineResult {
        .init(isSuccess: true, message: message, details: details)
    }

    static func failure(_ message: String) -> EngineResult {
        .init(isSuccess: false, message: message, details: nil)
    }
}
