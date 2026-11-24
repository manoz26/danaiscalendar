import LocalAuthentication
import Observation
import PlannerCore
import SwiftUI

/// Locking with Face ID, Touch ID or the device's passcode (Settings → Lock): the whole
/// app, or only the journal and the sketches. It locks whenever the app goes to the
/// background (and at launch); while the app is not in front (the app switcher), what is
/// locked is covered.
@MainActor
@Observable
final class AppLock {
    var mode: LockMode {
        didSet {
            guard mode != oldValue else { return }
            // Turned on here she just unlocked to do it; turned off, nothing is locked.
            unlocked = true
            AppLog.info("Lock: \(mode.rawValue)")
        }
    }

    /// Unlocked since the app last came to the front.
    private(set) var unlocked: Bool
    /// The app is not in front: locked content is covered (the app switcher shows the cover).
    private(set) var covered = false
    /// The journal or a sketch is on screen (the iPad's page or a sheet, the iPhone's tab).
    var showsNotebook = false
    /// A Face ID / passcode sheet is up.
    private(set) var isAsking = false

    init(mode: LockMode) {
        self.mode = mode
        unlocked = mode == .off
    }

    /// Something locked would be on screen.
    var isLocked: Bool {
        !unlocked && (mode == .app || (mode == .journal && showsNotebook))
    }

    /// The journal and sketches need unlocking first (they are about to open).
    var notebooksLocked: Bool {
        !unlocked && mode != .off
    }

    /// What the app switcher may not show.
    var hidesContent: Bool {
        covered && (mode == .app || (mode == .journal && showsNotebook))
    }

    func sceneChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            covered = false
        case .inactive:
            // Also while the Face ID sheet is up: that is not leaving the app.
            if !isAsking { covered = true }
        case .background:
            covered = true
            if mode != .off, unlocked {
                unlocked = false
                AppLog.info("Locked")
            }
        @unknown default:
            break
        }
    }

    /// Asks for Face ID, Touch ID or the passcode. Returns whether it worked.
    @discardableResult
    func unlock() async -> Bool {
        guard !unlocked else { return true }
        guard await authenticate(reason: String(localized: "Unlock Danai's Calendar", comment: "Face ID / passcode reason: opening the locked app.")) else {
            return false
        }
        unlocked = true
        AppLog.info("Unlocked")
        return true
    }

    /// Face ID, Touch ID or the passcode, for `reason` (e.g. before turning the lock on).
    func authenticate(reason: String) async -> Bool {
        #if DEBUG
        if let fake = LaunchOptions.fakeUnlock { return fake }
        #endif
        guard !isAsking else { return false }
        isAsking = true
        defer { isAsking = false }
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            AppLog.warning("Unlock did not work: \((error as? LAError)?.code.rawValue ?? -1)")
            return false
        }
    }

    /// The device can lock the app: it has a passcode (Face ID and Touch ID need one too).
    static var isAvailable: Bool {
        #if DEBUG
        if LaunchOptions.fakeUnlock != nil { return true }
        #endif
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// What unlocks it on this device, for the settings' texts.
    static var method: Method {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcode
        }
    }

    enum Method {
        case faceID, touchID, passcode
    }
}

extension View {
    /// The whole app's lock screen, and the cover for the app switcher.
    func lockCover(_ lock: AppLock) -> some View {
        modifier(LockCover(lock: lock))
    }
}

private struct LockCover: ViewModifier {
    let lock: AppLock
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if lock.mode == .app && !lock.unlocked {
                    LockScreen(lock: lock, isWholeApp: true)
                        .transition(.opacity)
                } else if lock.hidesContent {
                    PrivacyCover()
                }
            }
            .animation(.easeOut(duration: 0.2), value: lock.unlocked)
            .onChange(of: scenePhase, initial: true) { _, phase in
                lock.sceneChanged(to: phase)
            }
    }
}

/// White paper with the app's name: what the app switcher shows of locked content.
private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Paper.background
            Text(verbatim: "DANAI'S CALENDAR")
                .font(.inter(.semibold, size: 13, relativeTo: .caption))
                .tracking(2)
                .foregroundStyle(Paper.secondary)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Locked: the app's name, a lock, and "Unlock". Face ID is asked for as soon as it shows.
struct LockScreen: View {
    let lock: AppLock
    /// The whole app (otherwise only the journal and sketches).
    let isWholeApp: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var failed = false

    var body: some View {
        ZStack {
            Paper.background
            VStack(spacing: 18) {
                Image(systemName: "lock")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Paper.ink)
                if isWholeApp {
                    CapsLabel("Danai's Calendar")
                } else {
                    CapsLabel("Journal and sketches")
                }
                Button {
                    ask()
                } label: {
                    Text("Unlock")
                        .font(.inter(.semibold, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.background)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Paper.ink)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lock.unlock")
                .padding(.top, 8)
                if failed {
                    Text("Not unlocked. Try again.")
                        .font(.inter(.regular, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Paper.secondary)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lock.screen")
        .task(id: scenePhase) {
            // Asked once each time it shows with the app in front.
            if scenePhase == .active, !failed { ask() }
        }
    }

    private func ask() {
        Task {
            let unlocked = await lock.unlock()
            failed = !unlocked
        }
    }
}
