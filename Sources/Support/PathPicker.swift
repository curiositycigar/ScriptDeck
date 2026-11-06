import AppKit

func choosePath(directory: Bool = false, completion: @escaping (String) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = directory
    panel.canChooseFiles = !directory
    panel.allowsMultipleSelection = false
    panel.begin { result in if result == .OK, let url = panel.url { completion(url.path) } }
}
