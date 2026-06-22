import SwiftUI

struct ContentView: View {
    // El ViewModel ahora vive en LocalTranslatorApp para sobrevivir a
    // ocultar/mostrar la ventana sin recargar el modelo.
    @Environment(TranslationViewModel.self) private var viewModel
    private let settings = AppSettings.shared

    var body: some View {
        Group {
            switch viewModel.screen {
            case .translator:
                translatorView
            case .settings:
                SettingsView(onBack: { viewModel.screen = .translator })
            }
        }
        .frame(width: 460, height: 400)
        .onChange(of: viewModel.isTranslating) { wasTranslating, isTranslating in
            // Auto-copy: copiamos solo cuando la traducción termina (no en
            // cada delta de streaming, que machacaría el portapapeles).
            guard wasTranslating, !isTranslating else { return }
            let text = viewModel.outputText
            guard settings.autoCopy,
                  !text.isEmpty,
                  !text.hasPrefix("⚠️") else { return }
            copyToClipboard(text)
        }
    }

    // MARK: - Vista del traductor
    private var translatorView: some View {
        @Bindable var bindable = viewModel

        return VStack(spacing: 16) {
            // Zona de entrada
            inputArea

            // Zona de salida
            outputArea

            // Barra inferior: pickers de idioma + swap (izquierda) | clear + settings (derecha)
            HStack(spacing: 10) {
                languagePicker(selection: $bindable.sourceLanguage, includeAutoDetect: true)

                Button {
                    viewModel.swapLanguages()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Intercambiar idiomas")

                languagePicker(selection: $bindable.targetLanguage, includeAutoDetect: false)

                Spacer()

                Button {
                    viewModel.clearInput()
                } label: {
                    Image(systemName: "eraser")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.inputText.isEmpty && viewModel.outputText.isEmpty)
                .help("Limpiar entrada y traducción")

                Button {
                    viewModel.screen = .settings
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Configuración")
            }
        }
        .padding(20)
        .overlay(alignment: .top) { statusOverlay }
    }

    // MARK: - Entrada
    @ViewBuilder
    private var inputArea: some View {
        // Necesitamos `@Bindable` local porque `viewModel` viene del environment.
        @Bindable var bindable = viewModel

        VStack(alignment: .trailing, spacing: 6) {
            Text("Enter para traducir · Shift+Enter para nueva línea")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            TextEditor(text: $bindable.inputText)
                .font(.body)
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .onKeyPress(.return) {
                    // Shift+Enter inserta nueva línea; Enter solo dispara traducción.
                    if NSEvent.modifierFlags.contains(.shift) {
                        return .ignored
                    }
                    viewModel.translate()
                    return .handled
                }
        }
    }

    // MARK: - Salida
    private var outputArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if viewModel.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if !viewModel.outputText.isEmpty {
                    Button {
                        copyToClipboard(viewModel.outputText)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copiar traducción")
                }
            }
            .frame(minHeight: 16)

            ScrollView {
                Text(viewModel.outputText.isEmpty ? " " : viewModel.outputText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            // Altura fija idéntica a la del input para que ambos cuadros
            // sean visualmente del mismo tamaño.
            .frame(height: 120)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            )
        }
    }

    // MARK: - Estado del modelo (banner superior)
    @ViewBuilder
    private var statusOverlay: some View {
        switch viewModel.modelState {
        case .loading:
            statusBanner(text: "Cargando modelo…", systemImage: "hourglass", color: .orange)
        case .failed(let message):
            statusBanner(text: "Error: \(message)", systemImage: "exclamationmark.triangle", color: .red)
        case .idle, .ready:
            EmptyView()
        }
    }

    private func statusBanner(text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .padding(.top, 4)
    }

    // MARK: - Picker de idioma (label clicable encima de cada cuadro)
    /// `includeAutoDetect` solo es `true` en el picker de origen; en destino
    /// no tiene sentido "Auto Detect" como idioma al que traducir.
    private func languagePicker(selection: Binding<Language>, includeAutoDetect: Bool) -> some View {
        let options = includeAutoDetect
            ? Language.allCases
            : Language.allCases.filter { $0 != .autoDetect }

        // Nota: usamos `Button`s sueltos en vez de un `Picker` dentro del
        // `Menu` porque, en macOS, la combinación renderizaba el menú vacío.
        return Menu {
            ForEach(options) { lang in
                Button {
                    selection.wrappedValue = lang
                } label: {
                    if lang == selection.wrappedValue {
                        Label(lang.displayLabel, systemImage: "checkmark")
                    } else {
                        Text(lang.displayLabel)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                // En el botón cerrado mostramos solo el nombre en inglés;
                // el nombre nativo entre paréntesis aparece dentro del menú.
                Text(selection.wrappedValue.englishName)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Utilidad
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

#Preview {
    ContentView()
        .environment(TranslationViewModel(engine: MockEngine()))
}
