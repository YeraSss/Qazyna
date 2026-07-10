import SwiftUI

/// A short first-run walkthrough that explains what Qazyna does. Shown once on first launch
/// (tracked by `@AppStorage("hasOnboarded")`) and replayable from Settings.
struct OnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0

    private struct Slide: Identifiable {
        let id = UUID()
        let symbol: String
        let tint: Color
        let title: String
        let body: String
    }

    private let slides: [Slide] = [
        Slide(symbol: "tengesign.circle.fill", tint: .green,
              title: "Welcome to Qazyna",
              body: "A fast, private money tracker for tenge and 150+ currencies. Everything stays on your device — no bank logins, no accounts."),
        Slide(symbol: "building.columns.fill", tint: .teal,
              title: "See your whole picture",
              body: "Group money by bank and sub-account — card, deposit, savings, cash. Your net worth is always at the top of the Accounts tab."),
        Slide(symbol: "bolt.fill", tint: .orange,
              title: "Add in seconds",
              body: "Type “coffee 1500 kaspi”, scan a receipt, or import a CSV. With Tap to Track, Apple Pay taps can log themselves in the background."),
        Slide(symbol: "chart.pie.fill", tint: .purple,
              title: "Budgets & insights",
              body: "Set monthly limits, get a nudge before you overspend, and see exactly where your money goes with clear charts."),
        Slide(symbol: "checkmark.seal.fill", tint: .green,
              title: "You’re in control",
              body: "Start by adding a bank in the Accounts tab. Your data is yours — back it up anytime from Settings.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .opacity(page == slides.count - 1 ? 0 : 1)
            }

            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    slideView(slide).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < slides.count - 1 {
                    withAnimation { page += 1 }
                    Haptics.selection()
                } else {
                    finish()
                }
            } label: {
                Text(page < slides.count - 1 ? "Continue" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }

    private func slideView(_ slide: Slide) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(slide.tint.opacity(0.15)).frame(width: 150, height: 150)
                Image(systemName: slide.symbol)
                    .font(.system(size: 66, weight: .semibold))
                    .foregroundStyle(slide.tint)
            }
            VStack(spacing: 12) {
                Text(slide.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(slide.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Spacer()
        }
        .padding()
    }

    private func finish() {
        Haptics.success()
        onDone()
    }
}

#Preview {
    OnboardingView(onDone: {})
}
