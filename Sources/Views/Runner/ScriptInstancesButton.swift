import SwiftUI

/// One instance opens directly. Multiple instances share the same chooser everywhere.
struct ScriptInstancesButton: View {
    @ObservedObject var runner: ProcessRunner
    let workspaceID: String
    let scriptID: String
    var showsStatus = false
    @State private var showingInstances = false

    private var instances: [ExecutionSession] {
        runner.activeSessions(workspaceID: workspaceID, scriptID: scriptID)
    }

    private var title: String {
        instances.count > 1 ? L("Instances ({0})", "\(instances.count)") : L("View Current Instance")
    }

    var body: some View {
        Button {
            if instances.count == 1, let session = instances.first { runner.showExecution(session) }
            else { showingInstances = true }
        } label: {
            if showsStatus {
                HStack(spacing: 8) {
                    RunningWaveform()
                    Text(L("{0} instances running", "\(instances.count)"))
                }
                .font(WorkspaceTypography.bodyStrong)
                .foregroundStyle(.blue)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            } else {
                RunningWaveform()
                    .frame(width: WorkspaceControlMetrics.iconTarget, height: WorkspaceControlMetrics.iconTarget)
                    // Plain buttons must hit the full target, including gaps between animated bars.
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if instances.count > 1 {
                            Text("\(instances.count)")
                                .font(.system(size: 9, weight: .semibold)).monospacedDigit()
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .foregroundStyle(Color.accentColor)
                                .background(WorkspaceStyle.canvas, in: Capsule())
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .help(title)
        .accessibilityLabel(title)
        .disabled(instances.isEmpty)
        .popover(isPresented: $showingInstances, arrowEdge: .top) {
            ScriptInstanceList(instances: instances) { session in
                showingInstances = false
                runner.showExecution(session)
            }
        }
    }
}

/// A compact waveform shared by running tasks and instance navigation.
struct RunningWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                bars(phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 0.75) / 0.75 * 2 * Double.pi
                    bars(phase: phase)
                }
            }
        }
        .frame(width: 22, height: 20)
        .accessibilityHidden(true)
    }

    private func bars(phase: Double) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<7) { index in
                let envelope = 1 - Double(abs(index - 3)) / 4
                let pulse = (sin(phase + Double(index) * .pi / 3) + 1) / 2
                Capsule()
                    .frame(width: 1.8, height: CGFloat(4 + envelope * (5 + 11 * pulse)))
            }
        }
    }
}

struct ScriptInstanceList: View {
    let instances: [ExecutionSession]
    let open: (ExecutionSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Running Instances")).font(WorkspaceTypography.sectionTitle)
            if instances.isEmpty {
                Text(L("No running tasks")).font(WorkspaceTypography.body).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(instances) { session in
                            ScriptInstanceRow(session: session, open: { open(session) })
                            if session.id != instances.last?.id { Divider().padding(.vertical, 10) }
                        }
                    }
                }.frame(height: min(CGFloat(instances.count) * 90, 360))
            }
        }
        .padding(16).frame(width: 420)
        .background(WorkspaceStyle.canvas)
        .workspaceTypography()
    }
}

private struct ScriptInstanceRow: View {
    @ObservedObject var session: ExecutionSession
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.instanceLabel).font(WorkspaceTypography.bodyStrong)
                Spacer()
                Text(session.startedAt, style: .timer).monospacedDigit().font(WorkspaceTypography.caption)
            }
            Text(L("Started {0}", L10n.date(session.startedAt, dateStyle: .short, timeStyle: .medium)))
                .font(WorkspaceTypography.caption).foregroundStyle(.secondary)
            HStack {
                Text(session.isBackgroundExecution ? L("Scheduled Task") : L("Manual Task"))
                    .foregroundStyle(.secondary)
                Text(session.status).foregroundStyle(.orange).lineLimit(1)
                Spacer(minLength: 8)
                Button(L("View Output"), action: open)
                Button(session.stopping ? L("Force Stop") : L("Stop"), role: .destructive) {
                    session.stop(force: session.stopping)
                }
            }.font(WorkspaceTypography.caption).controlSize(.small)
        }
    }
}
