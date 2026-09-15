import SwiftUI

struct ContentView: View {
    @StateObject private var model = RSLibViewModel()
    @State private var menuIsOpen = false

    var body: some View {
        ZStack(alignment: .leading) {
            Group {
                if model.isAuthenticated { decksScreen } else { signInScreen }
            }
            .offset(x: menuIsOpen ? 286 : 0)
            .disabled(menuIsOpen)

            if menuIsOpen {
                Color.black.opacity(0.28).ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { menuIsOpen = false } }
                    .offset(x: 286)
            }
            if model.isAuthenticated { sideMenu.offset(x: menuIsOpen ? 0 : -286) }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: menuIsOpen)
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
                    List(model.decks) { deck in
                        NavigationLink {
                            ReviewerView(model: model, deck: deck)
                        } label: {
                            Label(deck.name, systemImage: "rectangle.stack.fill")
                                .foregroundStyle(Color.indigo).font(.body.weight(.medium))
                        }
                    }
                    .listStyle(.plain).refreshable { await model.sync() }
                }
            }
            .navigationTitle("My decks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { menuIsOpen = true } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("Open menu")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.sync() } } label: {
                        if model.isSyncing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }.disabled(model.isSyncing).accessibilityLabel("Sync with AnkiWeb")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
                } else {
                    Text(model.lastSyncedText).font(.footnote).foregroundStyle(.secondary).padding(.vertical, 10)
                }
            }
        }
    }

    private var signInScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.indigo)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your decks,\neverywhere.")
                            .font(.title.bold())
                        Text("Sign in to AnkiWeb to bring your collection into Manki.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        TextField("AnkiWeb email", text: $model.username)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $model.password)
                            .textContentType(.password)
                    }
                    .textFieldStyle(.roundedBorder)

                    Button { Task { await model.signIn() } } label: {
                        HStack { Spacer(); if model.isSyncing { ProgressView().tint(.white) } else { Text("Sign in and sync") }; Spacer() }
                            .fontWeight(.semibold)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSignIn || model.isSyncing)

                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                    }
                    Text("Your credentials are stored only in your iPhone Keychain. Manki uses Anki’s official sync engine to connect to AnkiWeb.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: 440, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Manki")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var sideMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "rectangle.stack.fill").font(.title).foregroundStyle(.indigo)
                Text("Manki").font(.title2.bold())
                Text(model.username).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DECKS").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.top, 20)
                    ForEach(model.decks) { deck in
                        Button { menuIsOpen = false } label: {
                            Label(deck.name, systemImage: "rectangle.stack").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 11)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Divider()
            Button(role: .destructive) { menuIsOpen = false; model.logout() } label: {
                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
        }.frame(width: 286).frame(maxHeight: .infinity).background(.background).shadow(color: .black.opacity(0.2), radius: 12, x: 5)
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
