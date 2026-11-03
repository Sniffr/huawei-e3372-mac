import AppKit
import SwiftUI

/// `E3372Modem --snapshot <dir>` renders every screen to PNGs (light and
/// dark) using live data from the stick, then quits. For checking the UI
/// without screen-recording permission.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = args[i + 1]
        DispatchQueue.main.async {
            Task { @MainActor in
                await run(dir: dir)
                exit(0)
            }
        }
    }

    private static func run(dir: String) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let model = ModemModel()
        model.isSnapshot = true
        await model.refreshAll()
        model.ussdLog = [
            USSDEntry(kind: .sent, text: "*144#"),
            USSDEntry(kind: .received, text: "Airtime Bal: 0.02KSH.Expire date:01-01-2037. Tariff:Mpesa_Agent ."),
            USSDEntry(kind: .sent, text: "*544#"),
            USSDEntry(kind: .received, text: "Data & SMS Bundles\n1. Daily bundles\n2. Weekly bundles\n3. Monthly bundles\n4. No expiry"),
        ]
        model.ussdSessionOpen = true
        model.selectedPhone = model.conversations.first?.phone

        for dark in [false, true] {
            let suffix = dark ? "-dark" : ""
            for (name, section) in [("dialer", ModemModel.Section.dialer), ("messages", .messages), ("device", .device)] {
                model.section = section
                await render(ContentView().environmentObject(model), size: NSSize(width: 980, height: 640),
                             dark: dark, to: "\(dir)/\(name)\(suffix).png")
            }
            // Smallest window, with a banner: everything must still fit.
            model.section = .dialer
            model.problem = .notAnswering
            await render(ContentView().environmentObject(model), size: NSSize(width: 900, height: 600),
                         dark: dark, to: "\(dir)/dialer-min\(suffix).png")
            model.problem = nil
            await render(ContentView().environmentObject(model), size: NSSize(width: 900, height: 600),
                         dark: dark, to: "\(dir)/dialer-min-nobanner\(suffix).png")
            let banners: [ModemModel.Problem] = [.noStick, .starting(since: .distantPast), .driverMissing, .notAnswering]
            for (n, p) in banners.enumerated() {
                await render(ProblemBanner(problem: p).environmentObject(model).frame(width: 700),
                             size: NSSize(width: 700, height: 120), dark: dark, to: "\(dir)/banner\(n)\(suffix).png")
            }
            await render(MenuLabel(status: model.status).padding(6), size: NSSize(width: 80, height: 30),
                         dark: dark, to: "\(dir)/menulabel\(suffix).png")
        }
    }

    private static func render<V: View>(_ view: V, size: NSSize, dark: Bool, to path: String) async {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        // A process may capture its own windows without screen-recording
        // permission. CGWindowListCreateImage is hidden from the current SDK,
        // so look it up at run time.
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"),
           let image = unsafeBitCast(sym, to: Capture.self)(.null, 1 << 3 /* including window */,
                                                           UInt32(window.windowNumber), 1 << 0 /* ignore framing */)?
            .takeRetainedValue() {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        window.orderOut(nil)
    }
}
