import Foundation

/// Contrato que todo motor de traducción debe cumplir.
/// Hoy lo implementará un motor falso (mock); mañana, MLX con un modelo real.
/// La UI no necesita saber cuál se usa.
protocol TranslationEngine {
    /// Carga el modelo en memoria. Puede tardar, por eso es async.
    func loadModel() async throws

    /// Traduce un texto de un idioma a otro emitiendo deltas (fragmentos)
    /// según los va generando el modelo. La UI concatena los chunks para
    /// mostrar la traducción palabra a palabra.
    func translate(_ text: String,
                   from source: Language,
                   to target: Language) async throws -> AsyncThrowingStream<String, Error>
}
