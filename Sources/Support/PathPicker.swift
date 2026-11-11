import AppKit
import UniformTypeIdentifiers

func choosePath(directory: Bool = false, completion: @escaping (String) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = directory
    panel.canChooseFiles = !directory
    panel.allowsMultipleSelection = false
    panel.begin { result in if result == .OK, let url = panel.url { completion(url.path) } }
}

@discardableResult
func loadDroppedFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) -> Bool {
    let identifier = UTType.fileURL.identifier
    let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(identifier) }
    guard !fileProviders.isEmpty else { return false }

    let loads = DispatchGroup()
    var urls = Array<URL?>(repeating: nil, count: fileProviders.count)
    for (index, provider) in fileProviders.enumerated() {
        loads.enter()
        provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
            let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            DispatchQueue.main.async {
                if let url, url.isFileURL { urls[index] = url }
                loads.leave()
            }
        }
    }
    loads.notify(queue: .main) { completion(urls.compactMap { $0 }) }
    return true
}
