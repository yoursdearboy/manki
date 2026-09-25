import AVFoundation
import SwiftUI

private enum MankiPalette {
    static let sky = Color(red: 0.00, green: 0.64, blue: 0.87)
    static let deepSky = Color(red: 0.00, green: 0.45, blue: 0.70)
    static let ink = Color.primary
    static let softInk = Color.secondary
    static let canvas = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let mist = Color(uiColor: .systemGroupedBackground)
    static let field = Color(uiColor: .tertiarySystemFill)
    static let coral = Color(red: 1.00, green: 0.49, blue: 0.34)
    static let violet = Color(red: 0.48, green: 0.37, blue: 0.88)
    static let reviewAgain = Color(red: 0.86, green: 0.28, blue: 0.28)
    static let reviewHard = Color(red: 0.92, green: 0.52, blue: 0.16)
    static let reviewGood = Color(red: 0.10, green: 0.49, blue: 0.78)
    static let reviewEasy = Color(red: 0.20, green: 0.62, blue: 0.38)
}

private extension CardFlag {
    var color: Color {
        switch self {
        case .none: return .secondary
        case .red: return Color(red: 1.00, green: 0.44, blue: 0.44)
        case .orange: return Color(red: 1.00, green: 0.73, blue: 0.45)
        case .green: return Color(red: 0.47, green: 0.93, blue: 0.68)
        case .blue: return Color(red: 0.33, green: 0.66, blue: 0.98)
        case .pink: return Color(red: 0.96, green: 0.68, blue: 0.99)
        case .turquoise: return Color(red: 0.26, green: 0.92, blue: 0.84)
        case .purple: return Color(red: 0.76, green: 0.54, blue: 0.99)
        }
    }

    var systemImage: String { self == .none ? "flag.slash" : "flag.fill" }
}

enum CardEditorMode: Identifiable {
    case add(deckID: Int64)
    case edit(cardID: Int64, initialFront: String, initialBack: String)

    var id: String {
        switch self {
        case let .add(deckID): return "add-\(deckID)"
        case let .edit(cardID, _, _): return "edit-\(cardID)"
        }
    }

    var title: String {
        switch self {
        case .add: return "Add Card"
        case .edit: return "Edit Card"
        }
    }
}

