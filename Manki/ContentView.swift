import SwiftUI

struct ContentView: View {
    @StateObject private var model = RSLibViewModel()

    var body: some View {
        Group {
            if model.isAuthenticated { decksScreen } else { signInScreen }
        }
        .task { await model.restoreSession() }
    }

    private var decksScreen: some View {
        NavigationStack {
            Group {
                if model.isSyncing && model.decks.isEmpty {
                    ProgressView("Syncing your collection…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.decks.isEmpty {
                    ContentUnavailableView("No decks yet", systemImage: "rectangle.stack.badge.plus", description: Text("Create a deck in Anki, then sync again."))
                } else {
                    List {
                        Section {
                            ForEach(model.decks) { deck in
                                NavigationLink {
                                    ReviewerView(model: model, deck: deck)
                                } label: {
                                    Label(deck.name, systemImage: "rectangle.stack.fill")
                                }
                            }
                        } footer: {
                            Text(model.lastSyncedText)
                        }
                    }
                    .refreshable { await model.sync() }
                }
            }
            .navigationTitle("My Decks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            model.logout()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Deck actions")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.sync() } } label: {
                        if model.isSyncing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }.disabled(model.isSyncing).accessibilityLabel("Sync with AnkiWeb")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
                }
            }
        }
    }

    private var signInScreen: some View {
        NavigationStack {
            Form {
                Section("AnkiWeb") {
                        TextField("AnkiWeb email", text: $model.username)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $model.password)
                            .textContentType(.password)
                }

                Section {
                    Button("Sign In and Sync") { Task { await model.signIn() } }
                        .disabled(!model.canSignIn || model.isSyncing)
                }

                if model.isSyncing {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Syncing your collection…")
                        }
                    }
                }

                Section {
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                    }
                    Text("Your credentials are stored only in your iPhone Keychain. Manki uses Anki’s official sync engine to connect to AnkiWeb.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Manki")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct ReviewerView: View {
    @ObservedObject var model: RSLibViewModel
    let deck: Deck
    @State private var showingAnswer = false
    @State private var shownAt = Date.now

    var body: some View {
        VStack(spacing: 20) {
            if model.isReviewLoading && model.reviewCard == nil {
                ProgressView("Finding your next card…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let card = model.reviewCard {
                VStack(spacing: 16) {
                    Text(showingAnswer ? "Answer" : "Question")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            CardText(html: card.question)
                            if showingAnswer {
                                Divider()
                                CardText(html: card.answer)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .onTapGesture {
                    if !showingAnswer { showingAnswer = true }
                }

                if showingAnswer {
                    HStack(spacing: 8) {
                        ForEach(CardRating.allCases) { rating in
                            Button(rating.title) {
                                Task {
                                    await model.answer(card, in: deck, rating: rating, elapsed: Date.now.timeIntervalSince(shownAt))
                                    showingAnswer = false
                                    shownAt = .now
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(color(for: rating))
                            .frame(maxWidth: .infinity)
                            .disabled(model.isReviewLoading)
                        }
                    }
                } else {
                    Text("Tap the card to show the answer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("All caught up", systemImage: "checkmark.circle", description: Text("There are no cards scheduled in this deck right now."))
            }
        }
        .padding(20)
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deck.id) {
            showingAnswer = false
            shownAt = .now
            await model.loadNextCard(in: deck)
        }
    }

    private func color(for rating: CardRating) -> Color {
        switch rating {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}

private struct CardText: View {
    let html: String

    var body: some View {
        Text(plainText)
            .font(.title3)
            .textSelection(.enabled)
    }

    private var plainText: String {
        html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
