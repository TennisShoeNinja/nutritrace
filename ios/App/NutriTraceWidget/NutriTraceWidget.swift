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
        proteinIsMin: true, carbs: 140, carbsGoal: 220, carbsIsMin: false, fat: 48, fatGoal: 70, fatIsMin: false,
        meals: [MealCalories(name: "Breakfast", kcal: 420), MealCalories(name: "Lunch", kcal: 610), MealCalories(name: "Dinner", kcal: 0), MealCalories(name: "Snacks", kcal: 154)],
        energyUnit: "kcal", updatedAt: Date(), source: "app")

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
        // Goals: keep the ones the app last sent (they include activity / adaptive
        // adjustments the server doesn't compute). Only ask the server when the app
        // has never sent any.
        var snap = previous ?? WidgetSnapshot(
            date: today, kcal: 0, kcalGoal: nil, protein: 0, proteinGoal: nil, proteinIsMin: true,
            energyUnit: "kcal", updatedAt: Date(), source: "server")
        if previous == nil, let g = await getJSON(base, "/api/v1/goals", token),
           let goals = g["goals"] as? [String: Any] {
            func isMin(_ key: String) -> Bool {
                guard let m = goals[key] as? [String: Any] else { return false }
                return m["min"] != nil && m["max"] == nil
            }
            snap.kcalGoal = resolveGoal(goals["calories"], today)
            snap.proteinGoal = resolveGoal(goals["proteins"], today)
            snap.proteinIsMin = isMin("proteins")
            snap.carbsGoal = resolveGoal(goals["carbohydrates"], today)
            snap.carbsIsMin = isMin("carbohydrates")
            snap.fatGoal = resolveGoal(goals["fat"], today)
            snap.fatIsMin = isMin("fat")
        }

        if snap.date != today { snap.meals = nil; snap.mealsAt = nil } // yesterday's meals
        snap.date = today
        snap.kcal = num(t["calories"]) ?? 0
        snap.protein = num(t["proteins"]) ?? 0
        snap.carbs = num(t["carbohydrates"]) ?? 0
        snap.fat = num(t["fat"]) ?? 0
        snap.updatedAt = Date()
        snap.source = "server"
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
    // The web app's --macro-* colours, dark and light.
    static func nt(dark: UInt32, light: UInt32) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    static let ntCalories = nt(dark: 0xFFD54F, light: 0xF9A825)
    static let ntProtein  = nt(dark: 0xCE93D8, light: 0x8E24AA)
    static let ntCarbs    = nt(dark: 0x4FFFB0, light: 0x00A865)
    static let ntFat      = nt(dark: 0xFFB347, light: 0xE07A00)
}

struct Macro {
    let label: String     // "Protein"
    let short: String     // "P"
    let color: Color
    let eaten: Double
    let goal: Double?
    let isMin: Bool

    var progress: Double { guard let g = goal else { return 0 }; return min(max(eaten / g, 0), 1) }
    /// A minimum reached, or a target hit within 5%.
    var done: Bool {
        guard let g = goal else { return false }
        return isMin ? eaten >= g : abs(eaten - g) <= g * 0.05
    }
    /// Over a maximum/target by more than 5%.
    var over: Bool { guard let g = goal, !isMin else { return false }; return eaten > g * 1.05 }
    var amount: String { TodayNumbers.fmt(eaten) }
    var amountOfGoal: String { goal.map { "\(amount)/\(TodayNumbers.fmt($0))" } ?? amount }
}

struct TodayNumbers {
    let eaten: Double, goal: Double?
    let macros: [Macro]
    let meals: [MealCalories]
    /// Set when the server's total no longer matches the app's meal breakdown.
    let mealsAsOf: Date?
    let unit: String, factor: Double, asOf: Date?

    init(_ entry: TodayEntry) {
        let s = entry.snap
        let today = entry.isCurrentDay
        let kj = s?.energyUnit == "kJ"
        factor = kj ? 4.184 : 1
        unit = kj ? "kJ" : "kcal"
        eaten = today ? (s?.kcal ?? 0) : 0
        goal = Self.positive(s?.kcalGoal)
        macros = [
            Macro(label: "Protein", short: "P", color: .ntProtein, eaten: today ? (s?.protein ?? 0) : 0,
                  goal: Self.positive(s?.proteinGoal), isMin: s?.proteinIsMin ?? true),
            Macro(label: "Carbs", short: "C", color: .ntCarbs, eaten: today ? (s?.carbs ?? 0) : 0,
                  goal: Self.positive(s?.carbsGoal), isMin: s?.carbsIsMin ?? false),
            Macro(label: "Fat", short: "F", color: .ntFat, eaten: today ? (s?.fat ?? 0) : 0,
                  goal: Self.positive(s?.fatGoal), isMin: s?.fatIsMin ?? false),
        ]
        // Show "as of" when the numbers are over an hour old (same day only).
        if today, let u = s?.updatedAt, entry.date.timeIntervalSince(u) > 3600 { asOf = u } else { asOf = nil }
        meals = today ? (s?.meals ?? []) : []
        let mealSum = meals.reduce(0) { $0 + $1.kcal }
        if !meals.isEmpty, abs(mealSum - eaten) > 1, let at = s?.mealsAt { mealsAsOf = at } else { mealsAsOf = nil }
    }

