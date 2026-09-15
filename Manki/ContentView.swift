import SwiftUI

struct ContentView: View {
    @StateObject private var model = RSLibViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        model.startEngine()
                    } label: {
                        if model.isStarting {
                            HStack {
                                ProgressView()
                                Text("Starting Anki engine…")
                            }
                        } else {
                            Text("Start Anki engine")
                        }
                    }
                    .disabled(model.isStarting)
                } footer: {
                    Text("Manki uses Anki’s Rust backend directly. Authentication, collection access, scheduling, and sync must go through its protobuf service API; no AnkiWeb protocol is reimplemented in Swift.")
                }

                if let result = model.result {
                    Section("Result") {
                        Label(result.message, systemImage: result.symbolName)
                            .foregroundStyle(result.isSuccess ? .green : .red)

                        if let details = result.details {
                            Text(details)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Scope") {
                    Label("Official Anki collection backend", systemImage: "checkmark.shield")
                    Label("Protobuf RPC bridge", systemImage: "arrow.left.arrow.right")
                    Label("Native SQLite, scheduler, and sync engine", systemImage: "externaldrive")
                }
            }
            .navigationTitle("Manki")
        }
    }
}

#Preview {
    ContentView()
}
