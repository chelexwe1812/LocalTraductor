import SwiftUI

/// Botón compacto para intercambiar la dirección de traducción.
struct LanguageBar: View {
    let onSwap: () -> Void

    var body: some View {
        Button(action: onSwap) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .help("Intercambiar idiomas")
    }
}
