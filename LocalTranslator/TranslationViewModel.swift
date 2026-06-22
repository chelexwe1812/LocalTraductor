import Foundation
import Observation
import NaturalLanguage
import AppKit
import AVFoundation

@MainActor
@Observable
final class TranslationViewModel {

    /// Pantalla actualmente visible dentro del popover.
    enum Screen {
        case translator
        case settings
    }

    // MARK: - Estado observable por la UI
    var screen: Screen = .translator
    var inputText: String = "" {
        didSet {
            if settings.autoDetectLanguage {
                updateDetectedLanguage()
            }
            handleInputChange()
        }
    }
    var outputText: String = ""
    var sourceLanguage: Language = .english {
        didSet {
            // Mantenemos source ≠ target para que el botón ⇄ tenga sentido
            // y el modelo no reciba prompts del tipo "traduce de X a X".
            if sourceLanguage == targetLanguage {
                targetLanguage = oldValue
            }
        }
    }
    var targetLanguage: Language = .spanish {
        didSet {
            if targetLanguage == sourceLanguage {
                sourceLanguage = oldValue
            }
        }
    }
    var modelState: ModelState = .idle
    var isTranslating: Bool = false

    // MARK: - Dependencias y tareas internas
    private let engine: TranslationEngine
    private let settings: AppSettings
    private var translationTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: Duration = .milliseconds(450)
    private let languageRecognizer = NLLanguageRecognizer()

    /// Último contenido del portapapeles que esta sesión ya "consumió". Sirve
    /// para que el auto-pegado al abrir no repita el mismo texto cada vez.
    private var lastSeenClipboard: String?

    /// Síntesis de voz para el botón 🔊 — lee la traducción en alto.
    private let speechSynthesizer = AVSpeechSynthesizer()

    // MARK: - Init
    /// Recibe el motor de traducción y la fuente de preferencias.
    init(engine: TranslationEngine, settings: AppSettings = .shared) {
        self.engine = engine
        self.settings = settings
    }

    // MARK: - Carga del modelo
    func loadModel() async {
        modelState = .loading
        do {
            try await engine.loadModel()
            modelState = .ready
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Limpiar la entrada y la salida
    /// Cancela cualquier traducción en vuelo y vacía los campos de texto.
    /// La invoca el `StatusBarController` cuando el popover se cierra,
    /// si el usuario activó "Vaciar al cerrar".
    func clearInput() {
        translationTask?.cancel()
        debounceTask?.cancel()
        inputText = ""
        outputText = ""
        isTranslating = false
    }

    /// Vuelve a la pantalla del traductor (se invoca al cerrarse el popover).
    func resetToTranslator() {
        screen = .translator
    }

    // MARK: - TTS (botón 🔊)

    /// Lee la traducción en voz alta con la voz nativa del idioma destino.
    /// Si ya hay una locución sonando, la corta y empieza otra.
    func speakOutput() {
        let text = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("⚠️") else { return }
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: targetLanguage.speechLocale)
        speechSynthesizer.speak(utterance)
    }

    // MARK: - Traducir el portapapeles al abrir

    /// Si el portapapeles contiene texto distinto al de la última vez que lo
    /// vimos, lo pega en `inputText` y lanza la traducción al instante.
    /// Pensado para invocarse justo antes de que el popover se muestre. No
    /// sobrescribe si el usuario ya tiene algo escrito ni si está navegando
    /// en Configuración.
    func translateClipboardOnOpenIfNeeded() {
        guard settings.translateClipboardOnOpen, screen == .translator else { return }
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Si es el mismo texto que ya consumimos, no hacemos nada.
        guard text != lastSeenClipboard else { return }
        lastSeenClipboard = text

        // No pisar lo que el usuario ya está escribiendo.
        guard inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        inputText = text
        // Si el modelo aún no está listo, translate() devolverá silenciosamente.
        translate()
    }

    // MARK: - Intercambiar idiomas (botón ⇄)
    func swapLanguages() {
        // El `didSet` de `sourceLanguage` se encarga de mover target al
        // antiguo valor de source cuando los dos coinciden, así que basta
        // con asignar el target al source.
        sourceLanguage = targetLanguage
        // Si ya hay una traducción, el texto traducido pasa a ser la entrada.
        if !outputText.isEmpty {
            inputText = outputText
        }
    }

    // MARK: - Traducción a demanda
    /// Lanza la traducción del texto actual. La invoca la UI al pulsar Enter,
    /// el botón "Traducir", o el debounce automático si está habilitado.
    /// Si ya hay una traducción en vuelo, se cancela.
    func translate() {
        translationTask?.cancel()
        debounceTask?.cancel()

        let textSnapshot = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textSnapshot.isEmpty else {
            outputText = ""
            isTranslating = false
            return
        }

        guard modelState == .ready else { return }

        isTranslating = true
        // Limpiamos para que los deltas vayan apareciendo sobre lienzo en blanco.
        outputText = ""

        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.engine.translate(
                    textSnapshot,
                    from: self.sourceLanguage,
                    to: self.targetLanguage
                )
                var buffer = ""
                for try await chunk in stream {
                    try Task.checkCancellation()
                    buffer += chunk
                    // Mostramos el buffer crudo en streaming; al terminar limpiamos.
                    self.outputText = buffer
                }
                try Task.checkCancellation()
                self.outputText = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch is CancellationError {
                // Traducción descartada por una nueva: no hacemos nada
            } catch {
                self.outputText = "⚠️ Error: \(error.localizedDescription)"
            }
            self.isTranslating = false
        }
    }

    // MARK: - Auto-traducción (debounce condicional)

    /// Reacciona a cambios de `inputText`. Solo dispara traducción automática
    /// si el usuario lo activó en Configuración.
    private func handleInputChange() {
        guard settings.autoTranslate else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounceDelay)
            guard !Task.isCancelled else { return }
            self.translate()
        }
    }

    // MARK: - Detección de idioma

    /// Detecta el idioma de `inputText` con `NLLanguageRecognizer` (on-device,
    /// gratis, sin red). Si la confianza supera 0.6, ajusta `sourceLanguage`.
    /// Texto demasiado corto (< 4 chars) se ignora porque la detección no
    /// es fiable.
    private func updateDetectedLanguage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return }

        languageRecognizer.reset()
        languageRecognizer.processString(trimmed)

        let hypotheses = languageRecognizer.languageHypotheses(withMaximum: 1)
        guard let (language, confidence) = hypotheses.first,
              confidence >= 0.6 else { return }

        let detected: Language?
        switch language {
        case .english: detected = .english
        case .spanish: detected = .spanish
        case .french: detected = .french
        case .german: detected = .german
        case .italian: detected = .italian
        case .portuguese: detected = .portuguese
        case .russian: detected = .russian
        case .japanese: detected = .japanese
        case .korean: detected = .korean
        case .arabic: detected = .arabic
        case .simplifiedChinese: detected = .chineseSimplified
        case .traditionalChinese: detected = .chineseTraditional
        default: detected = nil
        }

        if let detected, detected != sourceLanguage {
            sourceLanguage = detected
        }
    }
}
