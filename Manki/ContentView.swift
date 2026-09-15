import SwiftUI

private enum MankiPalette {
    static let sky = Color(red: 0.00, green: 0.64, blue: 0.87)
    static let deepSky = Color(red: 0.00, green: 0.45, blue: 0.70)
    static let ink = Color(red: 0.10, green: 0.15, blue: 0.20)
    static let mist = Color(red: 0.94, green: 0.98, blue: 1.00)
    static let softInk = Color(red: 0.40, green: 0.45, blue: 0.49)
    static let coral = Color(red: 1.00, green: 0.49, blue: 0.34)
    static let violet = Color(red: 0.48, green: 0.37, blue: 0.88)
    static let reviewAgain = Color(red: 0.86, green: 0.28, blue: 0.28)
    static let reviewHard = Color(red: 0.92, green: 0.52, blue: 0.16)
    static let reviewGood = Color(red: 0.10, green: 0.49, blue: 0.78)
    static let reviewEasy = Color(red: 0.20, green: 0.62, blue: 0.38)
}

struct ContentView: View {
    @StateObject private var model = RSLibViewModel()

    var body: some View {
        Group { if model.isAuthenticated { decksScreen } else { signInScreen } }
            .tint(MankiPalette.sky)
            .task { await model.restoreSession() }
    }

    private var decksScreen: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                if model.isSyncing && model.decks.isEmpty {
                    ProgressView("Building your study space…").tint(MankiPalette.sky)
                } else if model.decks.isEmpty {
                    emptyDecks
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            dashboardHeader
                            Text("your decks")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundStyle(MankiPalette.ink)
                                .padding(.horizontal, 24).padding(.top, 8)
                            ForEach(Array(model.decks.enumerated()), id: \.element.id) { index, deck in
                                NavigationLink { ReviewerView(model: model, deck: deck) } label: {
                                    DeckRow(deck: deck, accent: deckAccent(for: index))
                                }
                                .buttonStyle(.plain).padding(.horizontal, 20)
                            }
                            DeckSchedulerLegend()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 2)
                            Text(model.lastSyncedText)
                                .font(.caption.weight(.medium)).foregroundStyle(MankiPalette.softInk)
                                .frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 30)
                        }
                    }
                    .scrollIndicators(.hidden).refreshable { await model.sync() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { MankiWordmark(compact: true) }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { model.logout() }
                    } label: { Image(systemName: "person.crop.circle").font(.title3).foregroundStyle(MankiPalette.ink) }
                    .accessibilityLabel("Account options")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.sync() } } label: {
                        Image(systemName: model.isSyncing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
                            .font(.title3).foregroundStyle(MankiPalette.sky)
                    }.disabled(model.isSyncing).accessibilityLabel("Sync with AnkiWeb")
                }
            }
            .overlay(alignment: .bottom) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 12)
                        .background(.red, in: Capsule()).padding(.bottom, 12)
                }
            }
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("hello, learner").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(MankiPalette.ink)
                Text("Small reviews. Lasting memory.").font(.subheadline.weight(.medium)).foregroundStyle(MankiPalette.softInk)
            }
            Spacer(minLength: 0)
            StudySpark().frame(width: 82, height: 82)
        }.padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 6)
    }

    private var emptyDecks: some View {
        VStack(spacing: 18) {
            StudySpark().frame(width: 126, height: 126)
            Text("your shelf is waiting").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(MankiPalette.ink)
            Text("Create a deck in Anki, then pull down here to sync it into Manki.")
                .foregroundStyle(MankiPalette.softInk).multilineTextAlignment(.center).padding(.horizontal, 38)
        }
    }

    private var signInScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack { MankiWordmark(); Spacer() }.padding(.top, 18).padding(.horizontal, 24)
                ZStack {
                    StudySpark().frame(width: 210, height: 210).rotationEffect(.degrees(-8))
                    FloatingCard(symbol: "brain.head.profile", color: MankiPalette.violet).offset(x: -103, y: 35)
                    FloatingCard(symbol: "checkmark", color: MankiPalette.coral).offset(x: 93, y: -51)
                }.frame(maxWidth: .infinity).padding(.top, 43).padding(.bottom, 35)
                Text("make every review count")
                    .font(.system(size: 39, weight: .heavy, design: .rounded)).foregroundStyle(MankiPalette.ink)
                    .lineSpacing(-4).padding(.horizontal, 24)
                Text("Your clean, focused home for the Anki decks you already love.")
                    .font(.body.weight(.medium)).foregroundStyle(MankiPalette.softInk).padding(.horizontal, 24).padding(.top, 12)
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ANKIWEB EMAIL").fieldLabel()
                        TextField("you@example.com", text: $model.username).emailField().keyboardType(.emailAddress).textContentType(.username)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PASSWORD").fieldLabel()
                        SecureField("Your AnkiWeb password", text: $model.password).emailField().textContentType(.password)
                    }
                    Button("CONNECT & SYNC") { Task { await model.signIn() } }
                        .buttonStyle(MankiPrimaryButton()).disabled(!model.canSignIn || model.isSyncing)
                    if model.isSyncing {
                        HStack(spacing: 10) { ProgressView().tint(MankiPalette.sky); Text("Bringing your decks home…") }
                            .font(.footnote.weight(.semibold)).foregroundStyle(MankiPalette.softInk)
                    }
                    if let error = model.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red) }
                }.padding(.horizontal, 24).padding(.top, 32)
                Text("Manki stores your login only in your iPhone Keychain and uses Anki’s official sync engine.")
                    .font(.footnote).foregroundStyle(MankiPalette.softInk).multilineTextAlignment(.center)
                    .padding(.horizontal, 38).padding(.top, 24).padding(.bottom, 32)
            }
        }.background(Color.white)
    }

    private func deckAccent(for index: Int) -> Color {
        [MankiPalette.sky, MankiPalette.violet, MankiPalette.coral, Color(red: 0.15, green: 0.70, blue: 0.48)][index % 4]
    }
}

