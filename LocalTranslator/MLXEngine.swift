import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Motor de traducción real. Usa MLX para correr un LLM cuantizado
/// en 4-bit sobre Apple Silicon.
///
/// La primera vez que se carga, descarga los pesos del modelo desde
/// Hugging Face (~2.5 GB para Qwen3-4B) y los guarda en caché local
/// dentro del contenedor de la app. Las siguientes veces, carga
/// directamente desde disco.
///
/// Es un `actor` para que toda la inferencia esté serializada y nunca
/// haya dos generaciones a la vez sobre el mismo modelo.
actor MLXEngine: TranslationEngine {

    // MARK: - Configuración

    /// Identificador del modelo en el repo `mlx-community` de Hugging Face.
    /// Para cambiar de modelo, basta con pasar otro ID al init.
    private let modelID: String

    /// Sesión de chat ya montada sobre el modelo cargado.
    /// La creamos una sola vez en `loadModel()` y la reutilizamos.
    private var session: ChatSession?

    init(modelID: String = "mlx-community/Qwen3-4B-Instruct-2507-4bit") {
        self.modelID = modelID
    }

    // MARK: - Carga del modelo

    func loadModel() async throws {
        print("[MLXEngine] Iniciando carga del modelo: \(modelID)")
        let configuration = ModelConfiguration(id: modelID)

        // 1) Descarga (la primera vez) + carga en memoria.
        //    Imprimimos progreso a la consola para poder ver descargas.
        let model: ModelContext
        do {
            model = try await loadMLXModelContext(for: configuration) { progress in
                let pct = Int(progress.fractionCompleted * 100)
                let done = ByteCountFormatter.string(
                    fromByteCount: progress.completedUnitCount,
                    countStyle: .file
                )
                let total = ByteCountFormatter.string(
                    fromByteCount: progress.totalUnitCount,
                    countStyle: .file
                )
                print("[MLXEngine] Descarga \(pct)% (\(done) / \(total))")
            }
        } catch {
            print("[MLXEngine] ❌ Fallo cargando modelo: \(error)")
            throw error
        }
        print("[MLXEngine] ✅ Modelo cargado en memoria")

        // 2) Parámetros de generación pensados para traducción:
        //    - temperatura baja => salida estable y poco creativa.
        //    - maxTokens generoso para textos largos.
        let parameters = GenerateParameters(
            maxTokens: 1024,
            temperature: 0.2
        )

        // 3) Instrucciones de sistema: fuerzan al modelo a devolver
        //    SOLO la traducción, sin comentarios ni comillas.
        let systemInstructions = """
        You are a precise translator between English and Spanish. \
        Output ONLY the translated text — no quotes, no explanations, \
        no preamble, no language labels. Preserve the meaning, tone, \
        punctuation and paragraph breaks of the original.
        """

        self.session = ChatSession(
            model,
            instructions: systemInstructions,
            generateParameters: parameters
        )
    }

    // MARK: - Traducción

    func translate(_ text: String,
                   from source: Language,
                   to target: Language) async throws -> AsyncThrowingStream<String, Error> {

        guard let session else { throw EngineError.modelNotLoaded }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AsyncThrowingStream { $0.finish() }
        }

        try Task.checkCancellation()

        // Cada traducción debe ser independiente: limpiamos el historial
        // para que el modelo no use traducciones previas como contexto.
        await session.clear()

        let prompt = """
        Translate the following text from \(source.englishName) \
        to \(target.englishName). Output ONLY the translation.

        \(trimmed)
        """

        // Devolvemos directamente el stream del ChatSession: la UI irá
        // concatenando los chunks conforme el modelo genera tokens.
        return session.streamResponse(to: prompt)
    }
}

// MARK: - Carga del modelo (función libre)

/// Helper a nivel de archivo para invocar el macro `#huggingFaceLoadModel`
/// fuera del actor. Hace falta porque dentro del actor `loadModel` queda
/// resuelto a nuestro método de instancia y el macro no puede expandirse.
private func loadMLXModelContext(
    for configuration: ModelConfiguration,
    progressHandler: @Sendable @escaping (Progress) -> Void
) async throws -> ModelContext {
    try await #huggingFaceLoadModel(
        configuration: configuration,
        progressHandler: progressHandler
    )
}

// MARK: - Errores propios

enum EngineError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "El modelo aún no está cargado."
        }
    }
}
