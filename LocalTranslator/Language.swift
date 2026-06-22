import Foundation

enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case russian = "ru"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"

    var id: String { rawValue }

    /// Nombre legible para mostrar en la UI (en su propio idioma).
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .russian: return "Русский"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .arabic: return "العربية"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        }
    }

    /// Nombre del idioma en inglés (para construir prompts consistentes
    /// hacia el modelo, que recibe sus instrucciones en inglés).
    var englishName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .arabic: return "Arabic"
        case .chineseSimplified: return "Simplified Chinese"
        case .chineseTraditional: return "Traditional Chinese"
        }
    }

    /// Etiqueta legible que combina el nombre en inglés con el nombre en
    /// el idioma propio entre paréntesis. Útil para reconocer idiomas
    /// cuyo nombre nativo está en alfabetos no latinos.
    /// Si ambos coinciden (caso del inglés), se muestra solo uno.
    var displayLabel: String {
        englishName == displayName ? englishName : "\(englishName) (\(displayName))"
    }

    /// Identificador BCP-47 con región, para que `AVSpeechSynthesisVoice`
    /// elija la voz adecuada al reproducir el texto.
    var speechLocale: String {
        switch self {
        case .english: return "en-US"
        case .spanish: return "es-ES"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        case .italian: return "it-IT"
        case .portuguese: return "pt-PT"
        case .russian: return "ru-RU"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .arabic: return "ar-SA"
        case .chineseSimplified: return "zh-CN"
        case .chineseTraditional: return "zh-TW"
        }
    }
}
