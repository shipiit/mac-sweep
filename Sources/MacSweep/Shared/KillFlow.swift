import Darwin
import MacSweepCore
import SwiftUI

struct KillRequest: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let force: Bool

    var id: String { "\(pid)-\(force)" }
    var signal: Int32 { force ? SIGKILL : SIGTERM }
}

/// Confirm → signal → (if EPERM) offer the admin prompt → report. Shared by Processes and Ports.
struct KillFlow: ViewModifier {
    @Binding var request: KillRequest?
    let onFinished: () -> Void

    @State private var adminRequest: KillRequest?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                request.map { $0.force ? "Force kill \($0.name)?" : "Quit \($0.name)?" } ?? "",
                isPresented: isPresented($request),
                titleVisibility: .visible,
                presenting: request
            ) { request in
                Button(request.force ? "Force Kill" : "Quit", role: .destructive) { perform(request) }
                Button("Cancel", role: .cancel) {}
            } message: { request in
                Text(request.force
                    ? "PID \(request.pid) will be stopped immediately (SIGKILL). Unsaved work is lost."
                    : "PID \(request.pid) will be asked to quit (SIGTERM).")
            }
            .alert("Administrator required", isPresented: isPresented($adminRequest), presenting: adminRequest) { request in
                Button("Kill as Administrator", role: .destructive) { performAsAdmin(request) }
                Button("Cancel", role: .cancel) {}
            } message: { request in
                Text("\(request.name) (PID \(request.pid)) belongs to another user. macOS will ask for your password.")
            }
            .alert("Couldn't stop process", isPresented: isPresented($errorMessage), presenting: errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    private func perform(_ request: KillRequest) {
        switch ProcessKiller.send(request.signal, to: request.pid, name: request.name) {
        case .sent, .notFound:
            onFinished()
        case .notPermitted:
            adminRequest = request
        case .refused(let reason):
            errorMessage = reason
        case .failed(let code):
            errorMessage = String(cString: strerror(code))
        }
    }

    private func performAsAdmin(_ request: KillRequest) {
        Task {
            do {
                try await AdminRunner.kill(pid: request.pid, signal: request.signal)
                onFinished()
            } catch AdminRunner.AdminError.cancelled {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension View {
    func killFlow(_ request: Binding<KillRequest?>, onFinished: @escaping () -> Void) -> some View {
        modifier(KillFlow(request: request, onFinished: onFinished))
    }
}

/// Adapts an optional binding to the Bool binding that dialogs and alerts need.
func isPresented<Value>(_ binding: Binding<Value?>) -> Binding<Bool> {
    Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
}
