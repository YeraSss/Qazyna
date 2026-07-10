import SwiftUI
import SwiftData
import UserNotifications

@main
struct BudgetApp: App {
    let container: ModelContainer
    @StateObject private var fx = FXRateService()
    @StateObject private var router = QuickAddRouter.shared
    @StateObject private var appLock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showOnboarding = false

    init() {
        container = ModelContainerFactory.makeContainer()
        // Seed only the default category taxonomy (idempotent). No sample accounts/transactions.
        SeedData.seedIfNeeded(container.mainContext)
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            LockGate(lock: appLock) {
                RootTabView()
                    .environmentObject(fx)
                    .environmentObject(router)
                    .environmentObject(appLock)
            }
            .task {
                #if DEBUG
                LedgerSelfTest.run()
                #endif
                // Post due auto-log recurring items, re-check budgets, publish widget data.
                RecurringScheduler.runAutoLog(in: container.mainContext)
                BudgetAlerts.evaluate(in: container.mainContext)
                await fx.refresh()
                WidgetSnapshotWriter.update(in: container.mainContext, rateToKZT: { fx.rateToKZT($0) })
            }
            .onAppear { showOnboarding = !hasOnboarded }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView { hasOnboarded = true; showOnboarding = false }
            }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                router.consumePendingIfNeeded()
            case .background:
                appLock.lockIfEnabled()
                WidgetSnapshotWriter.update(in: container.mainContext, rateToKZT: { fx.rateToKZT($0) })
            default: break
            }
        }
    }
}
