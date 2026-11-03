import SwiftUI

@main
struct E3372ModemApp: App {
    @StateObject private var model = ModemModel()

    init() { Snapshot.runIfRequested() }

    var body: some Scene {
        Window("E3372 Modem", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { model.start() }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            MenuLabel(status: model.status)
        }
    }
}

struct MenuLabel: View {
    let status: ModemStatus

    var body: some View {
        let level = status.reachable ? Double(status.signalBars) / Double(max(status.maxBars, 1)) : 0
        HStack(spacing: 3) {
            Image(systemName: status.reachable ? "cellularbars" : "antenna.radiowaves.left.and.right.slash",
                  variableValue: level)
            if status.unread > 0 { Text("\(status.unread)") }
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: ModemModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.status.reachable {
            Text("\(model.status.operatorName) · \(model.status.networkType)")
            Text(model.status.unread == 1 ? "1 unread message" : "\(model.status.unread) unread messages")
        } else {
            switch model.problem {
            case .starting: Text("E3372 starting up…")
            case .driverMissing: Text("E3372 driver not installed")
            case .notAnswering: Text("E3372 not answering")
            default: Text("E3372 not plugged in")
            }
        }
        Divider()
        Button("Open E3372 Modem") { show(.dialer) }
        Button("Messages") { show(.messages) }
        if !model.quickCodes.isEmpty {
            Menu("Dial") {
                ForEach(model.quickCodes) { q in
                    Button("\(q.name)  \(q.code)") {
                        show(.dialer)
                        model.dial(q.code)
                    }
                }
            }
        }
        Button("Stick's Web Settings") { NSWorkspace.shared.open(model.webURL) }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }

    private func show(_ section: ModemModel.Section) {
        model.section = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: ModemModel
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $model.section) {
                Label("Dialer", systemImage: "circle.grid.3x3.fill").tag(ModemModel.Section.dialer)
                Label("Messages", systemImage: "message.fill")
                    .badge(model.status.unread)
                    .tag(ModemModel.Section.messages)
                Label("Device", systemImage: "simcard.fill").tag(ModemModel.Section.device)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) { StatusFooter(status: model.status).padding(12) }
        } detail: {
            VStack(spacing: 0) {
                if let problem = model.problem {
                    ProblemBanner(problem: problem)
                    Divider()
                }
                switch model.section ?? .dialer {
                case .dialer: DialerView()
                case .messages: MessagesView()
                case .device: DeviceView()
                }
            }
            .animation(.default, value: model.problem)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

struct SignalBars: View {
    let bars: Int
    let max: Int

    var body: some View {
        Image(systemName: "cellularbars", variableValue: max > 0 ? Double(bars) / Double(max) : 0)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel("\(bars) of \(max) bars")
    }
}

struct StatusFooter: View {
    let status: ModemStatus

    var body: some View {
        HStack(spacing: 10) {
            if status.reachable {
                SignalBars(bars: status.signalBars, max: status.maxBars)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.operatorName.isEmpty ? "No network" : status.operatorName)
                        .font(.callout.weight(.semibold))
                    Text(status.simReady ? status.networkType : "No SIM")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").foregroundStyle(.secondary)
                Text("Stick not found").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