struct CardEditorSheet: View {
    let mode: CardEditorMode
    @ObservedObject var model: RSLibViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var front: String = ""
    @State private var back: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: CardEditorMode, model: RSLibViewModel) {
        self.mode = mode
        self.model = model
        if case let .edit(_, initialFront, initialBack) = mode {
            _front = State(initialValue: initialFront)
            _back = State(initialValue: initialBack)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("FRONT") {
                    TextField("Question / Front text", text: $front, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("card-editor-front")
                }
                Section("BACK") {
                    TextField("Answer / Back text", text: $back, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("card-editor-back")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            switch mode {
            case let .add(deckID):
                try await model.addCard(deckID: deckID, front: front, back: back)
            case let .edit(cardID, _, _):
                try await model.updateCurrentCard(cardID: cardID, front: front, back: back)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

struct ContentView: View {
    @StateObject private var model: RSLibViewModel
    @StateObject private var notifications = NotificationSettings()
    private let fixture: UITestFixture?
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var notificationRouter: NotificationRouter
    @State private var deckPath: [Int64] = []

    init() {
        let fixture = UITestFixture.current
        self.fixture = fixture
        _model = StateObject(wrappedValue: RSLibViewModel(fixture: fixture))
    }

    var body: some View {
        Group {
            switch fixture {
            case .reviewQuestion, .redFlagCard:
                NavigationStack { ReviewerView(model: model, deck: RSLibViewModel.fixtureDecks[0], notifications: notifications) }
            case .reviewAnswer:
                NavigationStack { ReviewerView(model: model, deck: RSLibViewModel.fixtureDecks[0], notifications: notifications, initiallyShowingAnswer: true) }
            case .allCaughtUp:
                NavigationStack { ReviewerView(model: model, deck: RSLibViewModel.fixtureDecks[0], notifications: notifications) }
            default:
                if model.isAuthenticated { decksScreen } else { signInScreen }
            }
        }
            .tint(MankiPalette.sky)
            .task { await model.restoreSession() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(300))
                    guard !Task.isCancelled else { return }
                    await model.periodicSync()
                }
            }
            .onChange(of: model.decks, initial: true) { _, decks in
                Task { await notifications.updateDecks(decks) }
                openRequestedDeckIfAvailable()
            }
            .onChange(of: notificationRouter.requestedDeckID) { _, deckID in
                guard deckID != nil else { return }
                openRequestedDeckIfAvailable()
            }
            .alert("Choose which collection to keep", isPresented: fullSyncChoiceBinding) {
                Button("Upload to AnkiWeb", role: .destructive) {
                    Task { await model.resolveFullSync(.upload) }
                }
                Button("Download from AnkiWeb", role: .destructive) {
                    Task { await model.resolveFullSync(.download) }
                }
                Button("Cancel", role: .cancel) { model.cancelFullSync() }
            } message: {
                Text("Anki cannot merge these collections. Upload replaces the collection on AnkiWeb. Download replaces the collection on this device.")
            }
    }

    private var fullSyncChoiceBinding: Binding<Bool> {
        Binding(
            get: { model.needsFullSyncChoice },
            set: { if !$0 { model.cancelFullSync() } }
        )
    }

    private var decksScreen: some View {
        NavigationStack(path: $deckPath) {
            ZStack {
                MankiPalette.mist.ignoresSafeArea()
                if model.isSyncing && model.decks.isEmpty {
                    ProgressView("Building your study space…").tint(MankiPalette.sky)
                } else if model.decks.isEmpty {
                    emptyDecks
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            dashboardHeader
                            ForEach(Array(model.decks.enumerated()), id: \.element.id) { index, deck in
                                NavigationLink(value: deck.id) {
                                    DeckRow(deck: deck, accent: deckAccent(for: index))
                                }
                                .contextMenu {
                                    NavigationLink {
                                        DeckSettingsView(model: model, notifications: notifications, deck: deck)
                                    } label: {
                                        Label("Deck settings", systemImage: "slider.horizontal.3")
                                    }
                                }
                                .accessibilityHint("Touch and hold for deck settings")
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
                    .onAppear { Task { await model.deckListDidAppear() } }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int64.self) { deckID in
                if let deck = model.decks.first(where: { $0.id == deckID }) {
                    ReviewerView(model: model, deck: deck, notifications: notifications)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { MankiWordmark(compact: true) }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView(model: model, notifications: notifications)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundStyle(MankiPalette.ink)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens application settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if model.isSyncing {
                            ProgressView().controlSize(.small)
                                .accessibilityLabel("Syncing with AnkiWeb")
                        }
                        Button { Task { await model.sync() } } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.circle")
                                .font(.title3).foregroundStyle(MankiPalette.sky)
                        }.disabled(model.isSyncing).accessibilityLabel("Sync with AnkiWeb")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let error = model.syncErrorMessage {
                    Button { Task { await model.sync() } } label: {
                        Label("\(error) Tap to retry.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 12)
                            .background(.red, in: Capsule()).padding(.bottom, 12)
                    }
                    .accessibilityLabel("Sync failed. Retry sync")
                }
            }
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hello, learner")
                Text("your decks")
            }
            .font(.system(size: 31, weight: .heavy, design: .rounded))
            .foregroundStyle(MankiPalette.ink)
            Spacer(minLength: 0)
            StudySpark().frame(width: 94, height: 94)
        }.padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 20)
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
        }.background(MankiPalette.canvas)
    }

    private func deckAccent(for index: Int) -> Color {
        [MankiPalette.sky, MankiPalette.violet, MankiPalette.coral, Color(red: 0.15, green: 0.70, blue: 0.48)][index % 4]
    }

    private func openRequestedDeckIfAvailable() {
        guard let deckID = notificationRouter.requestedDeckID,
              model.decks.contains(where: { $0.id == deckID }) else { return }
        deckPath = [deckID]
        notificationRouter.requestedDeckID = nil
    }
}

private struct SettingsView: View {
    @ObservedObject var model: RSLibViewModel
    @ObservedObject var notifications: NotificationSettings
    @State private var isConfirmingLogout = false

    var body: some View {
        ZStack {
            MankiPalette.mist.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Manage Manki and your account.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MankiPalette.softInk)

                    SettingsSection(title: "DAILY REMINDERS") {
                        VStack(spacing: 16) {
                            Toggle("Study reminders", isOn: Binding(
                                get: { notifications.isEnabled },
                                set: { enabled in Task { await notifications.setEnabled(enabled) } }
                            ))
                            .font(.system(.body, design: .rounded, weight: .bold))

                            if notifications.permissionDenied {
                                Label("Notifications are disabled in Settings.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(MankiPalette.reviewAgain)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            ForEach(notifications.times) { time in
                                HStack {
                                    DatePicker(
                                        "Reminder time",
                                        selection: Binding(
                                            get: { time.date },
                                            set: { date in Task { await notifications.updateTime(id: time.id, date: date) } }
                                        ),
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                    Spacer()
                                    Button(role: .destructive) {
                                        Task { await notifications.removeTime(id: time.id) }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel("Delete reminder at \(time.date.formatted(date: .omitted, time: .shortened))")
                                }
                            }

                            Button {
                                Task { await notifications.addTime() }
                            } label: {
                                Label("Add reminder", systemImage: "plus.circle.fill")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    BadgeSettingsSection(model: model)

                    SettingsSection(title: "ACCOUNT") {
                        Button(role: .destructive) {
                            isConfirmingLogout = true
                        } label: {
                            HStack(spacing: 15) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.headline.weight(.bold))
                                    .frame(width: 26)
                                Text("Log out")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(MankiPalette.reviewAgain)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Log out of Manki")
                        .accessibilityHint("Asks for confirmation before clearing your AnkiWeb session")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Log out of Manki?",
            isPresented: $isConfirmingLogout,
            titleVisibility: .visible
        ) {
            Button("Log out", role: .destructive) { Task { await model.logout() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved AnkiWeb credentials and local session will be cleared.")
        }
    }
}

private struct BadgeSettingsSection: View {
    @ObservedObject var model: RSLibViewModel
    @State private var includeNew = BadgePreferences().includesNew
    @State private var includeLearn = BadgePreferences().includesLearn
    @State private var includeDue = BadgePreferences().includesDue

    var body: some View {
        SettingsSection(title: "APP ICON COUNT") {
            VStack(spacing: 16) {
                Toggle("New cards", isOn: binding(\.includesNew, value: $includeNew))
                Toggle("Learning cards", isOn: binding(\.includesLearn, value: $includeLearn))
                Toggle("Due cards", isOn: binding(\.includesDue, value: $includeDue))
            }
            .font(.system(.body, design: .rounded, weight: .bold))
        }
    }

    private func binding(_ keyPath: WritableKeyPath<BadgePreferences, Bool>, value: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue }, set: { enabled in
            value.wrappedValue = enabled
            var preferences = BadgePreferences()
            preferences[keyPath: keyPath] = enabled
            Task { await model.refreshBadge() }
        })
    }
}

private struct DeckSettingsView: View {
    @ObservedObject var model: RSLibViewModel
    @ObservedObject var notifications: NotificationSettings
    let deck: Deck
    @State private var contributesToBadge: Bool
    @State private var sendsReminders: Bool
    @State private var reminderTimes: [DailyNotificationTime]
    @State private var cardHeight: Double

    init(model: RSLibViewModel, notifications: NotificationSettings, deck: Deck) {
        self.model = model
        self.notifications = notifications
        self.deck = deck
        _contributesToBadge = State(initialValue: BadgePreferences().includesDeck(deck.id))
        _sendsReminders = State(initialValue: notifications.isEnabled(for: deck.id))
        _reminderTimes = State(initialValue: notifications.times(for: deck.id))
        _cardHeight = State(initialValue: ReviewCardSettings().height(for: deck.id))
    }

    var body: some View {
        ZStack {
            MankiPalette.mist.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose how this deck contributes to Manki and when it reminds you to study.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MankiPalette.softInk)

                    SettingsSection(title: "APP ICON COUNT") {
                        Toggle("Include this deck in count", isOn: $contributesToBadge)
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .onChange(of: contributesToBadge) { _, included in
                                BadgePreferences().setIncludesDeck(included, deckID: deck.id)
                                Task { await model.refreshBadge() }
                            }
                    }

                    SettingsSection(title: "EXTRA NOTIFICATIONS") {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle("Remind me to study this deck", isOn: $sendsReminders)
                                .font(.system(.body, design: .rounded, weight: .bold))
                                .onChange(of: sendsReminders) { _, enabled in
                                    Task { await notifications.setEnabled(enabled, for: deck.id) }
                                }
                            if sendsReminders {
                                ForEach(reminderTimes) { time in
                                    HStack {
                                        DatePicker(
                                            "Reminder time",
                                            selection: Binding(
                                                get: { time.date },
                                                set: { date in
                                                    Task {
                                                        await notifications.updateTime(id: time.id, date: date, for: deck.id)
                                                        reminderTimes = notifications.times(for: deck.id)
                                                    }
                                                }
                                            ),
                                            displayedComponents: .hourAndMinute
                                        )
                                        .labelsHidden()
                                        Spacer()
                                        Button(role: .destructive) {
                                            Task {
                                                await notifications.removeTime(id: time.id, for: deck.id)
                                                reminderTimes = notifications.times(for: deck.id)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .accessibilityLabel("Delete reminder at \(time.date.formatted(date: .omitted, time: .shortened))")
                                        .accessibilityIdentifier(time.deleteButtonAccessibilityIdentifier)
                                    }
                                }
                                Button {
                                    Task {
                                        await notifications.addTime(for: deck.id)
                                        reminderTimes = notifications.times(for: deck.id)
                                    }
                                } label: {
                                    Label("Add reminder", systemImage: "plus.circle.fill")
                                        .font(.system(.body, design: .rounded, weight: .bold))
                                }
                            }
                            Text("These are additional reminders for this deck, separate from the app-wide reminder schedule.")
                                .font(.footnote)
                                .foregroundStyle(MankiPalette.softInk)
                        }
                    }

                    SettingsSection(title: "REVIEW") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Review card size")
                                .font(.system(.body, design: .rounded, weight: .bold))
                            Slider(value: $cardHeight, in: ReviewCardSettings.heightRange, step: 0.05) {
                                Text("Review card height")
                            } minimumValueLabel: {
                                Text("30%")
                            } maximumValueLabel: {
                                Text("80%")
                            }
                            .onChange(of: cardHeight) { _, height in
                                ReviewCardSettings().setHeight(height, for: deck.id)
                            }
                            Text(cardHeight, format: .percent.precision(.fractionLength(0)))
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(MankiPalette.deepSky)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension DailyNotificationTime {
    var deleteButtonAccessibilityIdentifier: String {
        String(format: "deck-reminder-delete-%02d-%02d", hour, minute)
    }
}

/// A reusable visual container for groups of global settings as the screen grows.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).fieldLabel().padding(.leading, 4)
            content
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MankiPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(MankiPalette.ink.opacity(0.10), lineWidth: 1.5)
                }
        }
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
        }.padding(14).background(MankiPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

private struct DeckStackPosition {
    let rotation: Double
    let xOffset: CGFloat
    let yOffset: CGFloat

    static func makeStack() -> [Self] {
        (0..<5).map { level in
            Self(
                rotation: Double.random(in: -2...2),
                xOffset: CGFloat.random(in: -4...4),
                yOffset: CGFloat(level) * 3 + CGFloat.random(in: -1...1)
            )
        }
    }
}

private extension Array where Element == DeckStackPosition {
    mutating func rotate() {
        guard !isEmpty else { return }
        removeFirst()
        append(DeckStackPosition(
            rotation: Double.random(in: -2...2),
            xOffset: CGFloat.random(in: -4...4),
            yOffset: CGFloat(count) * 3 + CGFloat.random(in: -1...1)
        ))
    }
}

private struct ReviewerView: View {
    @ObservedObject var model: RSLibViewModel
    let deck: Deck
    @ObservedObject var notifications: NotificationSettings
    @State private var showingAnswer: Bool
    @State private var shownAt = Date.now
    @State private var cardOffset = CGSize.zero
    @State private var isSubmittingSwipe = false
    @State private var buttonPreviewRating: CardRating?
    @State private var cardHeight: Double
    @State private var stackPositions = DeckStackPosition.makeStack()
    @StateObject private var audioPlayer = CardAudioPlayer()
    @State private var activeEditorMode: CardEditorMode?
    @State private var isNavigatingToDeckSettings = false

    init(model: RSLibViewModel, deck: Deck, notifications: NotificationSettings = NotificationSettings(), initiallyShowingAnswer: Bool = false) {
        self.model = model
        self.deck = deck
        self.notifications = notifications
        _showingAnswer = State(initialValue: initiallyShowingAnswer)
        _cardHeight = State(initialValue: ReviewCardSettings().height(for: deck.id))
    }

    var body: some View {
        ZStack {
            MankiPalette.mist.ignoresSafeArea()
            VStack(spacing: 30) {
                if model.isSyncing && model.reviewCard == nil {
                    ProgressView("Syncing your collection…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.isReviewLoading && model.reviewCard == nil {
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
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(deck.name)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(MankiPalette.deepSky)
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            activeEditorMode = .add(deckID: deck.id)
                        } label: {
                            Label("Add new card", systemImage: "plus.circle")
                        }

                        if let card = model.reviewCard {
                            Button {
                                Task {
                                    if let fields = try? await model.fetchCurrentNoteFields(cardID: card.id) {
                                        activeEditorMode = .edit(cardID: card.id, initialFront: fields.front, initialBack: fields.back)
                                    } else {
                                        activeEditorMode = .edit(cardID: card.id, initialFront: card.question, initialBack: card.answer)
                                    }
                                }
                            } label: {
                                Label("Edit card", systemImage: "pencil")
                            }

                            Menu {
                                ForEach(CardFlag.allCases) { flag in
                                    Button {
                                        Task { await model.setFlag(flag, on: card) }
                                    } label: {
                                        HStack {
                                            Label {
                                                Text(flag.title)
                                            } icon: {
                                                Image(systemName: flag.systemImage).foregroundStyle(flag.color)
                                            }
                                            if card.flag == flag.rawValue {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                    .tint(flag.color)
                                }
                            } label: {
                                Label("Flag card", systemImage: "flag.fill")
                            }
                        }

                        Button {
                            isNavigatingToDeckSettings = true
                        } label: {
                            Label("Deck settings", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Card actions")
                }
            }
            .navigationDestination(isPresented: $isNavigatingToDeckSettings) {
                DeckSettingsView(model: model, notifications: notifications, deck: deck)
            }
            .sheet(item: $activeEditorMode) { mode in
                CardEditorSheet(mode: mode, model: model)
            }
            .task(id: deck.id) { shownAt = .now; await model.loadNextCard(in: deck) }
            .onChange(of: model.reviewCard?.id, initial: true) { previousCardID, cardID in
                if previousCardID != nil, previousCardID != cardID {
                    showingAnswer = false
                    stackPositions.rotate()
                }
                buttonPreviewRating = nil
                playVisibleAudio()
            }
            .onChange(of: showingAnswer) { _, _ in
                playVisibleAudio()
            }
            .onDisappear {
                audioPlayer.stop()
                Task {
                    await model.stopReviewing(deckID: deck.id)
                    await model.refreshDueCounts()
                }
            }
    }

    @ViewBuilder private func reviewContent(_ card: ReviewCard) -> some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                ZStack {
                ForEach(Array(1..<visibleCardCount), id: \.self) { index in
                    reviewCardBacking(position: stackPositions[index])
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text("question").font(.caption.weight(.bold)).foregroundStyle(MankiPalette.sky).textCase(.uppercase).tracking(1)
                    ViewThatFits(in: .vertical) {
                        fittedCardText(card, size: 21, spacing: 20)
                        fittedCardText(card, size: 18, spacing: 14)
                        fittedCardText(card, size: 15, spacing: 10)
                        fittedCardText(card, size: 12, spacing: 7)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(MankiPalette.canvas, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(activeRating.map { color(for: $0).opacity(0.10) } ?? .clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(activeRating.map(color(for:)) ?? MankiPalette.sky.opacity(0.18), lineWidth: activeRating == nil ? 1.5 : 5)
                }
                .overlay(alignment: .topTrailing) {
                    if let flag = CardFlag(rawValue: card.flag), flag != .none {
                        Image(systemName: flag.systemImage)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(flag.color)
                            .padding(12)
                            .accessibilityLabel("\(flag.title) flag")
                    }
                }
                .shadow(color: activeRating.map { color(for: $0).opacity(0.48) } ?? .clear, radius: 20)
                .offset(x: stackPositions[0].xOffset + cardOffset.width, y: stackPositions[0].yOffset + cardOffset.height)
                .rotationEffect(.degrees(stackPositions[0].rotation + Double(cardOffset.width / 22)))
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .gesture(swipeGesture(for: card))
                .onTapGesture { if !showingAnswer { showingAnswer = true } }
                .accessibilityHint(showingAnswer ? "Swipe down for Again, left for Hard, right for Good, or up for Easy" : "Tap to show the answer")
                }
                .frame(
                    width: isLandscape ? geometry.size.width * cardHeight : nil,
                    height: isLandscape ? nil : geometry.size.height * cardHeight
                )
                .frame(maxHeight: isLandscape ? .infinity : nil)
                .zIndex(1)
                if showingAnswer {
                    VStack(spacing: 14) {
                        replayButton(for: card)
                        HStack(spacing: 8) {
                            ForEach(CardRating.allCases) { rating in
                                Button(rating.title) {
                                    submitFromButton(card, rating: rating)
                                }
                                .buttonStyle(ReviewRatingButton(
                                    color: color(for: rating)
                                ))
                                .disabled(model.isReviewLoading || isSubmittingSwipe)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        replayButton(for: card)
                        Button("SHOW ANSWER") { showingAnswer = true }
                            .buttonStyle(MankiPrimaryButton(expands: false))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func replayButton(for card: ReviewCard) -> some View {
        if !visibleAudio(for: card).isEmpty {
            Button { playVisibleAudio() } label: {
                Label("Replay audio", systemImage: "speaker.wave.2.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .textCase(.uppercase)
                    .tracking(1)
                    .frame(width: 192, height: 52)
            }
            .foregroundStyle(MankiPalette.sky)
            .background(MankiPalette.sky.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MankiPalette.sky.opacity(0.18), lineWidth: 1) }
            .accessibilityHint("Plays the audio attached to this side of the card again")
        }
    }

    private func visibleAudio(for card: ReviewCard) -> [String] {
        showingAnswer ? card.questionAudio + card.answerAudio : card.questionAudio
    }

    private func playVisibleAudio() {
        guard let card = model.reviewCard else {
            audioPlayer.stop()
            return
        }
        audioPlayer.play(filenames: visibleAudio(for: card))
    }

    @ViewBuilder private func fittedCardText(_ card: ReviewCard, size: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            CardText(html: card.question, fontSize: size)
            if showingAnswer {
                Rectangle().fill(MankiPalette.sky.opacity(0.18)).frame(height: 1)
                Text("answer").font(.caption.weight(.bold)).foregroundStyle(MankiPalette.sky).textCase(.uppercase).tracking(1)
                CardText(html: card.answer.answerBody, fontSize: size)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var swipeRating: CardRating? {
        guard showingAnswer else { return nil }
        return CardSwipe.rating(for: cardOffset)
    }

    private var activeRating: CardRating? {
        buttonPreviewRating ?? swipeRating
    }

    private var visibleCardCount: Int {
        let currentDeck = model.decks.first(where: { $0.id == deck.id }) ?? deck
        let scheduledCards = currentDeck.newCount + currentDeck.learnCount + currentDeck.dueCount
        return min(5, max(1, scheduledCards))
    }

    private func reviewCardBacking(position: DeckStackPosition) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(MankiPalette.canvas)
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(MankiPalette.sky.opacity(0.12), lineWidth: 1.5) }
            .rotationEffect(.degrees(position.rotation))
            .offset(x: position.xOffset, y: position.yOffset)
            .padding(.horizontal, 5)
            .allowsHitTesting(false)
    }

    private func swipeGesture(for card: ReviewCard) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard showingAnswer, !isSubmittingSwipe else { return }
                cardOffset = value.translation
            }
            .onEnded { value in
                guard showingAnswer, !isSubmittingSwipe else { return }
                cardOffset = value.predictedEndTranslation
                guard let rating = CardSwipe.rating(for: value.translation) else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { cardOffset = .zero }
                    return
                }
                submit(card, rating: rating)
            }
    }

    private func submit(_ card: ReviewCard, rating: CardRating) {
        guard !isSubmittingSwipe else { return }
        isSubmittingSwipe = true
        dismiss(card, rating: rating)
    }

    private func submitFromButton(_ card: ReviewCard, rating: CardRating) {
        guard !isSubmittingSwipe else { return }
        isSubmittingSwipe = true
        buttonPreviewRating = rating
        withAnimation(.easeOut(duration: 0.20)) {
            cardOffset = previewOffset(for: rating)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            dismiss(card, rating: rating)
        }
    }

    private func previewOffset(for rating: CardRating) -> CGSize {
        switch rating {
        case .again: CGSize(width: 0, height: 45)
        case .hard: CGSize(width: -50, height: 0)
        case .good: CGSize(width: 50, height: 0)
        case .easy: CGSize(width: 0, height: -45)
        }
    }

    private func dismiss(_ card: ReviewCard, rating: CardRating) {
        let distance: CGFloat = 900
        let destination: CGSize
        switch rating {
        case .again: destination = CGSize(width: cardOffset.width, height: distance)
        case .hard: destination = CGSize(width: -distance, height: cardOffset.height)
        case .good: destination = CGSize(width: distance, height: cardOffset.height)
        case .easy: destination = CGSize(width: cardOffset.width, height: -distance)
        }
        withAnimation(.easeIn(duration: 0.22)) { cardOffset = destination }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            await model.answer(card, in: deck, rating: rating, elapsed: Date.now.timeIntervalSince(shownAt))
            showingAnswer = false
            shownAt = .now
            cardOffset = .zero
            buttonPreviewRating = nil
            isSubmittingSwipe = false
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

@MainActor
private final class CardAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var remainingURLs: [URL] = []

    func play(filenames: [String]) {
        stop()
        remainingURLs = filenames.compactMap { AnkiRSLibBackend.mediaURL(for: $0) }
        playNext()
    }

    func stop() {
        player?.stop()
        player = nil
        remainingURLs = []
    }

    private func playNext() {
        guard !remainingURLs.isEmpty else {
            player = nil
            return
        }
        do {
            let nextPlayer = try AVAudioPlayer(contentsOf: remainingURLs.removeFirst())
            nextPlayer.delegate = self
            nextPlayer.prepareToPlay()
            nextPlayer.play()
            player = nextPlayer
        } catch {
            playNext()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in playNext() }
    }
}

enum CardSwipe {
    static let threshold: CGFloat = 80

    static func rating(for translation: CGSize) -> CardRating? {
        guard max(abs(translation.width), abs(translation.height)) >= threshold else { return nil }
        if abs(translation.width) > abs(translation.height) {
            return translation.width < 0 ? .hard : .good
        }
        return translation.height < 0 ? .easy : .again
    }
}

private struct CardText: View {
    let html: String
    let fontSize: CGFloat
    var body: some View { Text(plainText).font(.system(size: fontSize, weight: .regular, design: .rounded)).foregroundStyle(MankiPalette.ink) }
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
    var expands = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.heavy)).tracking(0.8).foregroundStyle(.white)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(width: expands ? nil : 192, height: 54)
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
            .background(MankiPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MankiPalette.sky.opacity(0.20), lineWidth: 1.5) }
    }
}
