import Charts
import IntervalCore
import SwiftUI

/// Redraws `content` when the monitor sends a reading, and once more when that reading goes stale.
/// Nothing else redraws it, so a run screen that is paused or waiting draws only this.
struct LiveHeartRate<Content: View>: View {
    let monitor: HeartRateMonitor
    @ViewBuilder let content: (HeartRateDisplay) -> Content

    var body: some View {
        let latest = monitor.latest
        let link = monitor.link
        let maxHeartRate = monitor.maxHeartRate
        TimelineView(Staleness(at: latest.map { $0.date + HeartRateReading.freshFor + 0.1 })) { context in
            content(HeartRateMonitor.display(latest: latest, link: link, maxHeartRate: maxHeartRate, at: context.date))
        }
    }
}

private struct Staleness: TimelineSchedule {
    let date: Date?

    init(at date: Date?) {
        self.date = date
    }

    func entries(from start: Date, mode: TimelineScheduleMode) -> [Date] {
        // TimelineView does not draw the last entry of a schedule that ends, so a date that never comes follows it.
        guard let date, date > start else { return [start, .distantFuture] }
        return [start, date, .distantFuture]
    }
}

/// The heart rate on the run screen. Its slot is the same height whatever it shows.
struct HeartRateReadout: View {
    let monitor: HeartRateMonitor

    static let height: CGFloat = 44

    var body: some View {
        LiveHeartRate(monitor: monitor) { display in
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(display.tone?.tint ?? Color.white.opacity(0.5))
                    .accessibilityHidden(true)
                Text(display.bpm.map(String.init) ?? "–")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel(display.bpm.map { "\($0) beats per minute" } ?? "No heart rate")
                    .accessibilityIdentifier("heartRateBPM")
                Text(display.state.uppercased())
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(display.tone == nil ? Color.white.opacity(0.75) : Color.black)
                    .background(display.tone?.tint ?? Color.white.opacity(0.18), in: Capsule())
                    .accessibilityIdentifier("heartRateZone")
            }
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: Self.height)
            .background(Color.black.opacity(0.28), in: Capsule())
        }
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("heartRate")
    }
}

extension HeartRateDisplay {
    var bpm: Int? {
        if case .live(let bpm, _) = self { bpm } else { nil }
    }

    var tone: ZoneTone? {
        if case .live(_, let zone) = self { ZoneTone(zone) } else { nil }
    }

    /// The zone, or why there is no number.
    var state: String {
        switch self {
        case .live(_, let zone): ZoneTone(zone).label
        case .connecting: "Connecting"
        case .noSignal: "No signal"
        }
    }
}

/// The Heart rate section of Settings.
struct HeartRateSettings: View {
    let monitor: HeartRateMonitor

    var body: some View {
        Section {
            if let remembered = monitor.remembered {
                LabeledContent {
                    LiveHeartRate(monitor: monitor) { display in
                        Text(reading(display))
                            .monospacedDigit()
                            .accessibilityIdentifier("monitorReading")
                    }
                } label: {
                    Text(remembered.name)
                        .accessibilityIdentifier("rememberedMonitor")
                }
                Button("Forget", role: .destructive) { monitor.forget() }
                    .accessibilityIdentifier("forgetMonitorButton")
            } else {
                Text("No heart rate monitor")
                    .foregroundStyle(Color.secondary)
                    .accessibilityIdentifier("noMonitor")
            }
            NavigationLink("Find a monitor") {
                FindMonitorScreen(monitor: monitor)
            }
            .accessibilityIdentifier("findMonitorButton")
            Stepper(value: maxHeartRate, in: MaxHeartRate.range) {
                LabeledContent("Max heart rate", value: "\(monitor.maxHeartRate.value) bpm")
            }
            .accessibilityIdentifier("maxHeartRateStepper")
        } header: {
            Text("Heart rate")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let problem {
                    Text(problem).foregroundStyle(Tone.prepare.tint)
                }
                Text("A workout shows your heart rate and keeps it in History. On a Fitbit Air, open the Google Health app and turn on Connections, Fitbit Air, Share heart rate. Any Bluetooth heart-rate strap works too.")
                Text("Max heart rate sets the zones. Roughly 220 minus your age.")
            }
        }
    }

    private var maxHeartRate: Binding<Int> {
        Binding(get: { monitor.maxHeartRate.value }, set: { value in
            if let valid = MaxHeartRate(value) { monitor.maxHeartRate = valid }
        })
    }

    private func reading(_ display: HeartRateDisplay) -> String {
        switch (display, monitor.link) {
        case (.live(let bpm, let zone), _): "\(bpm) bpm · \(ZoneTone(zone).label)"
        case (_, .off): "Bluetooth is off"
        case (_, .unauthorized): "Not allowed"
        case (_, .refused): "Not sending"
        default: display.state
        }
    }

    private var problem: String? {
        guard monitor.remembered != nil else { return nil }
        return switch monitor.link {
        case .unauthorized: "Intervals may not use Bluetooth. Allow it in the Settings app, under Intervals."
        case .refused: "The monitor did not send its heart rate. If iOS asks to pair it, tap Pair. To try again, tap Find a monitor and pick it."
        default: nil
        }
    }
}

