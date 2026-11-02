import Foundation
import SwiftUI

// MARK: - Origen de la etiqueta IA

enum AILabelSource {
    /// El autor activó el interruptor a mano
    static let creator = "creator"
    /// Detectado en los metadatos del archivo y mantenido al publicar
    static let metadata = "metadata"

    /// Origen a guardar según el estado del interruptor al publicar.
    static func resolve(isOn: Bool, autoDetected: Bool) -> String? {
        guard isOn else { return nil }
        return autoDetected ? metadata : creator
    }
}

// MARK: - Detección en metadatos (C2PA / IPTC)

/// Busca huellas de IA en los bytes originales del archivo:
/// - marca IPTC `trainedAlgorithmicMedia` / `compositeWithTrainedAlgorithmicMedia` (XMP o C2PA);
/// - parámetros que guardan las herramientas de difusión (Stable Diffusion, ComfyUI, InvokeAI, NovelAI);
/// - manifiesto C2PA firmado por un generador de imágenes conocido.
enum AIContentProvenance {
    private static let windowSize = 8 * 1024 * 1024

    /// Basta con encontrar una de estas.
    private static let markers: [Data] = [
        "rainedAlgorithmicMedia", "\"class_type\"", "invokeai_metadata", "sd-metadata", "NovelAI",
    ].map { Data($0.utf8) }

    /// Tienen que aparecer las dos.
    private static let markerPairs: [(Data, Data)] = [
        ("Steps: ", "Sampler: "),
        ("c2pa", "OpenAI"),
        ("c2pa", "Adobe Firefly"),
        ("c2pa", "Google AI"),
    ].map { (Data($0.0.utf8), Data($0.1.utf8)) }

    private static func containsMarker(_ data: Data) -> Bool {
        if markers.contains(where: { data.range(of: $0) != nil }) { return true }
        return markerPairs.contains { data.range(of: $0.0) != nil && data.range(of: $0.1) != nil }
    }

    /// Escanea los primeros y últimos 8 MB. Nunca lanza; ante error devuelve false.
    static func isAIGenerated(data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        if data.count <= windowSize * 2 { return containsMarker(data) }
        if containsMarker(data.prefix(windowSize)) { return true }
        return containsMarker(data.suffix(windowSize))
    }

    /// Variante para archivos en disco: lee solo la cabecera y la cola.
    static func isAIGenerated(fileURL: URL) -> Bool {
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            guard size > 0 else { return false }
            try handle.seek(toOffset: 0)
            if size <= UInt64(windowSize * 2) {
                guard let data = try handle.readToEnd() else { return false }
                return containsMarker(data)
            }
            if let head = try handle.read(upToCount: windowSize), containsMarker(head) { return true }
            try handle.seek(toOffset: size - UInt64(windowSize))
            if let tail = try handle.read(upToCount: windowSize), containsMarker(tail) { return true }
            return false
        } catch {
            return false
        }
    }

    /// Ejecuta la detección fuera del hilo principal.
    static func detect(data: Data) async -> Bool {
        await Task.detached(priority: .utility) {
            AIContentProvenance.isAIGenerated(data: data)
        }.value
    }

    static func detect(fileURL: URL) async -> Bool {
        await Task.detached(priority: .utility) {
            AIContentProvenance.isAIGenerated(fileURL: fileURL)
        }.value
    }
}

// MARK: - Insignia "Info de IA"

/// Texto compacto con icono; el toque lo gestiona quien lo usa.
struct AIContentBadgeLabel: View {
    var foreground: Color
    var fontSize: CGFloat = legacyPoppinsSize(12)
    var iconSize: CGFloat = 11

    var body: some View {
        HStack(spacing: 4) {
            Image("AILabelIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize + 2, height: iconSize + 2)
            Text(NSLocalizedString("ai.badge", comment: "AI info badge"))
                .font(.system(size: fontSize))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Insignia que abre por sí misma la hoja informativa.
struct AIContentBadgeButton: View {
    let source: String?
    var foreground: Color
    var fontSize: CGFloat = legacyPoppinsSize(12)
    var iconSize: CGFloat = 11

    @State private var showingInfo = false

    var body: some View {
        Button {
            showingInfo = true
        } label: {
            AIContentBadgeLabel(foreground: foreground, fontSize: fontSize, iconSize: iconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingInfo) {
            AIContentInfoSheet(source: source)
        }
    }
}

// MARK: - Hoja informativa

struct AIContentInfoSheet: View {
    let source: String?

    @Environment(\.colorScheme) private var colorScheme

    private var primaryColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.55)
    }

    private var bodyKey: String {
        source == AILabelSource.metadata ? "ai.info.metadata" : "ai.info.creator"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image("AILabelIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(NSLocalizedString("ai.info.title", comment: "AI info sheet title"))
                    .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
            }
            .foregroundStyle(primaryColor)

            Text(NSLocalizedString(bodyKey, comment: "AI info sheet body"))
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(primaryColor)
                .fixedSize(horizontal: false, vertical: true)

            Text(NSLocalizedString("ai.info.footer", comment: "AI info sheet footer"))
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundStyle(secondaryColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}
