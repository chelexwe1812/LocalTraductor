import Foundation
import Observation
import SwiftUI
import AppKit

/// Preferencia del usuario para el modo de color de la UI.
enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    /// Devuelve un `ColorScheme` concreto siempre.
    ///
    /// Para `.system` resolvemos la apariencia activa de macOS en el momento
    /// de la consulta: si dejáramos `nil`, SwiftUI no tendría un valor al que
    /// reaccionar y los textos que ya cachearon su color (p. ej. el NSTextView
    /// que envuelve `TextEditor`) se quedarían con la apariencia anterior
    /// hasta cerrar/reabrir el popover.
    @MainActor
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            let matched = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return matched == .darkAqua ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }
}

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

    /// Modo de color: sigue el sistema, fuerza claro o fuerza oscuro.
    var colorScheme: ColorSchemePreference {
        didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: Keys.colorScheme) }
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
        if let raw = d.string(forKey: Keys.colorScheme),
           let pref = ColorSchemePreference(rawValue: raw) {
            self.colorScheme = pref
        } else {
            self.colorScheme = .system
        }
    }

    private enum Keys {
        static let autoTranslate = "autoTranslate"
        static let autoCopy = "autoCopy"
        static let autoDetectLanguage = "autoDetectLanguage"
        static let clearOnDismiss = "clearOnDismiss"
        static let translateClipboardOnOpen = "translateClipboardOnOpen"
        static let colorScheme = "colorScheme"
    }
}
