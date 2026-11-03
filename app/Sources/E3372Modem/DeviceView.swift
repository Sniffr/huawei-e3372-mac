import SwiftUI

struct DeviceView: View {
    @EnvironmentObject var model: ModemModel
    @State private var hostField = ""
    @State private var newName = ""
    @State private var newCode = ""

    var body: some View {
        Form {
            Section("Network") {
                LabeledContent("Operator", value: value(model.status.operatorName))
                LabeledContent("Network", value: value(model.status.networkType))
                LabeledContent("Signal") {
                    HStack(spacing: 8) {
                        SignalBars(bars: model.status.signalBars, max: model.status.maxBars)
                            .font(.title3)
                        if !model.status.rsrp.isEmpty {
                            Text("RSRP \(model.status.rsrp) · SINR \(model.status.sinr)")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("SIM", value: model.status.reachable ? (model.status.simReady ? "Ready" : "Not ready") : "—")
                LabeledContent("Mobile data", value: value(model.status.connectionText))
            }

            Section {
                ForEach($model.quickCodes) { $q in
                    HStack(spacing: 8) {
                        TextField(text: $q.name, prompt: Text("Name")) { EmptyView() }.labelsHidden()
                            .frame(width: 170)
                        TextField(text: $q.code, prompt: Text("Code")) { EmptyView() }.labelsHidden()
                            .font(.body.monospaced())
                        Button(role: .destructive) {
                            model.quickCodes.removeAll { $0.id == q.id }
                        } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
                HStack(spacing: 8) {
                    TextField(text: $newName, prompt: Text("Name")) { EmptyView() }.labelsHidden()
                        .frame(width: 170)
                    TextField(text: $newCode, prompt: Text("Code, e.g. *544#")) { EmptyView() }.labelsHidden()
                        .font(.body.monospaced())
                        .onSubmit(addCode)
                    Button(action: addCode) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newName.isEmpty || newCode.isEmpty)
                    .help("Add")
                }
            } header: {
                Text("Quick codes")
            } footer: {
                Text("These appear as buttons above the dialer keypad.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)

            Section("Stick") {
                LabeledContent {
                    HStack {
                        TextField(text: $hostField, prompt: Text("Automatic")) { EmptyView() }
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                            .onSubmit { model.setHost(hostField) }
                        Button("Apply") { model.setHost(hostField) }
                    }
                } label: {
                    Text("Address")
                    Text("Now using \(model.host). Leave empty to find it automatically.")
                }
                Toggle("Open at login (for new-message notifications)", isOn: Binding(
                    get: { model.opensAtLogin }, set: { model.opensAtLogin = $0 }))
                Button("Open the Stick's Web Settings") { NSWorkspace.shared.open(model.webURL) }
                Text("SIM PIN, APN and data settings live on the stick's own web page.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Device")
        .onAppear { hostField = UserDefaults.standard.string(forKey: "host") ?? "" }
    }

    private func addCode() {
        guard !newName.isEmpty, !newCode.isEmpty else { return }
        model.quickCodes.append(QuickCode(name: newName, code: newCode))
        newName = ""; newCode = ""
    }

    private func value(_ s: String) -> String {
        model.status.reachable && !s.isEmpty ? s : "—"
    }
}
