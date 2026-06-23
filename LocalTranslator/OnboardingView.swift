import SwiftUI
import AppKit
import KeyboardShortcuts

/// Pantalla de bienvenida que se muestra solo la primera vez que se abre
/// LocalTranslator (ver `AppSettings.hasCompletedOnboarding`). Da contexto
/// rápido sobre el atajo global, el permiso de Input Monitoring y los
/// toggles más útiles. Al pulsar "Empezar a usar" se marca el flag y se
/// pasa al traductor.
struct OnboardingView: View {
    @Bindable var settings = AppSettings.shared
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    shortcutSection
                    permissionsSection
                    togglesSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }

            Divider()

            // Pie con el botón principal: Enter también lo dispara para que
            // los usuarios de teclado terminen sin tocar el ratón.
            HStack {
                Spacer()
                Button(action: onFinish) {
                    Text("Empezar a usar")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                Spacer()
            }
            .padding(12)
        }
    }

    // MARK: - Cabecera (icono + bienvenida)
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.tint)
            Text("Bienvenido a LocalTranslator")
                .font(.title3.bold())
            Text("Traductor en tu menú, offline. Tu texto nunca sale de este Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    // MARK: - Atajo global
    private var shortcutSection: some View {
        sectionCard(title: "Atajo global", systemImage: "command") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Abre LocalTranslator desde cualquier app. Puedes cambiar el atajo cuando quieras.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Mostrar / ocultar")
                        .font(.callout)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleTranslator)
                }
            }
        }
    }

    // MARK: - Permisos
    private var permissionsSection: some View {
        sectionCard(title: "Permisos", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Si macOS te pide acceso para detectar el atajo global, concédelo desde Ajustes del Sistema → Privacidad y Seguridad → Input Monitoring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    openInputMonitoringSettings()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Abrir Ajustes del Sistema")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Toggles más útiles
    private var togglesSection: some View {
        sectionCard(title: "Tus preferencias", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Detectar el idioma automáticamente", isOn: $settings.autoDetectLanguage)
                Toggle("Traducir el portapapeles al abrir", isOn: $settings.translateClipboardOnOpen)
                Toggle("Vaciar al cerrar", isOn: $settings.clearOnDismiss)
                Toggle("Copiar la traducción al portapapeles", isOn: $settings.autoCopy)
                Text("Puedes cambiarlas en cualquier momento desde el icono ⚙︎.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Tarjeta de sección
    /// Caja con título e icono, contenido arbitrario debajo. Usamos un
    /// fondo gris semitransparente que se adapta automáticamente al modo
    /// claro/oscuro.
    @ViewBuilder
    private func sectionCard<Content: View>(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Abrir Ajustes del Sistema en el panel correcto
    private func openInputMonitoringSettings() {
        // URL profundo al panel de Input Monitoring. Si macOS no la
        // reconoce, caemos al panel general de Privacidad y Seguridad.
        let primary = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security")
        if let primary, NSWorkspace.shared.open(primary) { return }
        if let fallback { NSWorkspace.shared.open(fallback) }
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .frame(width: 460, height: 400)
}
