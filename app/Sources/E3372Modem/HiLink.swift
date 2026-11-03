import Foundation
import SystemConfiguration

/// Minimal XML tree; the HiLink API speaks small flat XML documents.
final class XMLNode {
    let name: String
    var text = ""
    var children: [XMLNode] = []

    init(name: String) { self.name = name }

    subscript(_ child: String) -> XMLNode? { children.first { $0.name == child } }
    func all(_ child: String) -> [XMLNode] { children.filter { $0.name == child } }
    func value(_ child: String) -> String { self[child]?.text ?? "" }

    static func parse(_ data: Data) -> XMLNode? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.parse()
        return builder.root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [XMLNode] = []
        var root: XMLNode?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let node = XMLNode(name: name)
            stack.last?.children.append(node)
            if root == nil { root = node }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            stack.last?.text += String(decoding: data, as: UTF8.self)
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let node = stack.removeLast()
            if node.children.isEmpty {
                node.text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}

struct HiLinkError: LocalizedError {
    let code: Int

    var errorDescription: String? {
        switch code {
        case -1: return "The stick didn't answer. Is it plugged in?"
        case 125002, 125003: return "The stick's session expired. Try again."
        case 100002: return "This stick doesn't support that."
        case 100003: return "The stick refused the request (not allowed)."
        default: return "The stick reported error \(code)."
        }
    }
}

func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

/// Talks to the stick's built-in web API (the one its web page uses).
/// Every call fetches a fresh session cookie and token, which is what the
/// stick's own page does too; it costs one tiny extra request.
actor HiLink {
    private(set) var host: String
    private let session: URLSession

    init(host: String) {
        self.host = host
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)
    }

    func setHost(_ host: String) { self.host = host }

    func get(_ path: String) async throws -> XMLNode {
        try await request(path, body: nil, auth: try await token())
    }

    func post(_ path: String, _ body: String) async throws -> XMLNode {
        try await request(path, body: body, auth: try await token())
    }

    private func token() async throws -> (cookie: String, token: String) {
        let info = try await request("webserver/SesTokInfo", body: nil, auth: nil)
        return (info.value("SesInfo"), info.value("TokInfo"))
    }

    private func request(_ path: String, body: String?, auth: (cookie: String, token: String)?) async throws -> XMLNode {
        guard let url = URL(string: "http://\(host)/api/\(path)") else { throw HiLinkError(code: -1) }
        var req = URLRequest(url: url)
        if let auth {
            req.setValue(auth.cookie, forHTTPHeaderField: "Cookie")
            req.setValue(auth.token, forHTTPHeaderField: "__RequestVerificationToken")
        }
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><request>\(body)</request>".utf8)
        }
        let data: Data
        do {
            (data, _) = try await session.data(for: req)
        } catch {
            throw HiLinkError(code: -1)
        }
        guard let root = XMLNode.parse(data) else { throw HiLinkError(code: -1) }
        if root.name == "error" {
            throw HiLinkError(code: Int(root.value("code")) ?? -1)
        }
        return root
    }

    /// The stick's address is the .1 of the subnet on its network interface:
    /// 192.168.8.1 on most HiLink sticks, but not all (some use 192.168.106.1).
    nonisolated static func detectHost() -> String {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return "192.168.8.1" }
        for iface in interfaces {
            guard let name = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String?,
                  name.uppercased().contains("HUAWEI"),
                  let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
                  let ip = ipv4Address(of: bsd) else { continue }
            var parts = ip.split(separator: ".").map(String.init)
            if parts.count == 4 {
                parts[3] = "1"
                return parts.joined(separator: ".")
            }
        }
        return "192.168.8.1"
    }

    nonisolated private static func ipv4Address(of interface: String) -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard String(cString: ifa.ifa_name) == interface,
                  let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}

// MARK: - Typed calls

struct ModemStatus: Equatable {
    var operatorName = ""
    var networkType = ""
    var signalBars = 0
    var maxBars = 5
    var simReady = false
    var connected = false
    var connectionText = ""
    var rsrp = ""
    var sinr = ""
    var unread = 0
    var storageFull = false
    var reachable = false
}

