import SwiftUI

struct ContentView: View {
    // El ViewModel ahora vive en LocalTranslatorApp para sobrevivir a
    // ocultar/mostrar la ventana sin recargar el modelo.
    @Environment(TranslationViewModel.self) private var viewModel
    private let settings = AppSettings.shared

    /// ID estable del ancla al final del scroll de salida. Lo usa
    /// `ScrollViewReader` para hacer auto-scroll mientras llega el stream.
    private let outputBottomID = "outputBottom"

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
        // Fuerza el idioma de la interfaz para que `Text("…")` busque las
        // traducciones en el catálogo aunque macOS esté en otro idioma.
        .environment(\.locale, settings.appLanguage.locale)
        // `TextEditor` envuelve un `NSTextView` que cachea sus colores cuando
        // cambia la apariencia en caliente: el fondo se actualiza pero las
        // letras se quedan con el color anterior. Forzar la identidad de la
        // jerarquía al cambiar el tema obliga a SwiftUI a destruir y recrear
        // los NSTextView para que se reinicialicen con los colores correctos.
        // El coste (perder foco/scroll) es aceptable porque cambiar de tema
        // es una acción rara. También re-identificamos al cambiar de idioma
        // para forzar el re-render de las strings localizadas.
        .id("\(settings.colorScheme.rawValue)-\(settings.appLanguage.rawValue)")
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
        .onChange(of: settings.translationTone) { _, _ in
            // Al cambiar de tono, re-traducimos al instante si hay algo que
            // traducir. Si el input está vacío no hacemos nada para no
            // disparar trabajo inútil. El feedback visual (borde arcoíris)
            // lo dispara `SiriGlow` al ver `isTranslating = true`.
            let trimmed = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            viewModel.translate()
        }
    }

    // MARK: - Vista del traductor
    private var translatorView: some View {
        // Tres bloques verticales (entrada / salida + barra de acciones).
        // La posición de la barra (arriba o abajo) la elige el usuario en
        // Configuración. Sin tarjetas: ambos cuadros ocupan todo el ancho.
        VStack(spacing: 0) {
            if settings.toolbarPosition == .top {
                bottomBar
                Divider()
                inputArea
                Divider()
                outputArea
            } else {
                inputArea
                Divider()
                outputArea
                Divider()
                bottomBar
            }
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
        // `ScrollViewReader` para poder hacer auto-scroll al final mientras
        // van llegando los chunks de streaming en traducciones largas.
        ScrollViewReader { proxy in
            ScrollView {
                Text(viewModel.outputText.isEmpty ? " " : viewModel.outputText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                // Ancla invisible al final del contenido: `scrollTo` la
                // posiciona al borde inferior del viewport, dejando el
                // último trozo de texto siempre visible.
                Color.clear
                    .frame(height: 1)
                    .id(outputBottomID)
            }
            .onChange(of: viewModel.outputText) { _, _ in
                // Animación corta para que el desplazamiento siga al texto
                // sin parecer brusco con cada chunk del stream.
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(outputBottomID, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Borde arcoíris estilo Siri: aparece cuando arranca una traducción
        // y se desvanece cuando termina. El overlay no captura clics.
        .overlay { SiriGlow(isTranslating: viewModel.isTranslating) }
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
    /// Prioridad de espacio: los nombres de los idiomas mandan. Solo cuando
    /// quepa la etiqueta del tono junto al icono ✦, `ViewThatFits` la incluye;
    /// en caso contrario, cae a la variante compacta con solo icono.
    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            barContent(showToneLabel: true)
            barContent(showToneLabel: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func barContent(showToneLabel: Bool) -> some View {
        @Bindable var bindable = viewModel

        HStack(spacing: 10) {
            languagePicker(selection: $bindable.sourceLanguage, includeAutoDetect: true)

            Button {
                viewModel.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Intercambiar idiomas")

            languagePicker(selection: $bindable.targetLanguage, includeAutoDetect: false)

            // `minLength` evita que el Spacer se colapse a 0 dentro de
            // `ViewThatFits`: así la variante con etiqueta solo "cabe" si
            // queda hueco real entre los pickers y los iconos de acción.
            Spacer(minLength: 8)

            toneMenu(showLabel: showToneLabel)

            Button {
                viewModel.clearInput()
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.inputText.isEmpty && viewModel.outputText.isEmpty)
            .help("Limpiar entrada y traducción")

            Button {
                viewModel.screen = .settings
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Configuración")
        }
    }

    // MARK: - Estado del modelo (banner superior)
    @ViewBuilder
    private var statusOverlay: some View {
        switch viewModel.modelState {
        case .loading:
            statusBanner("Cargando modelo…", systemImage: "hourglass", color: .orange)
        case .failed(let message):
            // La interpolación produce una `LocalizedStringKey` con clave
            // "Error: %@", que coincide con la entrada del catálogo.
            statusBanner("Error: \(message)", systemImage: "exclamationmark.triangle", color: .red)
        case .idle, .ready:
            EmptyView()
        }
    }

    private func statusBanner(_ key: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        Label(key, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .padding(.top, 4)
    }

    // MARK: - Menú de tono de traducción
    /// Selector con estrella (✦) que cambia el registro con el que el modelo
    /// devuelve la traducción. Si `showLabel` es `true` muestra también el
    /// nombre del tono activo al lado del icono; si no, solo icono. La
    /// decisión la toma `ViewThatFits` en `bottomBar` según el espacio
    /// disponible (los nombres de los idiomas tienen prioridad).
    private func toneMenu(showLabel: Bool) -> some View {
        Menu {
            ForEach(TranslationTone.allCases) { tone in
                Button {
                    settings.translationTone = tone
                } label: {
                    if tone == settings.translationTone {
                        Label(tone.displayName, systemImage: "checkmark")
                    } else {
                        Text(tone.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                if showLabel {
                    Text(settings.translationTone.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tono de traducción")
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

/// Borde estilo Siri que envuelve el área de salida mientras dura una
/// traducción. Diseño:
/// - `TimelineView(.animation)` redibuja cada frame con un `AngularGradient`
///   cuyo `angle` depende del tiempo. Así el gradiente *rota* en su sitio en
///   vez de cambiar de matiz, lo que evita pasar por verdes (problema típico
///   de `hueRotation`, que cicla por TODO el espectro).
/// - Dos `strokeBorder` superpuestos: el exterior es ancho y muy difuminado
///   (halo) y el interior es más fino y un poco menos difuminado (perfil).
///   Esa combinación da el aspecto luminoso/dramático tipo Siri.
/// - La paleta es la "siri-ish" pedida: rosas, rojos, amarillo, blanco,
///   celestes y morados. Sin mint / verde.
///
/// La animación se monta solo mientras `rendered == true`, así no malgasta
/// CPU cuando no está traduciendo.
private struct SiriGlow: View {
    let isTranslating: Bool

    /// Mantiene el `TimelineView` montado durante el fade-in y fade-out.
    /// Se pone a `false` al terminar el fade-out (vía `completion:`).
    @State private var rendered: Bool = false
    @State private var opacity: Double = 0
    @State private var startDate: Date = .distantPast
    /// Invalida `completion:` de animaciones previas si la traducción
    /// reinicia mientras se estaba desvaneciendo el efecto.
    @State private var generation: Int = 0

    /// Velocidad de giro del gradiente, en grados por segundo.
    private let rotationSpeed: Double = 220

    /// Paleta Siri: rosas, rojos, amarillo cálido, blanco, celestes,
    /// morados. Nada de mint. Termina en el mismo morado para que la
    /// transición al envolver sea suave.
    private let siriColors: [Color] = [
        .purple, .pink, .red, .yellow, .white, .cyan, .blue, .indigo, .purple
    ]

    var body: some View {
        ZStack {
            if rendered {
                TimelineView(.animation) { timeline in
                    let angle = timeline.date.timeIntervalSince(startDate) * rotationSpeed
                    let gradient = AngularGradient(
                        colors: siriColors,
                        center: .center,
                        angle: .degrees(angle)
                    )
                    ZStack {
                        // Halo exterior: ancho y muy difuminado.
                        Rectangle()
                            .strokeBorder(gradient, lineWidth: 10)
                            .blur(radius: 12)
                            .opacity(0.45)
                        // Perfil interior: más fino, define el borde.
                        Rectangle()
                            .strokeBorder(gradient, lineWidth: 4)
                            .blur(radius: 3)
                    }
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .onChange(of: isTranslating) { _, newValue in
            if newValue {
                start()
            } else {
                stop()
            }
        }
    }

    private func start() {
        generation &+= 1
        rendered = true
        startDate = Date()
        withAnimation(.easeOut(duration: 0.25)) {
            opacity = 1.0
        }
    }

    private func stop() {
        generation &+= 1
        let myGen = generation
        withAnimation(.easeIn(duration: 0.55)) {
            opacity = 0
        } completion: {
            // Si la traducción volvió a arrancar antes de terminar el
            // fade-out, no desmontamos: una nueva start() ya está activa.
            if myGen == generation {
                rendered = false
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(TranslationViewModel(engine: MockEngine()))
}
