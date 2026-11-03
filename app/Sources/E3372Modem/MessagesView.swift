import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var model: ModemModel
    @State private var newPhone = ""
    @State private var askNew = false
    @State private var confirmDelete: Conversation?
    @State private var confirmClear = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if model.status.storageFull {
                    storageBanner
                }
                List(selection: $model.selectedPhone) {
                    if let draft = model.draftPhone {
                        ConversationRow(phone: draft, preview: "New message", date: nil, unread: 0)
                            .tag(draft)
                    }
                    ForEach(model.conversations) { c in
                        ConversationRow(phone: c.phone, preview: c.last?.content ?? "",
                                        date: c.last?.date, unread: c.unreadCount)
                            .tag(c.phone)
                            .contextMenu {
                                Button("Delete Conversation", role: .destructive) { confirmDelete = c }
                            }
                    }
                }
                .listStyle(.inset)
            }
            .frame(width: 280)
            Divider()
            if let phone = model.selectedPhone {
                ChatView(phone: phone)
                    .id(phone)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "message").font(.system(size: 44)).foregroundStyle(.tertiary)
                    Text("Select a conversation").font(.title3).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Messages")
        .toolbar {
            Button { Task { await model.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Button { askNew = true } label: { Label("New Message", systemImage: "square.and.pencil") }
        }
        .alert("New message", isPresented: $askNew) {
            TextField("Phone number", text: $newPhone)
            Button("Start") {
                let p = newPhone.filter { $0.isNumber || $0 == "+" }
                if !p.isEmpty { model.compose(to: p) }
                newPhone = ""
            }
            Button("Cancel", role: .cancel) { newPhone = "" }
        }
        .confirmationDialog("Delete this conversation?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), presenting: confirmDelete) { c in
            Button("Delete \(c.messages.count) messages", role: .destructive) {
                if model.selectedPhone == c.phone { model.selectedPhone = nil }
                model.delete(c)
            }
        }
        .confirmationDialog("Delete all \(model.sentCount) sent messages?", isPresented: $confirmClear) {
            Button("Delete Sent Messages", role: .destructive) { model.clearSent() }
        } message: {
            Text("Received messages are kept.")
        }
    }

    private var storageBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Message storage is full", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text("New texts can't arrive until you free space. You have \(model.sentCount) sent messages stored.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Delete Sent Messages…") { confirmClear = true }
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
    }
}

struct ConversationRow: View {
    let phone: String
    let preview: String
    let date: Date?
    let unread: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(unread > 0 ? Color.accentColor : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(phone).font(.body.weight(unread > 0 ? .semibold : .regular)).lineLimit(1)
                    Spacer()
                    if let date {
                        Text(date, format: Calendar.current.isDateInToday(date)
                             ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(preview).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ChatView: View {
    @EnvironmentObject var model: ModemModel
    let phone: String
    @State private var text = ""
    @State private var sending = false

    private var messages: [SMS] {
        model.conversations.first { $0.phone == phone }?.messages ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(phone).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { m in
                            SMSBubble(sms: m).id(m.id)
                        }
                    }
                    .padding(16)
                }
                .onAppear { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                .onChange(of: messages.count) { _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Text message", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
                    .onSubmit(send)
                VStack(spacing: 2) {
                    Button(action: send) {
                        Image(systemName: sending ? "ellipsis.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 26))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(text.isEmpty ? Color.secondary : Color.accentColor)
                    .disabled(text.isEmpty || sending)
                    Text(counter).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .onAppear(perform: markRead)
        .onChange(of: messages.count) { _ in markRead() }
    }

    private var counter: String {
        let n = text.count
        let parts = n <= 160 ? 1 : Int((Double(n) / 153).rounded(.up))
        return parts > 1 ? "\(n) · \(parts) SMS" : "\(n)"
    }

    private func markRead() {
        if let c = model.conversations.first(where: { $0.phone == phone }), c.unreadCount > 0 {
            model.markRead(c)
        }
    }

    private func send() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        Task {
            if await model.send(body, to: phone) {
                text = ""
                if model.draftPhone == phone { model.draftPhone = nil }
            }
            sending = false
        }
    }
}

struct SMSBubble: View {
    let sms: SMS

    var body: some View {
        HStack {
            if sms.outgoing { Spacer(minLength: 80) }
            VStack(alignment: sms.outgoing ? .trailing : .leading, spacing: 3) {
                Text(sms.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(sms.outgoing ? Color.accentColor : Color.secondary.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(sms.outgoing ? Color.white : Color.primary)
                Text(sms.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !sms.outgoing { Spacer(minLength: 80) }
        }
    }
}