private struct DeckRow: View {
    let deck: Deck; let accent: Color
    var body: some View {
        HStack(spacing: 16) {
            ZStack { RoundedRectangle(cornerRadius: 17, style: .continuous).fill(accent.opacity(0.14)); Image(systemName: "rectangle.stack.fill").font(.title3.weight(.bold)).foregroundStyle(accent) }
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 8) {
                Text(deck.name).font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(MankiPalette.ink).lineLimit(2)
                HStack(spacing: 8) {
                    DeckSchedulerCount(deck.newCount, color: MankiPalette.sky)
                    DeckSchedulerCount(deck.learnCount, color: MankiPalette.coral)
                    DeckSchedulerCount(deck.dueCount, color: .green)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(accent)
        }.padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(MankiPalette.ink.opacity(0.10), lineWidth: 1.5) }
    }
}

private struct DeckSchedulerCount: View {
    let value: Int
    let color: Color

    init(_ value: Int, color: Color) {
        self.value = value
        self.color = color
    }

    var body: some View {
        Text(value, format: .number)
            .font(.caption.weight(.heavy))
            .foregroundStyle(value == 0 ? MankiPalette.softInk.opacity(0.55) : color)
            .frame(width: 32)
            .monospacedDigit()
            .accessibilityLabel("\(value) \(value == 1 ? "card" : "cards")")
    }
}

private struct DeckSchedulerLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("New").foregroundStyle(MankiPalette.sky)
            Text("Learn").foregroundStyle(MankiPalette.coral)
            Text("Due").foregroundStyle(.green)
        }
        .font(.caption2.weight(.heavy))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Deck counts: New, Learn, Due")
    }
}

private struct ReviewerView: View {
    @ObservedObject var model: RSLibViewModel
    let deck: Deck
    @State private var showingAnswer = false
    @State private var shownAt = Date.now

