import SwiftUI
import UniformTypeIdentifiers
import AppKit

@MainActor
final class AppModel: ObservableObject {
    @Published var simulators: [Simulator] = []
    @Published var selectedIDs: Set<String> = []
    @Published var mediaURLs: [URL] = []
    @Published var statusMessage: String?
    @Published var isError = false
    @Published var isLoadingSimulators = false
    @Published var isAdding = false
    @Published var isTargeted = false

    func refreshSimulators(preferBootedSelection: Bool = false) async {
        isLoadingSimulators = true
        defer { isLoadingSimulators = false }

        do {
            let devices = try await SimCtlService.listDevices()
            simulators = devices

            if preferBootedSelection || selectedIDs.isEmpty {
                let booted = Set(devices.filter(\.isBooted).map(\.id))
                selectedIDs = booted.isEmpty ? Set(devices.prefix(1).map(\.id)) : booted
            } else {
                selectedIDs = selectedIDs.intersection(Set(devices.map(\.id)))
                if selectedIDs.isEmpty {
                    let booted = Set(devices.filter(\.isBooted).map(\.id))
                    selectedIDs = booted.isEmpty ? Set(devices.prefix(1).map(\.id)) : booted
                }
            }
        } catch {
            isError = true
            statusMessage = error.localizedDescription
        }
    }

    func addDroppedURLs(_ urls: [URL]) {
        let supported = urls.filter(SimCtlService.isSupportedMedia)
        guard !supported.isEmpty else {
            isError = true
            statusMessage = "Unsupported file type. Use photos, videos, or vCards."
            return
        }

        var existing = Set(mediaURLs.map(\.path))
        for url in supported where !existing.contains(url.path) {
            mediaURLs.append(url)
            existing.insert(url.path)
        }

        isError = false
        statusMessage = "\(mediaURLs.count) file\(mediaURLs.count == 1 ? "" : "s") ready"
    }

    func removeMedia(_ url: URL) {
        mediaURLs.removeAll { $0 == url }
    }

    func clearMedia() {
        mediaURLs.removeAll()
        statusMessage = nil
        isError = false
    }

    func selectAllBooted() {
        selectedIDs = Set(simulators.filter(\.isBooted).map(\.id))
    }

    func selectAll() {
        selectedIDs = Set(simulators.map(\.id))
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    func addMediaToSelected() async {
        let selected = simulators.filter { selectedIDs.contains($0.id) }
        isAdding = true
        defer { isAdding = false }

        do {
            let result = try await SimCtlService.addMedia(paths: mediaURLs, to: selected)
            isError = false
            statusMessage = result
        } catch {
            isError = true
            statusMessage = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                dropColumn
                    .frame(minWidth: 260)
                Divider()
                simulatorColumn
                    .frame(minWidth: 240)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.refreshSimulators(preferBootedSelection: true)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sim Media Drop")
                    .font(.headline)
                Text("Drop photos or videos, pick simulators, add in one click")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refreshSimulators() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoadingSimulators || model.isAdding)
        }
        .padding(16)
    }

    private var dropColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Media")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            DropZoneView(isTargeted: $model.isTargeted) { urls in
                model.addDroppedURLs(urls)
            }
            .frame(maxWidth: .infinity, minHeight: 140)

            if !model.mediaURLs.isEmpty {
                List {
                    ForEach(model.mediaURLs, id: \.path) { url in
                        HStack(spacing: 8) {
                            Image(systemName: iconName(for: url))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.removeMedia(url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(maxHeight: 180)

                Button("Clear files") {
                    model.clearMedia()
                }
                .buttonStyle(.borderless)
            }

            Button {
                pickFiles()
            } label: {
                Label("Choose files…", systemImage: "folder")
            }
            .disabled(model.isAdding)
        }
        .padding(16)
    }

    private var simulatorColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Simulators")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu("Select") {
                    Button("Booted only") { model.selectAllBooted() }
                    Button("All") { model.selectAll() }
                    Button("None") { model.deselectAll() }
                }
                .menuStyle(.borderlessButton)
            }

            if model.isLoadingSimulators && model.simulators.isEmpty {
                ProgressView("Loading simulators…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.simulators.isEmpty {
                ContentUnavailableView(
                    "No simulators",
                    systemImage: "iphone.slash",
                    description: Text("Create or download a simulator in Xcode.")
                )
            } else {
                List(selection: $model.selectedIDs) {
                    ForEach(model.simulators) { simulator in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(simulator.isBooted ? Color.green : Color.secondary.opacity(0.35))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(simulator.name)
                                Text("\(simulator.displayRuntime) · \(simulator.state)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(simulator.id)
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let status = model.statusMessage {
                Text(status)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(model.isError ? Color.red : Color.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text(summaryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await model.addMediaToSelected() }
                } label: {
                    if model.isAdding {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("Adding…")
                    } else {
                        Label("Add to Simulators", systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.isAdding
                        || model.mediaURLs.isEmpty
                        || model.selectedIDs.isEmpty
                )
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
    }

    private var summaryLabel: String {
        let files = model.mediaURLs.count
        let sims = model.selectedIDs.count
        return "\(files) file\(files == 1 ? "" : "s") → \(sims) simulator\(sims == 1 ? "" : "s")"
    }

    private func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v", "avi", "mkv"].contains(ext) {
            return "video"
        }
        if ext == "vcf" {
            return "person.crop.circle"
        }
        return "photo"
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .image, .movie, .mpeg4Movie, .quickTimeMovie, .vCard,
            UTType(filenameExtension: "heic") ?? .image
        ].compactMap { $0 }

        if panel.runModal() == .OK {
            model.addDroppedURLs(panel.urls)
        }
    }
}

struct DropZoneView: View {
    @Binding var isTargeted: Bool
    var onDrop: ([URL]) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                )

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                Text("Drop photos or videos here")
                    .font(.callout.weight(.medium))
                Text("jpg, png, heic, mov, mp4, vcf…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                let urls = await loadURLs(from: providers)
                await MainActor.run {
                    onDrop(urls)
                }
            }
            return true
        }
    }

    private func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadFileURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 640, height: 520)
}
