import AppKit
import Foundation
import UserNotifications

struct Conversation: Identifiable, Hashable {
    var id: String { phone }
    let phone: String
    var messages: [SMS]

    var last: SMS? { messages.last }
    var unreadCount: Int { messages.filter { $0.unread && !$0.outgoing }.count }
}

struct USSDEntry: Identifiable {
    enum Kind { case sent, received, info, error }
    let id = UUID()
    let kind: Kind
    let text: String
    let date = Date()
}

struct QuickCode: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var code: String
}

@MainActor
final class ModemModel: ObservableObject {
    @Published var status = ModemStatus()
    @Published var conversations: [Conversation] = []
    @Published var sentCount = 0
    @Published var ussdLog: [USSDEntry] = []
    @Published var ussdBusy = false
    @Published var ussdSessionOpen = false
    @Published var lastError: String?
    @Published var quickCodes: [QuickCode] = ModemModel.loadQuickCodes() {
        didSet { saveQuickCodes() }
    }
    @Published var host: String
    @Published var section: Section? = .dialer
    @Published var selectedPhone: String?
    @Published var draftPhone: String?

    enum Section: Hashable { case dialer, messages, device }

    let api: HiLink
    private var knownInbox: Set<Int>?
    private var timer: Timer?
    private var started = false

    init() {
        let saved = UserDefaults.standard.string(forKey: "host")
        let host = (saved?.isEmpty == false ? saved! : HiLink.detectHost())
        self.host = host
        api = HiLink(host: host)
    }

    var webURL: URL { URL(string: "http://\(host)/")! }

    func start() {
        guard !started else { return }
        started = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        Task { await refreshAll() }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    func setHost(_ newHost: String) {
        let h = newHost.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(h, forKey: "host")
        host = h.isEmpty ? HiLink.detectHost() : h
        Task {
            await api.setHost(host)
            await refreshAll()
        }
    }

    // MARK: Status and messages

    func poll() async {
        let before = status.unread
        await refreshStatus()
        if status.reachable && (status.unread != before || knownInbox == nil) {
            await refreshMessages()
        }
    }

    func refreshAll() async {
        if UserDefaults.standard.string(forKey: "host")?.isEmpty != false {
            let detected = HiLink.detectHost()
            if detected != host {
                host = detected
                await api.setHost(detected)
            }
        }
        await refreshStatus()
        await refreshMessages()
    }

    func refreshStatus() async {
        do {
            status = try await api.status()
        } catch {
            status = ModemStatus()
        }
    }

    func refreshMessages() async {
        do {
            let inbox = try await api.messages(box: 1)
            let sent = try await api.messages(box: 2)
            sentCount = sent.count
            notifyNew(inbox)
            var byPhone: [String: [SMS]] = [:]
            for m in inbox + sent { byPhone[m.phone, default: []].append(m) }
            conversations = byPhone.map { Conversation(phone: $0.key, messages: $0.value.sorted { $0.date < $1.date }) }
                .sorted { ($0.last?.date ?? .distantPast) > ($1.last?.date ?? .distantPast) }
            NSApp.dockTile.badgeLabel = status.unread > 0 ? "\(status.unread)" : nil
        } catch {
            report(error)
        }
    }

    private func notifyNew(_ inbox: [SMS]) {
        let ids = Set(inbox.map(\.id))
        defer { knownInbox = ids }
        guard let known = knownInbox else { return }
        for m in inbox where !known.contains(m.id) && m.unread {
            let content = UNMutableNotificationContent()
            content.title = m.phone
            content.body = m.content
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "sms-\(m.id)", content: content, trigger: nil))
        }
    }

    func markRead(_ conversation: Conversation) {
        let ids = conversation.messages.filter { $0.unread && !$0.outgoing }.map(\.id)
        guard !ids.isEmpty else { return }
        Task {
            do {
                try await api.markRead(ids)
                await refreshStatus()
                await refreshMessages()
            } catch { report(error) }
        }
    }

    func send(_ text: String, to phone: String) async -> Bool {
        do {
            try await api.sendSMS(to: phone, text: text)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await refreshMessages()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func delete(_ conversation: Conversation) {
        Task {
            do {
                try await api.delete(conversation.messages.map(\.id))
                await refreshAll()
            } catch { report(error) }
        }
    }

    func clearSent() {
        Task {
            do {
                let sent = try await api.messages(box: 2)
                try await api.delete(sent.map(\.id))
                await refreshAll()
            } catch { report(error) }
        }
    }

    // MARK: USSD

    func dial(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty, !ussdBusy else { return }
        ussdLog.append(USSDEntry(kind: .sent, text: code))
        ussdBusy = true
        Task {
            do {
                switch try await api.sendUSSD(code) {
                case .reply(let text):
                    ussdLog.append(USSDEntry(kind: .received, text: text))
                    // Any reply may be a menu or a prompt ("Enter amount"), so keep
                    // the session open until the user ends it or dials a new code.
                    ussdSessionOpen = true
                case .noReply:
                    ussdLog.append(USSDEntry(kind: .info, text: "No reply. The result may arrive as an SMS."))
                    ussdSessionOpen = false
                }
            } catch {
                ussdLog.append(USSDEntry(kind: .error, text: error.localizedDescription))
                ussdSessionOpen = false
            }
            ussdBusy = false
        }
    }

    func endUSSD() {
        ussdSessionOpen = false
        ussdLog.append(USSDEntry(kind: .info, text: "Session ended"))
        Task { await api.releaseUSSD() }
    }

    /// The stick can't place voice calls, so a plain number becomes a new SMS.
    func compose(to phone: String) {
        if conversations.contains(where: { $0.phone == phone }) {
            selectedPhone = phone
            draftPhone = nil
        } else {
            draftPhone = phone
            selectedPhone = phone
        }
        section = .messages
    }

    // MARK: Helpers

    private func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    private static func loadQuickCodes() -> [QuickCode] {
        if let data = UserDefaults.standard.data(forKey: "quickCodes"),
           let codes = try? JSONDecoder().decode([QuickCode].self, from: data) {
            return codes
        }
        return [
            QuickCode(name: "Balance", code: "*144#"),
            QuickCode(name: "Bundles", code: "*544#"),
            QuickCode(name: "M-PESA", code: "*334#"),
            QuickCode(name: "Safaricom", code: "*100#"),
        ]
    }

    private func saveQuickCodes() {
        if let data = try? JSONEncoder().encode(quickCodes) {
            UserDefaults.standard.set(data, forKey: "quickCodes")
        }
    }
}
