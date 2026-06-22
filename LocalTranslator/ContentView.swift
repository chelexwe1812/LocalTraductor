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
        // Aplica la preferencia de modo de color del usuario. Pasa `nil` cuando
        // el usuario eligió "Sistema" para que SwiftUI siga la apariencia activa.
        .preferredColorScheme(settings.colorScheme.colorScheme)
        // `TextEditor` envuelve un `NSTextView` que cachea sus colores cuando
        // cambia la apariencia en caliente: el fondo se actualiza pero las
        // letras se quedan con el color anterior. Forzar la identidad de la
        // jerarquía al cambiar el tema obliga a SwiftUI a destruir y recrear
        // los NSTextView para que se reinicialicen con los colores correctos.
        // El coste (perder foco/scroll) es aceptable porque cambiar de tema
        // es una acción rara.
        .id(settings.colorScheme)
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
        // Tres bloques verticales (entrada / salida / barra de acciones)
        // separados solo por un `Divider` del sistema. Nada de tarjetas,
        // ambos cuadros de texto ocupan todo el ancho.
        VStack(spacing: 0) {
            inputArea
            Divider()
            outputArea
            Divider()
            bottomBar
        }
        .overlay(alignment: .top) { statusOverlay }
    }

    // MARK: - Entrada
    @ViewBuilder
    private var inputArea: some View {
        // Necesitamos `@Bindable` local porque `viewModel` viene del environment.
        @Bindable var bindable = viewModel

        TextEditor(text: $bindable.inputText)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Sin background aquí: el tinte del input se aplica a nivel
            // popover en `StatusBarController` para que la flecha que apunta
            // al icono del menubar comparta color con esta sección.
            .onKeyPress(.return) {
                // Shift+Enter inserta nueva línea; Enter solo dispara traducción.
                if NSEvent.modifierFlags.contains(.shift) {
                    return .ignored
                }
                viewModel.translate()
                return .handled
            }
    }

    // MARK: - Salida
    private var outputArea: some View {
        ScrollView {
            Text(viewModel.outputText.isEmpty ? " " : viewModel.outputText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Progress + copia como overlay en la esquina superior derecha,
        // así no roban espacio vertical al texto traducido.
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                if viewModel.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
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
            .padding(8)
        }
    }

    // MARK: - Barra inferior (pickers + acciones)
    private var bottomBar: some View {
        @Bindable var bindable = viewModel

        return HStack(spacing: 10) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
