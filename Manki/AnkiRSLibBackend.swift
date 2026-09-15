import Foundation
import MankiAnkiRust

/// Thread-safe owner of an Anki `rslib` backend handle.
///
/// The bridge deliberately transports only protobuf bytes. Higher-level
/// collection, scheduler, and sync features must use rslib's generated
/// service contracts rather than recreating them in Swift.
final class AnkiRSLibBackend {
    private let handle: Int64
    private let lock = NSLock()

    init() throws {
        var rawHandle: Int64 = 0
        let status = manki_anki_open_backend(nil, 0, &rawHandle)
        guard status == 0, rawHandle != 0 else {
            throw AnkiRSLibError.initializationFailed(status)
        }
        handle = rawHandle
    }

    deinit {
        manki_anki_close_backend(handle)
    }

    /// Dispatches one serialized request to Anki's backend.
    func run(service: UInt32, method: UInt32, request: Data = Data()) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        var responsePointer: UnsafeMutablePointer<UInt8>?
        var responseLength = 0
        let status = request.withUnsafeBytes { bytes in
            manki_anki_run_method(
                handle,
                service,
                method,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytes.count,
                &responsePointer,
                &responseLength
            )
        }
        defer {
            if let responsePointer {
                manki_anki_free_response(responsePointer, responseLength)
            }
        }

        let response = responsePointer.map { Data(bytes: $0, count: responseLength) } ?? Data()
        switch status {
        case 0:
            return response
        case 1:
            throw AnkiRSLibError.backend(response)
        default:
            throw AnkiRSLibError.bridgeFailed(status)
        }
    }
}

enum AnkiRSLibError: LocalizedError {
    case initializationFailed(Int32)
    case bridgeFailed(Int32)
    case backend(Data)

    var errorDescription: String? {
        switch self {
        case let .initializationFailed(status):
            return "Could not initialize Anki rslib (status \(status))."
        case let .bridgeFailed(status):
            return "Anki rslib bridge failed (status \(status))."
        case .backend:
            return "Anki rslib rejected the request. Decode the returned BackendError protobuf for details."
        }
    }
}
