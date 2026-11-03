import SwiftUI

struct DialerView: View {
    @EnvironmentObject var model: ModemModel
    @State private var number = ""
    @State private var reply = ""
    @State private var showNoCalls = false
    @FocusState private var replyFocused: Bool

    private let keys: [(String, String)] = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", ""), ("0", "+"), ("#", ""),
    ]

    var body: some View {
        HStack(spacing: 0) {
            keypad
                .frame(width: 320)
                .padding(.vertical, 16)
            Divider()
            transcript
        }
        .navigationTitle("Dialer")
        .alert("This stick can't make calls", isPresented: $showNoCalls) {
            Button("Send SMS") { model.compose(to: number) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The E3372 is a data-only modem with no voice support. You can send \(number) a text message instead.")
        }
    }

    // MARK: Keypad

    private var keypad: some View {
        GeometryReader { geo in
            // Five rows of keys (4 + call) plus gaps take 6.2 key heights; the
            // quick codes and the display take the rest. Drop the quick codes
            // in short windows (they're also in the menu bar).
            let showQuick = geo.size.height > 470
            let fixed: CGFloat = showQuick ? 150 : 60
            let key = min(68, max(34, (geo.size.height - fixed) / 6.2))
            VStack(spacing: key * 0.2) {
                if showQuick { quickCodes }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    TextField("Enter code", text: $number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        .onSubmit(call)
                    Button { if !number.isEmpty { number.removeLast() } } label: {
                        Image(systemName: "delete.left").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(number.isEmpty ? 0 : 1)
                }
                .frame(height: 40)
                .padding(.horizontal, 28)

                Grid(horizontalSpacing: key * 0.28, verticalSpacing: key * 0.2) {
                    ForEach(0..<4) { row in
                        GridRow {
                            ForEach(0..<3) { col in
                                let k = keys[row * 3 + col]
                                KeyButton(digit: k.0, letters: k.1, size: key) { number += k.0 }
                            }
                        }
                    }
                }

                Button(action: call) {
                    ZStack {
                        Circle().fill(Color.green)
                        if model.ussdBusy {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "phone.fill").font(.system(size: key * 0.36)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: key, height: key)
                }
                .buttonStyle(KeyPressStyle())
                .disabled(number.isEmpty || model.ussdBusy)
                .opacity(number.isEmpty ? 0.45 : 1)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var quickCodes: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
            ForEach(model.quickCodes) { q in
                Button {
                    number = q.code
                    call()
                } label: {
                    VStack(spacing: 1) {
                        Text(q.name).font(.callout.weight(.medium))
                        Text(q.code).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(model.ussdBusy)
            }
        }
        .padding(.horizontal, 20)
    }

    private func call() {
        let code = number.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        if code.contains("*") || code.contains("#") {
            model.dial(code)
        } else {
            showNoCalls = true
        }
    }

    // MARK: USSD transcript

    private var transcript: some View {
        VStack(spacing: 0) {
            if model.ussdLog.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "number.circle").font(.system(size: 44)).foregroundStyle(.tertiary)
                    Text("USSD replies appear here").font(.title3)
                    Text("Dial a code such as *144# for your balance.\nMenus let you answer with a number.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(model.ussdLog) { entry in
                                USSDBubble(entry: entry).id(entry.id)
                            }
                            if model.ussdBusy {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Waiting for the network…").foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .id("busy")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: model.ussdLog.count) { _ in
                        withAnimation { proxy.scrollTo(model.ussdLog.last?.id, anchor: .bottom) }
                    }
                }
            }
            if model.ussdSessionOpen {
                Divider()
                HStack(spacing: 8) {
                    TextField("Reply (e.g. 1)", text: $reply)
                        .textFieldStyle(.roundedBorder)
                        .focused($replyFocused)
                        .onSubmit(sendReply)
                    Button("Send", action: sendReply)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(reply.isEmpty || model.ussdBusy)
                    Button("End", role: .destructive) { model.endUSSD() }
                        .disabled(model.ussdBusy)
                }
                .padding(12)
                .onAppear { replyFocused = true }
            }
        }
        .toolbar {
            if !model.ussdLog.isEmpty {
                Button {
                    if model.ussdSessionOpen { model.endUSSD() }
                    model.ussdLog.removeAll()
                } label: { Label("Clear", systemImage: "trash") }
                .disabled(model.ussdBusy)
            }
        }
    }

    private func sendReply() {
        guard !reply.isEmpty, !model.ussdBusy else { return }
        model.dial(reply, reply: true)
        reply = ""
    }
}

struct KeyButton: View {
    let digit: String
    let letters: String
    var size: CGFloat = 68
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: -2) {
                Text(digit).font(.system(size: size * 0.4, weight: .regular, design: .rounded))
                Text(letters.isEmpty ? " " : letters)
                    .font(.system(size: max(8, size * 0.13), weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
            .background(Circle().fill(.quaternary))
            .contentShape(Circle())
        }
        .buttonStyle(KeyPressStyle())
    }
}

struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct USSDBubble: View {
    let entry: USSDEntry

    var body: some View {
        switch entry.kind {
        case .sent:
            HStack {
                Spacer(minLength: 80)
                Text(entry.text)
                    .font(.body.monospaced())
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
        case .received:
            HStack {
                Text(entry.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 80)
            }
        case .info, .error:
            Text(entry.text)
                .font(.caption)
                .foregroundStyle(entry.kind == .error ? .red : .secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
