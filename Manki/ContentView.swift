import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var model = RSLibViewModel()
    @State private var decks = Deck.sampleDecks
    @State private var lastSyncDate = Date()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(decks) { deck in
                        NavigationLink(value: deck) {
                            Label(deck.name, systemImage: "rectangle.stack.fill")
                        }
                    }
                    .onDelete(perform: deleteDecks)
                } footer: {
                    Text("Last synced \(lastSyncDate.formatted(date: .abbreviated, time: .shortened))")
                }

                if let result = model.result, !result.isSuccess {
                    Section("Anki Engine") {
                        Label(result.message, systemImage: result.symbolName)
                            .foregroundStyle(.red)

                        if let details = result.details {
                            Text(details)
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("My Decks")
            .navigationDestination(for: Deck.self) { deck in
                DeckDetailView(deck: deck)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("New Deck", systemImage: "plus") {
                            addDeck()
                        }

                        Button("Start Anki Engine", systemImage: "bolt.fill") {
                            model.startEngine()
                        }
                        .disabled(model.isStarting)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Deck actions")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sync()
                    } label: {
                        if model.isStarting {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isStarting)
                    .accessibilityLabel("Sync")
                }
            }
            .refreshable {
                sync()
            }
        }
    }

    private func addDeck() {
        decks.append(Deck(name: "New Deck"))
    }

    private func deleteDecks(at offsets: IndexSet) {
        decks.remove(atOffsets: offsets)
    }

    private func sync() {
        model.startEngine()
        lastSyncDate = .now
    }
}

private struct Deck: Identifiable, Hashable {
    let id = UUID()
    let name: String

    static let sampleDecks = [
        Deck(name: "Default"),
        Deck(name: "Genetics"),
        Deck(name: "Немецкий для начинающих — слова")
    ]
}

private struct DeckDetailView: View {
    let deck: Deck

    var body: some View {
        ContentUnavailableView(
            deck.name,
            systemImage: "rectangle.stack",
            description: Text("Cards for this deck will appear here.")
        )
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
}
