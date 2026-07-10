import SwiftUI

enum AppTab: String, Hashable {
    case home, history, accounts, analytics, settings
}

/// Root tab navigation. Tabs are filled in progressively by phase; Accounts (the net-worth
/// differentiator) ships in Phase 1. Selection is state-driven so quick-add / deep links can
/// switch tabs later.
struct RootTabView: View {
    @State private var selection: AppTab = Self.initialTab
    @EnvironmentObject private var router: QuickAddRouter
    @State private var showQuickAdd = false

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }
                .tag(AppTab.history)

            AccountsView()
                .tabItem { Label("Accounts", systemImage: "building.columns.fill") }
                .tag(AppTab.accounts)

            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.pie.fill") }
                .tag(AppTab.analytics)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .sheet(isPresented: $showQuickAdd, onDismiss: { router.clear() }) { QuickAddView() }
        .onChange(of: router.shouldOpenQuickAdd) { _, open in
            if open { selection = .home; showQuickAdd = true }
        }
        .onAppear { if router.shouldOpenQuickAdd { showQuickAdd = true } }
        .onOpenURL { url in
            if url.scheme == "budget", url.host == "quickadd" { selection = .home; showQuickAdd = true }
        }
    }

    /// Allows launching straight to a tab for development/screenshots: pass `-startTab accounts`.
    private static var initialTab: AppTab {
        if let raw = UserDefaults.standard.string(forKey: "startTab"),
           let tab = AppTab(rawValue: raw) {
            return tab
        }
        return .home
    }
}

/// Temporary placeholder for tabs not yet implemented.
struct PlaceholderTab: View {
    let title: String
    let systemImage: String
    let message: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                .navigationTitle(title)
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(FXRateService())
        .modelContainer(ModelContainerFactory.makeContainer(inMemory: true))
}
