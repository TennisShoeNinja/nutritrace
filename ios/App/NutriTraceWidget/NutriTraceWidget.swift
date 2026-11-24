import WidgetKit
import SwiftUI

// MARK: - Timeline

struct TodayEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
    /// false when the snapshot is from an earlier day: eaten numbers show as 0.
    let isCurrentDay: Bool
    let isPlaceholder: Bool
}

struct TodayProvider: TimelineProvider {
    private static let sample = WidgetSnapshot(
        date: WidgetShared.dayString(), kcal: 1184, kcalGoal: 2200, protein: 162, proteinGoal: 234,
        proteinIsMin: true, energyUnit: "kcal", updatedAt: Date(), source: "app")

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snap: Self.sample, isCurrentDay: true, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(Self.entry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task {
            await ServerRefresh.run()
            let now = Date()
            let cal = Calendar.current
            let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now)!)
            // A second entry at midnight resets "eaten" for the new day even if
            // iOS doesn't wake the widget right then.
            let entries = [Self.entry(at: now), Self.entry(at: midnight)]
            let next = min(now.addingTimeInterval(15 * 60), midnight)
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }

    static func entry(at date: Date) -> TodayEntry {
        let snap = WidgetShared.loadSnapshot()
        let current = snap?.date == WidgetShared.dayString(date)
        return TodayEntry(date: date, snap: snap, isCurrentDay: current, isPlaceholder: false)
    }
}

// MARK: - Server refresh (entries logged on the web or Android)

enum ServerRefresh {
    static func run() async {
        guard let base = WidgetShared.serverUrl, !base.isEmpty,
              let token = WidgetShared.loadToken() else { return }
        let today = WidgetShared.dayString()
        let previous = WidgetShared.loadSnapshot()

        // The app just wrote today's numbers (and may still be syncing them up):
        // trust those over a server read that could be a few seconds behind.
        if let p = previous, p.source == "app", p.date == today,
           Date().timeIntervalSince(p.updatedAt) < 120 { return }

        guard let totals = await getJSON(base, "/api/v1/diary/\(today)/totals", token),
              let t = totals["totals"] as? [String: Any] else { return }
        let kcal = num(t["calories"]) ?? 0
        let protein = num(t["proteins"]) ?? 0

        // Goals: keep the ones the app last sent (they include activity / adaptive
        // adjustments the server doesn't compute). Only ask the server when the app
        // has never sent any.
        var kcalGoal = previous?.kcalGoal
        var proteinGoal = previous?.proteinGoal
        var proteinIsMin = previous?.proteinIsMin ?? true
        if previous == nil, let g = await getJSON(base, "/api/v1/goals", token),
           let goals = g["goals"] as? [String: Any] {
            kcalGoal = resolveGoal(goals["calories"], today)
            proteinGoal = resolveGoal(goals["proteins"], today)
            if let p = goals["proteins"] as? [String: Any] {
                proteinIsMin = p["min"] != nil && p["max"] == nil
            }
        }

        let snap = WidgetSnapshot(
            date: today, kcal: kcal, kcalGoal: kcalGoal, protein: protein, proteinGoal: proteinGoal,
            proteinIsMin: proteinIsMin, energyUnit: previous?.energyUnit ?? "kcal",
            updatedAt: Date(), source: "server")
        WidgetShared.saveSnapshot(snap)
    }

    private static func getJSON(_ base: String, _ path: String, _ token: String) async -> [String: Any]? {
        guard let url = URL(string: base + path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func num(_ v: Any?) -> Double? {
        (v as? NSNumber)?.doubleValue
    }

    /// Mirrors src/lib/goal-resolver.js resolveGoalFor (shared or per-weekday goals).
    /// Percent-of-calories macro goals aren't resolved here; the app's snapshot covers them.
    private static func resolveGoal(_ raw: Any?, _ day: String) -> Double? {
        guard let g = raw as? [String: Any], (g["isPercent"] as? Bool) != true else { return nil }
        let fallback = num(g["max"]) ?? num(g["min"])
        if (g["sharedGoal"] as? Bool) != false { return fallback }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        if let days = g["days"] as? [Any], days.count == 7, let d = f.date(from: day) {
            // JS getDay(): 0 = Sunday; Calendar weekday: 1 = Sunday.
            let i = Calendar(identifier: .gregorian).component(.weekday, from: d) - 1
            if let v = num(days[i]) { return v }
        }
        return fallback
    }
}

// MARK: - Display helpers

private extension Color {
    // The web app's --macro-calories / --macro-protein, light and dark.
    static let ntCalories = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1.00, green: 0.835, blue: 0.31, alpha: 1)    // #FFD54F
        : UIColor(red: 0.976, green: 0.659, blue: 0.145, alpha: 1) }) // #F9A825
    static let ntProtein = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.808, green: 0.576, blue: 0.847, alpha: 1)  // #CE93D8
        : UIColor(red: 0.557, green: 0.141, blue: 0.667, alpha: 1) }) // #8E24AA
}

struct TodayNumbers {
    let eaten: Double, goal: Double?, protein: Double, proteinGoal: Double?, proteinIsMin: Bool
    let unit: String, factor: Double, asOf: Date?

