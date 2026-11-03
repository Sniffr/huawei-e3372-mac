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
                        if !model.status.rsrp.isEmpty {
                            Text("RSRP \(model.status.rsrp) · SINR \(model.status.sinr)")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("SIM", value: model.status.reachable ? (model.status.simReady ? "Ready" : "Not ready") : "—")
                LabeledContent("Mobile data", value: value(model.status.connectionText))
            }

            Section("Quick codes") {
                ForEach($model.quickCodes) { $q in
                    HStack {
                        TextField("Name", text: $q.name)
                        TextField("Code", text: $q.code).font(.body.monospaced())
                        Button(role: .destructive) {
                            model.quickCodes.removeAll { $0.id == q.id }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Name", text: $newName)
                    TextField("Code, e.g. *544#", text: $newCode).font(.body.monospaced())
                    Button {
                        model.quickCodes.append(QuickCode(name: newName, code: newCode))
                        newName = ""; newCode = ""
                    } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless)
                    .disabled(newName.isEmpty || newCode.isEmpty)
                }
            }

            Section("Stick") {
                LabeledContent("Address") {
                    HStack {
                        TextField("Automatic (\(HiLink.detectHost()))", text: $hostField)
                            .frame(maxWidth: 220)
                            .onSubmit { model.setHost(hostField) }
                        Button("Apply") { model.setHost(hostField) }
                    }
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

    private func value(_ s: String) -> String {
        model.status.reachable && !s.isEmpty ? s : "—"
    }
}
