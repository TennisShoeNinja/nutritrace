import Capacitor

/// Main.storyboard's root view controller. Registers plugins that live in the
/// app target itself (not in node_modules), which Capacitor can't find on its own.
class BridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(WidgetBridgePlugin())
    }
}
