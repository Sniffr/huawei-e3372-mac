import SwiftUI

/// Shown above every screen while the stick can't be used, with the fix.
struct ProblemBanner: View {
    @EnvironmentObject var model: ModemModel
    let problem: ModemModel.Problem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(3)
                actions.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
    }

    @ViewBuilder private var actions: some View {
        switch problem {
        case .noStick:
            EmptyView()
        case .starting(let since):
            TimelineView(.periodic(from: .now, by: 5)) { context in
                if context.date.timeIntervalSince(since) > 45 && Driver.canSwitch {
                    switchButton
                }
            }
        case .driverMissing:
            if Driver.canSwitch { switchButton }
        case .notAnswering:
            HStack {
                Button("Open Local Network Settings") { NSWorkspace.shared.open(Driver.localNetworkSettings) }
                Button("Retry") { Task { await model.refreshAll() } }
            }
        }
    }

    private var switchButton: some View {
        Button {
            model.switchNow()
        } label: {
            if model.switching { ProgressView().controlSize(.small) } else { Text("Switch Now") }
        }
        .disabled(model.switching)
    }

    private var icon: String {
        switch problem {
        case .noStick: return "cable.connector"
        case .starting: return "hourglass"
        case .driverMissing: return "exclamationmark.triangle.fill"
        case .notAnswering: return "network.slash"
        }
    }

    private var tint: Color {
        switch problem {
        case .noStick, .starting: return .blue
        case .driverMissing, .notAnswering: return .orange
        }
    }

    private var title: String {
        switch problem {
        case .noStick: return "Plug in your E3372"
        case .starting: return "Your stick is starting up…"
        case .driverMissing: return "The E3372 driver isn't installed"
        case .notAnswering: return "The stick is connected but not answering"
        }
    }

    private var detail: String {
        switch problem {
        case .noStick:
            return "Connect the stick to a USB port. It takes about 20 seconds to come online."
        case .starting:
            return "It's switching from its CD mode to a network adapter, which takes about 20 seconds."
        case .driverMissing:
            return "Without it the stick stays in CD mode. Reinstall the Huawei-E3372 package, or switch it once now."
        case .notAnswering:
            return "If you clicked Don't Allow when macOS asked about your local network, turn on E3372 Modem under Privacy & Security › Local Network."
        }
    }
}