    var body: some View {
        ZStack {
            MankiPalette.mist.ignoresSafeArea()
            VStack(spacing: 18) {
                Text(deck.name).font(.caption.weight(.bold)).foregroundStyle(MankiPalette.deepSky).textCase(.uppercase).tracking(1.2).lineLimit(1)
                if model.isReviewLoading && model.reviewCard == nil {
                    ProgressView("Finding your next card…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let card = model.reviewCard {
                    reviewContent(card)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "party.popper.fill").font(.system(size: 52)).foregroundStyle(MankiPalette.coral)
                        Text("all caught up").font(.system(size: 30, weight: .heavy, design: .rounded))
                        Text("There are no cards scheduled right now.").foregroundStyle(MankiPalette.softInk)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.padding(20)
        }.navigationBarTitleDisplayMode(.inline)
            .task(id: deck.id) { showingAnswer = false; shownAt = .now; await model.loadNextCard(in: deck) }
    }

    @ViewBuilder private func reviewContent(_ card: ReviewCard) -> some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                Text("question").font(.caption.weight(.bold)).foregroundStyle(MankiPalette.sky).textCase(.uppercase).tracking(1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        CardText(html: card.question)
                        if showingAnswer {
                            Rectangle().fill(MankiPalette.sky.opacity(0.18)).frame(height: 1)
                            Text("answer").font(.caption.weight(.bold)).foregroundStyle(MankiPalette.sky).textCase(.uppercase).tracking(1)
                            CardText(html: card.answer.answerBody)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(MankiPalette.sky.opacity(0.18), lineWidth: 1.5) }
                .onTapGesture { if !showingAnswer { showingAnswer = true } }
            if showingAnswer {
                HStack(spacing: 8) {
                    ForEach(CardRating.allCases) { rating in
                        Button(rating.title) {
                            Task { await model.answer(card, in: deck, rating: rating, elapsed: Date.now.timeIntervalSince(shownAt)); showingAnswer = false; shownAt = .now }
                        }.buttonStyle(ReviewRatingButton(color: color(for: rating))).disabled(model.isReviewLoading)
                    }
                }
            } else { Button("SHOW ANSWER") { showingAnswer = true }.buttonStyle(MankiPrimaryButton()) }
        }
    }

    private func color(for rating: CardRating) -> Color {
        switch rating {
        case .again: MankiPalette.reviewAgain
        case .hard: MankiPalette.reviewHard
        case .good: MankiPalette.reviewGood
        case .easy: MankiPalette.reviewEasy
        }
    }
}

private struct CardText: View {
    let html: String
    var body: some View { Text(plainText).font(.system(size: 21, weight: .regular, design: .rounded)).foregroundStyle(MankiPalette.ink).textSelection(.enabled) }
    private var plainText: String {
        html.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br/>", with: "\n").replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    /// Anki's default answer template repeats `{{FrontSide}}` before an
    /// `<hr id=answer>` separator. The question is already displayed above,
    /// so reveal only the content after that separator.
    var answerBody: String {
        let separator = #"<hr\b[^>]*\bid\s*=\s*(?:\"answer\"|'answer'|answer)[^>]*>"#
        guard let range = range(of: separator, options: [.regularExpression, .caseInsensitive]) else {
            return self
        }
        return String(self[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MankiWordmark: View {
    var compact = false
    var body: some View {
        HStack(spacing: 8) { MankiMark().frame(width: compact ? 24 : 31, height: compact ? 24 : 31); Text("manki").font(.system(size: compact ? 20 : 25, weight: .heavy, design: .rounded)).foregroundStyle(MankiPalette.ink) }
    }
}

private struct MankiMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(MankiPalette.sky)
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white).frame(width: 16, height: 19).rotationEffect(.degrees(-10))
            Circle().fill(MankiPalette.coral).frame(width: 6, height: 6).offset(x: 7, y: -8)
        }
    }
}

private struct StudySpark: View {
    var body: some View {
        ZStack {
            Circle().fill(MankiPalette.sky.opacity(0.16))
            Circle().fill(MankiPalette.sky.opacity(0.22)).frame(width: 76, height: 76).offset(x: 22, y: -26)
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(MankiPalette.sky).frame(width: 104, height: 128).rotationEffect(.degrees(10))
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white).frame(width: 74, height: 88).rotationEffect(.degrees(10))
            Image(systemName: "sparkles").font(.system(size: 35, weight: .bold)).foregroundStyle(MankiPalette.coral).offset(x: 6, y: 2)
        }
    }
}

private struct FloatingCard: View {
    let symbol: String; let color: Color
    var body: some View {
        Image(systemName: symbol).font(.title3.weight(.bold)).foregroundStyle(.white).frame(width: 48, height: 48)
            .background(color, in: RoundedRectangle(cornerRadius: 15, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 15).stroke(.white, lineWidth: 3) }
    }
}

private struct MankiPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.heavy)).tracking(0.8).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 54)
            .background(configuration.isPressed ? MankiPalette.deepSky : MankiPalette.sky, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 17, style: .continuous).fill(MankiPalette.deepSky).frame(height: 4).allowsHitTesting(false) }
            .scaleEffect(configuration.isPressed ? 0.98 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ReviewRatingButton: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption.weight(.heavy)).foregroundStyle(color).frame(maxWidth: .infinity).frame(height: 48)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.32), lineWidth: 1.5) }
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private extension View {
    func fieldLabel() -> some View { font(.caption2.weight(.heavy)).foregroundStyle(MankiPalette.softInk).tracking(0.9) }
    func emailField() -> some View {
        self.textInputAutocapitalization(.never).autocorrectionDisabled().padding(.horizontal, 16).frame(height: 54)
            .background(MankiPalette.mist, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MankiPalette.sky.opacity(0.20), lineWidth: 1.5) }
    }
}
