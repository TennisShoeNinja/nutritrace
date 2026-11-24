import Foundation
import Capacitor
import WidgetKit

/// JS name "WidgetBridge" (src/lib/ios-widget.js). iOS only.
/// - setSnapshot: today's calories/protein from the Diary -> App Group, redraw widgets now.
/// - setServer: server URL + read-only API token for the widget's own refreshes (token -> Keychain).
/// - getStatus: whether the widget has a token for this server.
/// - clear: forget everything (sign-out).
@objc(WidgetBridgePlugin)
public class WidgetBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "WidgetBridgePlugin"
    public let jsName = "WidgetBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setSnapshot", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setServer", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise),
    ]

    @objc func setSnapshot(_ call: CAPPluginCall) {
        guard let date = call.getString("date") else { return call.reject("date is required") }
        let meals: [MealCalories]? = call.getArray("meals")?.compactMap { raw in
            guard let m = raw as? [String: Any], let name = m["name"] as? String else { return nil }
            return MealCalories(name: name, kcal: (m["kcal"] as? NSNumber)?.doubleValue ?? 0)
        }
        let now = Date()
        let snap = WidgetSnapshot(
            date: date,
            kcal: call.getDouble("kcal") ?? 0,
            kcalGoal: call.getDouble("kcalGoal"),
            protein: call.getDouble("protein") ?? 0,
            proteinGoal: call.getDouble("proteinGoal"),
            proteinIsMin: call.getBool("proteinIsMin") ?? true,
            carbs: call.getDouble("carbs"),
            carbsGoal: call.getDouble("carbsGoal"),
            carbsIsMin: call.getBool("carbsIsMin"),
            fat: call.getDouble("fat"),
            fatGoal: call.getDouble("fatGoal"),
            fatIsMin: call.getBool("fatIsMin"),
            meals: meals,
            mealsAt: meals == nil ? nil : now,
            energyUnit: call.getString("energyUnit") ?? "kcal",
            updatedAt: now,
            source: "app")
        // Skip redraws when nothing visible changed (the Diary re-renders often).
        if var old = WidgetShared.loadSnapshot() {
            old.updatedAt = snap.updatedAt
            old.mealsAt = snap.mealsAt
            old.source = "app"
            if old == snap {
                WidgetShared.saveSnapshot(old)
                return call.resolve(["changed": false])
            }
        }
        WidgetShared.saveSnapshot(snap)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.widgetKind)
        call.resolve(["changed": true])
    }

    @objc func setServer(_ call: CAPPluginCall) {
        guard let url = call.getString("serverUrl"), let token = call.getString("token"),
              !url.isEmpty, !token.isEmpty else { return call.reject("serverUrl and token are required") }
        WidgetShared.serverUrl = url
        guard WidgetShared.saveToken(token) else { return call.reject("Could not save the token to the Keychain") }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.widgetKind)
        call.resolve()
    }

    @objc func getStatus(_ call: CAPPluginCall) {
        call.resolve([
            "hasToken": WidgetShared.loadToken() != nil,
            "serverUrl": WidgetShared.serverUrl ?? "",
        ])
    }

    @objc func clear(_ call: CAPPluginCall) {
        WidgetShared.clearAll()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.widgetKind)
        call.resolve()
    }
}
