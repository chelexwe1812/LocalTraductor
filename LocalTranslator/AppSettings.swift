import Foundation
import Observation

/// Preferencias persistentes de la app.
///
/// Se expone como singleton `shared` para que UI y ViewModel observen la
/// misma instancia. Cada cambio se guarda automáticamente en
/// `UserDefaults`, así que las preferencias sobreviven a relanzamientos.
@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    /// Traduce automáticamente con un pequeño debounce mientras escribes.
    /// Cuando es `false`, solo se traduce al pulsar Enter.
    var autoTranslate: Bool {
        didSet { UserDefaults.standard.set(autoTranslate, forKey: Keys.autoTranslate) }
    }

    /// Copia la traducción al portapapeles automáticamente al completarse.
    var autoCopy: Bool {
        didSet { UserDefaults.standard.set(autoCopy, forKey: Keys.autoCopy) }
    }

    /// Detecta el idioma del texto de entrada con `NLLanguageRecognizer`
    /// y actualiza la dirección de traducción sobre la marcha.
    var autoDetectLanguage: Bool {
        didSet { UserDefaults.standard.set(autoDetectLanguage, forKey: Keys.autoDetectLanguage) }
    }

    /// Vaciar entrada y salida cada vez que se oculta el popover, para
    /// poder escribir algo nuevo nada más reabrirlo sin tener que borrar.
    var clearOnDismiss: Bool {
        didSet { UserDefaults.standard.set(clearOnDismiss, forKey: Keys.clearOnDismiss) }
    }

    /// Al abrir el popover, si el portapapeles contiene texto distinto al
    /// de la última vez que lo vimos, se pega en la entrada y se lanza la
    /// traducción al instante.
    var translateClipboardOnOpen: Bool {
        didSet { UserDefaults.standard.set(translateClipboardOnOpen, forKey: Keys.translateClipboardOnOpen) }
    }

    private init() {
        let d = UserDefaults.standard
        // .bool(forKey:) devuelve false si no existe → defaults seguros.
        self.autoTranslate = d.bool(forKey: Keys.autoTranslate)
        self.autoCopy = d.bool(forKey: Keys.autoCopy)
        // Defaults a `true` para autoDetect y clearOnDismiss: solo si nunca
        // se guardaron, usamos true.
        if d.object(forKey: Keys.autoDetectLanguage) == nil {
            self.autoDetectLanguage = true
        } else {
            self.autoDetectLanguage = d.bool(forKey: Keys.autoDetectLanguage)
        }
        if d.object(forKey: Keys.clearOnDismiss) == nil {
            self.clearOnDismiss = true
        } else {
            self.clearOnDismiss = d.bool(forKey: Keys.clearOnDismiss)
        }
        if d.object(forKey: Keys.translateClipboardOnOpen) == nil {
            self.translateClipboardOnOpen = true
        } else {
            self.translateClipboardOnOpen = d.bool(forKey: Keys.translateClipboardOnOpen)
        }
    }

    private enum Keys {
        static let autoTranslate = "autoTranslate"
        static let autoCopy = "autoCopy"
        static let autoDetectLanguage = "autoDetectLanguage"
        static let clearOnDismiss = "clearOnDismiss"
        static let translateClipboardOnOpen = "translateClipboardOnOpen"
    }
}