    init(_ entry: TodayEntry) {
        let s = entry.snap
        let kj = s?.energyUnit == "kJ"
        factor = kj ? 4.184 : 1
        unit = kj ? "kJ" : "kcal"
        eaten = entry.isCurrentDay ? (s?.kcal ?? 0) : 0
        protein = entry.isCurrentDay ? (s?.protein ?? 0) : 0
        goal = s?.kcalGoal.flatMap { $0 > 0 ? $0 : nil }
        proteinGoal = s?.proteinGoal.flatMap { $0 > 0 ? $0 : nil }
        proteinIsMin = s?.proteinIsMin ?? true
        // Show "as of" when the numbers are over an hour old (same day only).
        if entry.isCurrentDay, let u = s?.updatedAt, entry.date.timeIntervalSince(u) > 3600 { asOf = u } else { asOf = nil }
    }

    var remaining: Double? { goal.map { $0 - eaten } }
    var progress: Double { guard let g = goal else { return 0 }; return min(max(eaten / g, 0), 1) }
    var proteinProgress: Double { guard let g = proteinGoal else { return 0 }; return min(max(protein / g, 0), 1) }
    var proteinDone: Bool { proteinIsMin && proteinGoal != nil && protein >= proteinGoal! }

    func energy(_ kcal: Double) -> String { Self.fmt(kcal * factor) }
    static func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v.rounded()))"
    }

    /// Big number + caption: "1,016" / "kcal left", or "184" / "kcal over".
    var headline: (String, String) {
        guard let r = remaining else { return (energy(eaten), "\(unit) eaten") }
        return r >= 0 ? (energy(r), "\(unit) left") : (energy(-r), "\(unit) over")
    }
}

struct CalorieRing: View {
    let n: TodayNumbers
    var lineWidth: CGFloat = 10
    var body: some View {
        ZStack {
            Circle().stroke(Color.ntCalories.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: n.progress)
                .stroke(n.remaining.map { $0 < 0 } == true ? Color.red : Color.ntCalories,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(n.headline.0).font(.system(.title2, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(n.headline.1).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, lineWidth + 2)
        }
    }
}

struct ProteinBar: View {
    let n: TodayNumbers
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Protein").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if n.proteinDone { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Color.ntProtein) }
                Text(proteinLabel).font(.caption.weight(.semibold)).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ntProtein.opacity(0.2))
                    Capsule().fill(Color.ntProtein).frame(width: max(g.size.width * n.proteinProgress, n.protein > 0 ? 6 : 0))
                }
            }
            .frame(height: 8)
        }
    }
    var proteinLabel: String {
        let eaten = TodayNumbers.fmt(n.protein)
        guard let g = n.proteinGoal else { return "\(eaten) g" }
        return "\(eaten) / \(TodayNumbers.fmt(g)) g"
    }
}

// MARK: - Views per family

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        let n = TodayNumbers(entry)
        Group {
            if entry.snap == nil && !entry.isPlaceholder {
                empty
            } else {
                switch family {
                case .systemSmall: small(n)
                case .systemMedium: medium(n)
                case .accessoryCircular: circular(n)
                case .accessoryRectangular: rectangular(n)
                case .accessoryInline: inline(n)
                default: small(n)
                }
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "fork.knife").font(.title3)
            Text("Open NutriTrace to set up").font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }

    private func asOf(_ n: TodayNumbers) -> some View {
        Group {
            if let d = n.asOf {
                Text("as of \(d.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func small(_ n: TodayNumbers) -> some View {
        VStack(spacing: 6) {
            CalorieRing(n: n, lineWidth: 11)
            if n.asOf != nil {
                asOf(n)
            } else if let g = n.goal {
                Text("\(n.energy(n.eaten)) / \(n.energy(g))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func medium(_ n: TodayNumbers) -> some View {
        HStack(spacing: 16) {
            CalorieRing(n: n, lineWidth: 11).frame(maxWidth: 120)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calories").font(.caption).foregroundStyle(.secondary)
                    Text(n.goal.map { "\(n.energy(n.eaten)) / \(n.energy($0)) \(n.unit)" } ?? "\(n.energy(n.eaten)) \(n.unit)")
                        .font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                }
                ProteinBar(n: n)
                asOf(n)
            }
        }
    }

    private func circular(_ n: TodayNumbers) -> some View {
        Gauge(value: n.progress) {
            Text(n.unit)
        } currentValueLabel: {
            Text(n.remaining.map { TodayNumbers.fmt(abs($0) * n.factor) } ?? n.energy(n.eaten))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private func rectangular(_ n: TodayNumbers) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n.headline.0) \(n.headline.1)").font(.headline).widgetAccentable().lineLimit(1)
            Text(n.proteinGoal.map { "Protein \(TodayNumbers.fmt(n.protein)) / \(TodayNumbers.fmt($0)) g" }
                 ?? "Protein \(TodayNumbers.fmt(n.protein)) g")
                .font(.caption).lineLimit(1)
            Gauge(value: n.proteinProgress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
        }
    }

    private func inline(_ n: TodayNumbers) -> some View {
        Text("\(n.headline.0) \(n.headline.1) · \(TodayNumbers.fmt(n.protein)) g protein")
    }
}

// MARK: - Widget

struct NutriTraceTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Calories left and protein for today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct NutriTraceWidgets: WidgetBundle {
    var body: some Widget {
        NutriTraceTodayWidget()
    }
}