    private static func positive(_ v: Double?) -> Double? { v.flatMap { $0 > 0 ? $0 : nil } }

    var remaining: Double? { goal.map { $0 - eaten } }
    var progress: Double { guard let g = goal else { return 0 }; return min(max(eaten / g, 0), 1) }

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

    /// "P 70 · C 120 · F 40"
    var macroLine: String { macros.map { "\($0.short) \($0.amount)" }.joined(separator: " · ") }
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

struct MacroBar: View {
    let m: Macro
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(m.label).font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if m.done { Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(m.color) }
                Text("\(m.amountOfGoal) g").font(.caption2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(m.over ? Color.red : Color.primary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(m.color.opacity(0.2))
                    Capsule().fill(m.color).frame(width: max(g.size.width * m.progress, m.eaten > 0 ? 5 : 0))
                }
            }
            .frame(height: 5)
        }
    }
}

/// "Calories  620 / 2,200" with a bar, sitting above the macro bars.
struct CalorieBar: View {
    let n: TodayNumbers
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text("Calories").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(n.goal.map { "\(n.energy(n.eaten)) / \(n.energy($0))" } ?? "\(n.energy(n.eaten)) \(n.unit)")
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(n.remaining.map { $0 < 0 } == true ? Color.red : Color.primary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ntCalories.opacity(0.2))
                    Capsule().fill(Color.ntCalories).frame(width: max(g.size.width * n.progress, n.eaten > 0 ? 5 : 0))
                }
            }
            .frame(height: 5)
        }
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
                case .systemLarge: large(n)
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

    /// Coloured "P 70  C 45  F 19".
    private func pcf(_ n: TodayNumbers) -> some View {
        HStack(spacing: 6) {
            ForEach(n.macros, id: \.short) { m in
                HStack(spacing: 1) {
                    Text(m.short).foregroundStyle(m.color).fontWeight(.bold)
                    Text(m.amount).monospacedDigit()
                }
            }
        }
        .font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
    }

    // Option A, small: ring, eaten / goal, P · C · F.
    private func small(_ n: TodayNumbers) -> some View {
        VStack(spacing: 4) {
            CalorieRing(n: n, lineWidth: 10)
            if n.asOf != nil {
                asOf(n)
            } else if let g = n.goal {
                Text("\(n.energy(n.eaten)) / \(n.energy(g))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            pcf(n)
        }
    }

    // Option A, medium: ring, then Calories above Protein, Carbs, Fat.
    private func medium(_ n: TodayNumbers) -> some View {
        HStack(spacing: 14) {
            CalorieRing(n: n, lineWidth: 11).frame(maxWidth: 112)
            VStack(alignment: .leading, spacing: 6) {
                CalorieBar(n: n)
                ForEach(n.macros, id: \.short) { MacroBar(m: $0) }
                asOf(n)
            }
        }
    }

    // Option A, large: ring with eaten and goal, the four bars, calories per meal.
    private func large(_ n: TodayNumbers) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                CalorieRing(n: n, lineWidth: 12).frame(width: 124, height: 124)
                VStack(alignment: .leading, spacing: 8) {
                    stat("Eaten", "\(n.energy(n.eaten)) \(n.unit)")
                    if let g = n.goal { stat("Goal", "\(n.energy(g)) \(n.unit)") }
                    asOf(n)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                CalorieBar(n: n)
                ForEach(n.macros, id: \.short) { MacroBar(m: $0) }
            }
            if !n.meals.isEmpty {
                Divider()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 5) {
                    ForEach(Array(n.meals.enumerated()), id: \.offset) { _, meal in
                        HStack {
                            Text(meal.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(meal.kcal > 0 ? "\(n.energy(meal.kcal)) \(n.unit)" : "–")
                                .font(.caption2.weight(.semibold)).monospacedDigit()
                        }
                    }
                }
                if let at = n.mealsAsOf {
                    Text("Meals as of \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
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
        VStack(alignment: .leading, spacing: 1) {
            Text("\(n.headline.0) \(n.headline.1)").font(.headline).widgetAccentable().lineLimit(1)
            Text("P \(n.macros[0].amountOfGoal) g").font(.caption).lineLimit(1)
            Text("C \(n.macros[1].amount) g · F \(n.macros[2].amount) g").font(.caption).lineLimit(1)
        }
    }

    private func inline(_ n: TodayNumbers) -> some View {
        Text("\(n.headline.0) \(n.headline.1) · \(n.macroLine)")
    }
}

// MARK: - Widget

struct NutriTraceTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Calories left, protein, carbs and fat for today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct NutriTraceWidgets: WidgetBundle {
    var body: some Widget {
        NutriTraceTodayWidget()
    }
}
