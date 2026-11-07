import Foundation
import UniformTypeIdentifiers

/// A coarse file category used by the breakdown chart, the Largest filter and the advisor.
enum FileKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case video, image, audio, archive, diskImage, application, document, developer, cache, other

    var id: Self { self }

    var title: String {
        switch self {
        case .video: return "Videos"
        case .image: return "Images"
        case .audio: return "Audio"
        case .archive: return "Archives"
        case .diskImage: return "Disk Images & VMs"
        case .application: return "Apps & Installers"
        case .document: return "Documents"
        case .developer: return "Developer Files"
        case .cache: return "Caches & Logs"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .image: return "photo"
        case .audio: return "music.note"
        case .archive: return "archivebox"
        case .diskImage: return "opticaldiscdrive"
        case .application: return "app.badge"
        case .document: return "doc.text"
        case .developer: return "hammer"
        case .cache: return "clock.arrow.circlepath"
        case .other: return "questionmark.folder"
        }
    }

    /// The kind every file inside a folder inherits, when the folder's name says what it holds
    /// (an app bundle, `node_modules`, a `Caches` folder…). `nil` means "classify each file".
    static func directoryContext(_ name: String) -> FileKind? {
        let lower = name.lowercased()
        if developerFolders.contains(lower) { return .developer }
        if lower == "caches" || lower == "logs" || lower == "cache" || lower == ".cache" { return .cache }
        let ext = (lower as NSString).pathExtension
        switch ext {
        case "app", "pkg", "mpkg": return .application
        case "xcarchive", "xcodeproj", "xcworkspace", "playground": return .developer
        case "photoslibrary", "photolibrary", "aplibrary": return .image
        case "fcpbundle", "imovielibrary", "tvlibrary", "fcpxml": return .video
        case "logicx", "band": return .audio
        case "sparsebundle", "utm", "pvm", "vmwarevm": return .diskImage
        default: return nil
        }
    }

    private static let developerFolders: Set<String> = [
        "deriveddata", "node_modules", "coresimulator", "ios devicesupport", "watchos devicesupport",
        ".gradle", "pods", ".git", ".build", "carthage", ".cargo", ".rustup", "site-packages",
        ".venv", "venv", "__pycache__", ".m2", ".npm", ".pnpm-store", ".yarn",
    ]

    /// Classifies a file by name. `context` comes from `directoryContext` of an enclosing folder.
    static func classify(fileName: String, context: FileKind? = nil, cache: inout [String: FileKind]) -> FileKind {
        if let context { return context }
        let lower = fileName.lowercased()
        if lower == "docker.raw" { return .diskImage }
        let ext = (lower as NSString).pathExtension
        if ext.isEmpty { return .other }
        if let hit = cache[ext] { return hit }
        let kind = classify(extension: ext)
        cache[ext] = kind
        return kind
    }

    /// Convenience for one-off classification (tests, advisor).
    static func classify(fileName: String, context: FileKind? = nil) -> FileKind {
        var cache: [String: FileKind] = [:]
        return classify(fileName: fileName, context: context, cache: &cache)
    }

    private static func classify(extension ext: String) -> FileKind {
        switch ext {
        case "dmg", "iso", "img", "sparseimage", "vmdk", "vdi", "qcow2", "vhd", "vhdx", "hdd": return .diskImage
        case "ipa", "pkg", "mpkg", "xip", "apk": return .application
        case "log", "crash", "ips", "diag": return .cache
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst": return .archive
        default: break
        }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .diskImage) { return .diskImage }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .application) || type.conforms(to: .executable) { return .application }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .developer }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent) || type.conforms(to: .database) {
            return .document
        }
        return .other
    }
}

/// How long ago a file was last modified.
enum AgeBucket: String, CaseIterable, Codable, Sendable, Identifiable {
    case lastMonth, lastSixMonths, lastYear, older

    var id: Self { self }

    var title: String {
        switch self {
        case .lastMonth: return "< 1 month"
        case .lastSixMonths: return "1–6 months"
        case .lastYear: return "6–12 months"
        case .older: return "> 1 year"
        }
    }

    static func bucket(for date: Date?, now: Date = Date()) -> AgeBucket {
        guard let date else { return .older }
        let days = now.timeIntervalSince(date) / 86_400
        if days < 31 { return .lastMonth }
        if days < 183 { return .lastSixMonths }
        if days < 366 { return .lastYear }
        return .older
    }
}