struct SMS: Identifiable, Hashable {
    let id: Int
    let phone: String
    let content: String
    let date: Date
    let outgoing: Bool
    var unread: Bool
}

enum USSDResult {
    case reply(String)
    case noReply
}

extension HiLink {
    func status() async throws -> ModemStatus {
        var s = ModemStatus()
        let st = try await get("monitoring/status")
        s.reachable = true
        s.signalBars = Int(st.value("SignalIcon")) ?? 0
        s.maxBars = Int(st.value("maxsignal")) ?? 5
        s.simReady = st.value("SimStatus") == "1"
        switch st.value("ConnectionStatus") {
        case "900": s.connectionText = "Connecting"
        case "901": s.connected = true; s.connectionText = "Connected"
        case "903": s.connectionText = "Disconnecting"
        default: s.connectionText = "Not connected"
        }
        let ex = Int(st.value("CurrentNetworkTypeEx")) ?? 0
        switch ex {
        case 0: s.networkType = "No service"
        case 101...: s.networkType = "4G"
        case 41...100: s.networkType = "3G"
        default: s.networkType = "2G"
        }
        if let plmn = try? await get("net/current-plmn") {
            s.operatorName = plmn.value("FullName").isEmpty ? plmn.value("ShortName") : plmn.value("FullName")
        }
        if let sig = try? await get("device/signal") {
            s.rsrp = sig.value("rsrp")
            s.sinr = sig.value("sinr")
        }
        if let n = try? await get("monitoring/check-notifications") {
            s.unread = Int(n.value("UnreadMessage")) ?? 0
            s.storageFull = n.value("SmsStorageFull") == "1"
        }
        return s
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// box 1 = inbox, 2 = sent.
    func messages(box: Int) async throws -> [SMS] {
        var result: [SMS] = []
        for page in 1...20 {
            let list = try await post("sms/sms-list", """
                <PageIndex>\(page)</PageIndex><ReadCount>50</ReadCount><BoxType>\(box)</BoxType>\
                <SortType>0</SortType><Ascending>0</Ascending><UnreadPreferred>0</UnreadPreferred>
                """)
            let items = list["Messages"]?.all("Message") ?? []
            for m in items {
                result.append(SMS(id: Int(m.value("Index")) ?? 0,
                                  phone: m.value("Phone"),
                                  content: m.value("Content"),
                                  date: Self.dateFormatter.date(from: m.value("Date")) ?? .distantPast,
                                  outgoing: box == 2,
                                  unread: m.value("Smstat") == "0"))
            }
            if items.count < 50 { break }
        }
        return result
    }

    func sendSMS(to phone: String, text: String) async throws {
        let now = Self.dateFormatter.string(from: Date())
        _ = try await post("sms/send-sms", """
            <Index>-1</Index><Phones><Phone>\(xmlEscape(phone))</Phone></Phones><Sca></Sca>\
            <Content>\(xmlEscape(text))</Content><Length>\(text.count)</Length><Reserved>1</Reserved>\
            <Date>\(now)</Date>
            """)
    }

    func markRead(_ ids: [Int]) async throws {
        for id in ids {
            _ = try await post("sms/set-read", "<Index>\(id)</Index>")
        }
    }

    func delete(_ ids: [Int]) async throws {
        for chunk in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) {
            _ = try await post("sms/delete-sms", chunk.map { "<Index>\($0)</Index>" }.joined())
        }
    }

    func sendUSSD(_ code: String) async throws -> USSDResult {
        _ = try await post("ussd/send",
                           "<content>\(xmlEscape(code))</content><codeType>CodeType</codeType><timeout></timeout>")
        // The stick reports result 1 while it waits for the network.
        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let s = try await get("ussd/status")
            if s.value("result") != "1" { break }
        }
        do {
            let reply = try await get("ussd/get").value("content")
            return reply.isEmpty ? .noReply : .reply(reply)
        } catch {
            return .noReply
        }
    }

    func releaseUSSD() async {
        _ = try? await get("ussd/release")
    }
}
