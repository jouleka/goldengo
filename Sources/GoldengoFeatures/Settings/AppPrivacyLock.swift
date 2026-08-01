import SwiftUI
import GoldengoData
import GoldengoDesignSystem
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

enum GoldengoDeviceAuthentication {
    @MainActor
    static func authenticate(reason: String) async -> Bool {
#if canImport(LocalAuthentication)
        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
#else
        return false
#endif
    }
}

/// Full-screen privacy gate. It authenticates on entry, but always leaves a clear retry action so a
/// cancelled Face ID prompt never traps the user in a blank or spinner-only screen.
struct AppPrivacyLockView: View {
    let onUnlock: () -> Void
    @State private var authenticating = false
    @State private var attempted = false

    var body: some View {
        ZStack {
            Color.goldengoBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(GoldengoTheme.accentSoft).frame(width: 82, height: 82)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 34, weight: .semibold)).foregroundStyle(GoldengoTheme.accent)
                }
                VStack(spacing: 7) {
                    Text("Goldengo is locked").font(.system(size: 28, weight: .medium, design: .serif))
                    Text("Your money stays private when you step away.")
                        .font(.system(size: 14)).foregroundStyle(GoldengoTheme.inkMuted)
                }
                Button { unlock() } label: {
                    HStack(spacing: 9) {
                        if authenticating { ProgressView().tint(Color.goldengoBackground) }
                        else { Image(systemName: "faceid") }
                        Text(authenticating ? "Checking…" : "Unlock")
                    }
                    .font(.system(size: 15.5, weight: .bold)).foregroundStyle(Color.goldengoBackground)
                    .frame(width: 190, height: 50).background(GoldengoTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain).disabled(authenticating)
                if attempted && !authenticating {
                    Text("Use Face ID or your device passcode.").font(.caption).foregroundStyle(GoldengoTheme.inkMuted)
                }
            }.padding(30)
        }
        .interactiveDismissDisabled()
        .task { unlock() }
    }

    private func unlock() {
        guard !authenticating else { return }
        authenticating = true; attempted = true
        Task { @MainActor in
            let success = await GoldengoDeviceAuthentication.authenticate(reason: "Unlock your financial overview")
            authenticating = false
            if success { onUnlock() }
        }
    }
}
