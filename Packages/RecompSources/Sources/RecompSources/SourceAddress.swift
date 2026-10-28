import Foundation

struct RomMAddress: Sendable {
    let base: URL
    init(_ address: String, allowHTTP: Bool) throws {
        let url = try validatedURL(address)
        guard url.scheme == "https" || (url.scheme == "http" && allowHTTP) else {
            throw LibraryError.message("Enter an https:// RomM URL, or enable HTTP for this connection.")
        }
        // Accept an instance URL or a copied /api URL, including reverse-proxy prefixes.
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = path.split(separator: "/").map(String.init)
        try parts.forEach(validateComponent)
        base = url.lastPathComponent == "api" ? url.deletingLastPathComponent() : url
    }

    func endpoint(_ components: [String], query: [URLQueryItem] = []) throws -> URL {
        var url = base.appendingPathComponent("api", isDirectory: true)
        for component in components {
            try validateComponent(component)
            url.appendPathComponent(component, isDirectory: false)
        }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw LibraryError.message("The RomM URL is invalid.")
        }
        parts.queryItems = query.isEmpty ? nil : query
        guard let result = parts.url else { throw LibraryError.message("The RomM URL is invalid.") }
        return result
    }
}

struct SMBAddress: Sendable {
    let server: URL
    let share: String
    let root: String

    init(_ address: String) throws {
        let url = try validatedURL(address)
        guard url.scheme == "smb" else {
            throw LibraryError.message("Enter smb://server/share, optionally followed by a folder.")
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let share = parts.first else {
            throw LibraryError.message("Include the share name: smb://server/share.")
        }
        try parts.forEach(validateComponent)
        self.share = share
        root = parts.dropFirst().joined(separator: "/")
        guard var serverParts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw LibraryError.message("The SMB URL is invalid.")
        }
        serverParts.path = ""
        guard let server = serverParts.url else { throw LibraryError.message("The SMB URL is invalid.") }
        self.server = server
    }

    func path(_ location: LibraryLocation) throws -> String {
        let path: String
        switch location {
        case .root: return root
        case .directory(let value): path = value
        case .rom, .platform: throw LibraryError.message("This location does not belong to an SMB share.")
        }
        try path.split(separator: "/", omittingEmptySubsequences: false).map(String.init).forEach(validateComponent)
        guard root.isEmpty || path == root || path.hasPrefix(root + "/") else {
            throw LibraryError.message("The folder is outside the configured share folder.")
        }
        return path
    }

    func child(_ name: String, in parent: String) throws -> String {
        try validateComponent(name)
        return parent.isEmpty ? name : parent + "/" + name
    }
}

private func validatedURL(_ text: String) throws -> URL {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parts = URLComponents(string: text), let url = parts.url,
          let host = parts.host, !host.isEmpty,
          parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
          parts.port.map({ (1...65535).contains($0) }) ?? true,
          !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
        throw LibraryError.message("Enter a server URL without credentials, query parameters or a fragment.")
    }
    return url
}

func validateComponent(_ value: String) throws {
    guard !value.isEmpty, value != ".", value != "..",
          !value.contains("/"), !value.contains("\\"),
          !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
        throw LibraryError.message("The server returned an invalid file or folder name.")
    }
}
