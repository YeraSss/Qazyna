import Foundation
import LocalAuthentication
import Security
import SwiftUI

/// Face ID / Touch ID / passcode lock. When enabled, the app content is gated behind a lock
/// screen on launch and after returning from the background. An optional app-specific PIN is
/// stored in the Keychain as a fallback for when biometrics aren't available.
@MainActor
final class AppLock: ObservableObject {
    @Published var isLocked: Bool
    @AppStorage("appLockEnabled") var isEnabled = false { didSet { if !isEnabled { isLocked = false } } }

    init() {
        isLocked = UserDefaults.standard.bool(forKey: "appLockEnabled")
    }

    var biometryLabel: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Passcode"
        }
    }

    func lockIfEnabled() { if isEnabled { isLocked = true } }

    func authenticate() async {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: "Unlock Qazyna to view your finances")
            if ok { isLocked = false; Haptics.success() }
        } catch {
            // If biometrics/passcode are unavailable (e.g. Simulator), allow PIN or fail open on unset.
            if !hasPIN() { isLocked = false }
        }
    }

    // MARK: PIN (Keychain)

    private let pinKey = "com.qazyna.app.pin"

    func hasPIN() -> Bool { readPIN() != nil }

    func setPIN(_ pin: String) {
        let data = Data(pin.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrAccount as String: pinKey]
        SecItemDelete(query as CFDictionary)
        var add = query; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    func clearPIN() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: pinKey] as CFDictionary)
    }

    private func readPIN() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrAccount as String: pinKey,
                                     kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let stored = readPIN() else { return false }
        if stored == pin { isLocked = false; Haptics.success(); return true }
        Haptics.error(); return false
    }
}

/// Gates its content behind the lock screen when the app is locked.
struct LockGate<Content: View>: View {
    @ObservedObject var lock: AppLock
    @ViewBuilder var content: () -> Content
    @State private var pin = ""

    var body: some View {
        ZStack {
            content()
            if lock.isEnabled && lock.isLocked {
                lockScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: lock.isLocked)
    }

    private var lockScreen: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "lock.fill").font(.system(size: 52)).foregroundStyle(.tint)
                Text("Qazyna is locked").font(.title2.weight(.semibold))
                Button {
                    Task { await lock.authenticate() }
                } label: {
                    Label("Unlock with \(lock.biometryLabel)", systemImage: "faceid")
                        .padding(.horizontal, 20).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                if lock.hasPIN() {
                    SecureField("PIN", text: $pin)
                        .textFieldStyle(.roundedBorder).keyboardType(.numberPad)
                        .frame(width: 160).multilineTextAlignment(.center)
                        .onChange(of: pin) { _, v in if v.count >= 4 { _ = lock.verifyPIN(v); pin = "" } }
                }
            }
            .padding()
        }
        .task { await lock.authenticate() }
    }
}
