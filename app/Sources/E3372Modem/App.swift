import SwiftUI

@main
struct E3372ModemApp: App {
    @StateObject private var model = ModemModel()

    var body: some Scene {
        Window("E3372 Modem", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 560)
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
            Text("E3372 not found")
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

    var body: some View {
        NavigationSplitView {
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
            switch model.section ?? .dialer {
            case .dialer: DialerView()
            case .messages: MessagesView()
            case .device: DeviceView()
            }
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
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<max, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < bars ? Color.primary : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: CGFloat(5 + i * 3))
            }
        }
    }
}

struct StatusFooter: View {
    let status: ModemStatus

    var body: some View {
        HStack(spacing: 10) {
            if status.reachable {
                SignalBars(bars: status.signalBars, max: status.maxBars)
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