private struct FindMonitorScreen: View {
    let monitor: HeartRateMonitor

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if monitor.found.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Looking for monitors")
                            .foregroundStyle(Color.secondary)
                    }
                }
                ForEach(monitor.found) { found in
                    Button {
                        monitor.remember(found)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Text(found.name)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "cellularbars", variableValue: found.strength)
                                .accessibilityHidden(true)
                            Text(found.strengthLabel)
                                .foregroundStyle(Color.secondary)
                        }
                        .lineLimit(1)
                    }
                    .accessibilityIdentifier("foundMonitor-\(found.name)")
                }
            } footer: {
                Text(footer)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Find a monitor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { monitor.scan(true) }
        .onDisappear { monitor.scan(false) }
    }

    private var footer: String {
        switch monitor.link {
        case .unauthorized: "Intervals may not use Bluetooth. Allow it in the Settings app, under Intervals."
        case .off: "Bluetooth is off. Turn it on in Control Centre."
        default: "Monitors that share heart rate over Bluetooth appear here. On a Fitbit Air, turn on Share heart rate in the Google Health app first. Tap a monitor to use it."
        }
    }
}

private extension FoundMonitor {
    /// From 0 at -100 dBm to 1 at -50 dBm.
    var strength: Double { min(max(Double(rssi + 100) / 50, 0), 1) }

    var strengthLabel: String {
        rssi >= -60 ? "Strong" : rssi >= -75 ? "Good" : "Weak"
    }
}

/// The heart rate of a run, on its History entry.
struct HeartRateSummaryCard: View {
    let summary: HeartRateSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                figure("Average", summary.average, identifier: "heartRateAverage")
                Spacer()
                figure("Maximum", summary.maximum, identifier: "heartRateMaximum")
            }
            ZoneBar(summary: summary)
                .frame(height: 14)
                .accessibilityIdentifier("zoneBar")
            VStack(spacing: 8) {
                ForEach(HeartRateZone.allCases.reversed(), id: \.self) { zone in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(ZoneTone(zone).tint)
                            .frame(width: 10, height: 10)
                        Text(ZoneTone(zone).label)
                        Spacer()
                        Text(ClockText.remaining(summary.seconds(in: zone)))
                            .monospacedDigit()
                            .foregroundStyle(Color.secondary)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
            HeartRateGraph(summary: summary)
                .frame(height: 200)
            Text("Zones from a max heart rate of \(summary.maxHeartRate.value) bpm.")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
        }
        .padding(16)
        .background(Theme.card, in: Theme.cardShape)
    }

    private func figure(_ label: String, _ bpm: Int, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(bpm)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("bpm")
                    .font(.headline)
                    .foregroundStyle(Color.secondary)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(bpm) bpm")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier(identifier)
    }
}

/// The time in each zone as one bar, coolest on the left.
private struct ZoneBar: View {
    let summary: HeartRateSummary

    var body: some View {
        Canvas { context, size in
            let radius = min(size.height / 2, 4)
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius), with: .color(.white.opacity(0.14)))
            let total = summary.secondsInZone.reduce(0, +)
            guard total > 0 else { return }
            context.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius))
            var x: CGFloat = 0
            for zone in HeartRateZone.allCases {
                let width = size.width * summary.seconds(in: zone) / total
                context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(ZoneTone(zone).tint))
                x += width
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Time in each zone")
    }
}

/// The heart rate over the run, on the colours of the zones. A gap in the readings is a gap in the line.
private struct HeartRateGraph: View {
    let summary: HeartRateSummary

    private struct Point: Identifiable {
        let id: Int
        let minutes: Double
        let bpm: Int
        let part: Int
    }

    var body: some View {
        let points = Self.points(summary.trace)
        let beats = summary.trace.map(\.bpm)
        let low = (beats.min() ?? 60) - 10
        let high = (beats.max() ?? 200) + 10
        let end = max(points.last?.minutes ?? 0, 1)
        Chart {
            ForEach(HeartRateZone.allCases, id: \.self) { zone in
                RectangleMark(
                    xStart: .value("From", 0.0), xEnd: .value("To", end),
                    yStart: .value("Floor", summary.maxHeartRate.floor(of: zone)),
                    yEnd: .value("Ceiling", ceiling(of: zone)))
                    .foregroundStyle(ZoneTone(zone).tint.opacity(0.22))
            }
            ForEach(points) { point in
                LineMark(x: .value("Minutes", point.minutes), y: .value("Heart rate", point.bpm),
                         series: .value("Part", point.part))
                    .foregroundStyle(Color.white)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXScale(domain: 0...end)
        .chartYScale(domain: low...high)
        .chartXAxisLabel("Minutes")
        .chartYAxisLabel("bpm")
        .chartPlotStyle { $0.clipped() }
        .accessibilityIdentifier("heartRateGraph")
    }

    private func ceiling(of zone: HeartRateZone) -> Int {
        HeartRateZone(rawValue: zone.rawValue + 1).map(summary.maxHeartRate.floor) ?? HeartRateReading.plausible.upperBound + 10
    }

    /// A point more than `longestGap` after the one before starts a new part of the line.
    private static func points(_ trace: [HeartRateSummary.Point]) -> [Point] {
        var part = 0
        var previous: Int?
        return trace.enumerated().map { index, point in
            if let previous, Double(point.second - previous) > HeartRateSummary.longestGap { part += 1 }
            previous = point.second
            return Point(id: index, minutes: Double(point.second) / 60, bpm: point.bpm, part: part)
        }
    }
}
