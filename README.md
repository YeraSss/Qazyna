# Qazyna — Personal Expense & Net-Worth Tracker

**Qazyna** (Kazakh for *treasury*) is a fast, privacy-first, **offline-first** money tracker for iOS
(SwiftUI, iOS 18+), inspired by Finny, with a **net-worth / accounts** screen as its own
differentiator. (The Xcode project / module name is `Budget`; the app's display name is `Qazyna`.) Base currency is
**KZT (₸)** with full multi-currency support. All data stays on your device — no bank logins,
no server, no accounts.

Built with SwiftUI + **SwiftData**, Swift Charts, App Intents, Vision, UserNotifications, and
WidgetKit.

---

## Features

- **Accounts / Net worth** — organize money by **bank → sub-accounts** (card, deposit, savings,
  cash, asset, loan). Grand-total net worth up top, animated expand/collapse per bank, brand-color
  monogram tiles, manual balance adjustments, and transfers between accounts (never counted as
  spending). Built-in Kazakhstani banks: Kaspi, Freedom, Home Credit, Alatau City, ForteBank — plus
  custom banks.
- **Tracking** — sub-5-second quick add (amount, category, account, date, note) for expenses and
  income. Multi-currency: each transaction keeps its original currency and a KZT rate **snapshotted
  at entry**, so historical totals stay stable and auditable.
- **History** — grouped by day, searchable, filter by type/category/account, swipe to edit/delete.
- **Analytics (Swift Charts)** — donut by category, daily bars, 6-month trend, month navigation,
  and tap-a-category **drill-down** into the matching transactions.
- **Insights** — biggest category, month-over-month change, average daily spend, projected
  month-end total, budget-pace warnings ("at this rate you'll exceed Food around the 22nd"), and
  spending spikes.
- **Budgets** — monthly per-category limits with progress bars and configurable warning thresholds
  (default 80% / 100%) → in-app indicators **and** local notifications.
- **Savings goals** — target amount linked to an account, progress + projected completion date.
- **Recurring** — weekly/monthly/yearly/custom rules that auto-log (or prompt to confirm), with an
  "upcoming / due now" view.
- **Tap to Track** — auto-log Apple Pay taps via an iOS Shortcuts automation + a background App
  Intent (see below).
- **Capture** — on-device **natural-language** entry ("coffee 1500 kaspi"), **receipt OCR**
  (Vision), and **CSV / statement import** with column mapping.
- **Backup** — export transactions as CSV, full backup as JSON, and restore from JSON.
- **Extras** — Face ID / Touch ID / PIN lock, home & lock-screen **widgets**, Siri / Spotlight /
  Action-Button quick logging, and a shareable **monthly PDF report**.
- Dark mode, haptics, KZT formatting (`1 234 567 ₸`).

---

## Requirements

- **Xcode 26** (or newer) with the iOS 18+ SDK.
- **iOS 18.0+** deployment target.
- A paid **Apple Developer Team** only if you run on a physical device or use the widget / Tap to
  Track (App Groups require real signing). The Simulator runs unsigned with no Team ID.

## Build & run

```bash
open Budget.xcodeproj      # then press Run (⌘R), or:
xcodebuild -project Budget.xcodeproj -scheme Budget \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

On first launch a short **walkthrough** explains the app, then you start with a clean slate — no
sample data is ever created. Only the default category list is seeded. Add your first bank in the
**Accounts** tab (the built-in Kazakhstani banks appear as one-tap presets). Replay the walkthrough
anytime from **Settings → How Qazyna works**.

### Signing — runs with no Apple account

Both targets ship with **empty entitlements**, so the app builds and runs on the **Simulator with
no Team ID** (just press Run). To run on a **physical device**, select any Team (a free personal
Apple ID works) under *Signing & Capabilities* — there are no restricted capabilities to provision.

Bundle IDs default to `com.qazyna.app` and `com.qazyna.app.BudgetWidgets`.

### Optional: enable live widget data on device (App Group)

The app, the background App Intent, and the widget can share one on-device store via an **App
Group**. It's **off by default** so the project runs with no account. Everything works without it —
the app falls back to Application Support, Tap to Track still logs (the intent runs as the app), and
the **widget shows sample data**. To give the widget *live* data on a real device:

1. Add the **App Groups** capability (needs a paid Apple Developer Team) to both `Budget` and
   `BudgetWidgets`, using the same group id (e.g. `group.com.qazyna.app`).
2. Put that id in both `.entitlements` files and confirm it matches `AppConfig.appGroupID`
   (`Budget/Persistence/AppGroup.swift`) and `WidgetSnapshot.appGroupID`
   (`BudgetWidgets/WidgetSharedSnapshot.swift`).

### Bank logos (optional)

By default banks show a **brand-color monogram** tile (legally clean, no bundled logo art). To fetch
real logos at runtime, add a [Brandfetch](https://brandfetch.com/developers) client ID; the app
always falls back to the monogram when offline or unconfigured. (Logo fetching is a documented
enhancement point in `LogoService`; the monogram is the shipping default.)

---

## Tap to Track — set up the automation

Apple does **not** let third-party apps read Apple Pay transactions directly. The only supported
path (and the one Finny uses) is an iOS **Shortcuts personal automation** that runs a background
App Intent. Set it up once per device:

1. Open **Shortcuts** → **Automation** tab → **＋ New Automation**.
2. Choose **Transaction** (called **Wallet** on iOS 26) → **When I use a card**.
3. Pick the card(s) to track and set **Transaction Type: Payment**.
4. Turn **Run Immediately** on and **Notify When Run** off (silent logging).
5. Add action **Log Apple Pay Expense** (provided by Budget).
6. Map **Shortcut Input → Amount** to *Amount*, and **Merchant** to *Merchant*.
7. Save.

In the app, open **Settings → Tap to Track** to map each Wallet card name to a sub-account and
default currency, so taps land in the right place.

### Honest coverage limits (please read)

- Captures **in-store iPhone contactless Apple Pay taps only** — **not** Apple Watch, online/in-app,
  chip/swipe, or **Kaspi QR / Alaqan** (which dominate in Kazakhstan). Keep using manual entry /
  the capture tools for those.
- The automation **does not reliably pass a currency**, so a tap uses the mapped card's default
  currency (falling back to KZT) and is flagged **needs review**.
- Whether a usable **merchant name** comes through depends on your bank/card — validate on your real
  cards. Correcting a flagged transaction's category **teaches** the app for next time.
- **FinanceKit is not an option here** — it's limited to the US/UK App Stores and Apple
  Card/Cash/Savings, none of which exist in Kazakhstan.

---

## Exchange rates

Rates come from the keyless, public-domain (CC0) **fawazahmed0 Currency API** (KZT base, 330+
currencies) over the jsDelivr CDN with a Cloudflare Pages fallback. A snapshot is cached on-device
for offline use and a **seed snapshot is bundled** for first-run offline. Refresh happens on launch
and via **Settings → Refresh rates now**. This is not an official National Bank of Kazakhstan
valuation. Historical spend uses the rate snapshotted at entry; net worth converts balances at the
latest rate.

---

## Architecture

- **Targets:** `Budget` (app, includes the App Intents) + `BudgetWidgets` (widget extension), one
  hand-authored `.xcodeproj` using Xcode 16+ **file-system synchronized groups** (drop a `.swift`
  file in a folder and it's compiled — no pbxproj edits needed).
- **Persistence:** SwiftData behind a single write chokepoint, `Ledger`. Every money mutation
  (manual, Tap to Track, import, recurring) funnels through it so two invariants always hold:
  `cachedBalance == openingBalance + Σ ledger deltas`, and rollups == recompute(ledger). Edits use
  reverse-then-repost; `Ledger.rebuildRollups` / `rebuildBalances` / `integrityCheck` are the
  recovery net.
- **Aggregation:** SwiftData has no SUM/GROUP BY, so charts read **precomputed rollup entities**
  (`DailyRollup`, `MonthlyRollup`, `CategoryMonthlyRollup`) maintained on every write — never a
  full-table scan. All predicates filter flat indexed scalars (`dateKey`/`monthKey`/`accountID`).
- **Money:** `Decimal` end-to-end, rounded only at display; KZT with 0 fraction digits.
- **Widgets:** the app publishes a tiny `WidgetSnapshot` JSON to the App Group; the widget renders
  from it without opening the full store.
- **On-device NL:** heuristic parser everywhere, upgrading to Apple's **Foundation Models** on iOS 26
  + Apple-Intelligence-capable devices (graceful fallback).

### Project layout

```
Budget/
  App/            RootTabView, tab routing, deep links
  Models/         SwiftData @Model graph + enums + rollups + schema
  Persistence/    ModelContainerFactory, Ledger (write chokepoint), SeedData, self-test
  Services/       FX, NetWorth, TapLogger, NLParser/FoundationModels, ReceiptOCR,
                  ImportExport, InsightsEngine, RecurringScheduler, GoalsCalculator,
                  Notifications, BudgetAlerts, AppLock, ReportBuilder, WidgetSnapshot
  Features/       Home, History, Accounts, Analytics, Budgets, Goals, Recurring,
                  QuickAdd, Capture, TapToTrack, Settings
  Support/        Money, CurrencyFormatter, DateKeys, Color+Hex, Haptics
BudgetWidgets/    WidgetKit extension (reads the shared snapshot)
```

---

## Testing

The critical financial logic is covered by two suites that share the same assertions:

- **`BudgetTests`** (XCTest) — run with **⌘U** or:
  ```bash
  xcodebuild test -project Budget.xcodeproj -scheme Budget \
    -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
- **`LedgerSelfTest`** — the same checks run automatically on every DEBUG launch and log
  `✅ LedgerSelfTest: ALL PASSED` (visible in Console, subsystem `com.qazyna.app`,
  category `selftest`). Handy for verifying on-device.

Coverage includes: balance & rollup consistency across insert/edit/delete/transfer/adjust, the
`Σ rollups == recompute(ledger)` invariant after rebuild, KZT-aware amount parsing (incl. the
`2,990`-as-grouping case), Tap-to-Track routing + **idempotency** (no double-count on re-fired
taps), merchant learning, the NL parser, and CSV export/parse/import round-trips.

---

## Privacy

Everything is on-device. No bank connections, no analytics, no network calls except the daily
public exchange-rate fetch (and optional Brandfetch logo requests if you enable them). Optional
Face ID / PIN lock. A JSON backup you export is the only copy that ever leaves the device, and only
if you choose to share it.
