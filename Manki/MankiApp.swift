import SwiftUI

@main
struct MankiApp: App {
    @StateObject private var notificationRouter = NotificationRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notificationRouter)
        }
    }
}
