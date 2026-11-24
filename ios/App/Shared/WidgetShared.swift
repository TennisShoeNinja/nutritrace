// Shared by the App target (WidgetBridgePlugin) and the NutriTraceWidget extension.
//
// The app writes a snapshot of today's calories and protein into the App Group
// whenever the Diary shows today, and asks WidgetKit to redraw. The widget also
// fetches /api/v1/diary/<today>/totals from the server with a read-only API token
// (kept in the shared Keychain group) to pick up entries made on other devices.
import Foundation
import Security

struct MealCalories: Codable, Equatable {
    var name: String
    var kcal: Double
}

struct WidgetSnapshot: Codable, Equatable {
    var date: String          // local calendar day, yyyy-MM-dd
    var kcal: Double          // eaten, always kcal
    var kcalGoal: Double?     // effective goal the Diary shows (activity-adjusted)
    var protein: Double       // eaten, grams
    var proteinGoal: Double?  // grams
    var proteinIsMin: Bool    // true when the protein goal is a minimum to reach
    // Optional so snapshots saved before carbs/fat were added still decode.
    var carbs: Double? = nil        // grams
    var carbsGoal: Double? = nil
    var carbsIsMin: Bool? = nil
    var fat: Double? = nil          // grams
    var fatGoal: Double? = nil
    var fatIsMin: Bool? = nil
    var meals: [MealCalories]? = nil  // per meal slot, always from the app
    var mealsAt: Date? = nil          // when the app last calculated them
    var energyUnit: String    // "kcal" or "kJ", for display only
    var updatedAt: Date
    var source: String        // "app" or "server"
}

enum WidgetShared {
    static let appGroup = "group.com.tennisshoeninja.nutritrace"
    static let widgetKind = "NutriTraceToday"

    private static let snapshotKey = "widget.snapshot"
    private static let serverUrlKey = "widget.serverUrl"
    // Saved without kSecAttrAccessGroup: iOS puts it in the first group listed in
    // keychain-access-groups, which both targets' entitlements set to the shared group.
    private static let keychainService = "com.tennisshoeninja.nutritrace.widget"
    private static let keychainAccount = "api-token"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    // MARK: Snapshot

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snap: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    // MARK: Server + token

    static var serverUrl: String? {
        get { defaults?.string(forKey: serverUrlKey) }
        set { defaults?.set(newValue, forKey: serverUrlKey) }
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        deleteToken()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: Data(token.utf8),
            // The widget refreshes while the phone is locked (lock-screen widget).
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clearAll() {
        deleteToken()
        defaults?.removeObject(forKey: snapshotKey)
        defaults?.removeObject(forKey: serverUrlKey)
    }

    // MARK: Dates

    /// Local calendar day as yyyy-MM-dd, matching the web app's localDateStr().
    static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
