import Foundation

/// The cleanup targets. The target lists follow the ones PureMac and Mole use (both MIT).
enum CleanupCatalog {
    /// Folders inside ~/Library/Caches that have their own category.
    private static let cachesHandledElsewhere: Set<String> = [
        "Homebrew", "pip", "CocoaPods", "Yarn",
        "com.apple.Safari", "Google", "Firefox", "Microsoft Edge",
    ]

    static let all: [CleanupCategory] = [
        .init(
            id: "userCaches", name: "User Caches",
            detail: "Temporary data apps store in ~/Library/Caches. Apps rebuild it when needed.",
            symbol: "internaldrive",
            targets: [.init("~/Library/Caches", excluding: cachesHandledElsewhere)],
            defaultSelected: true, mode: .trash
        ),
        .init(
            id: "userLogs", name: "User Logs",
            detail: "Diagnostic logs written by apps.",
            symbol: "doc.text",
            targets: [.init("~/Library/Logs")],
            defaultSelected: true, mode: .trash
        ),
        .init(
            id: "xcode", name: "Xcode Junk",
            detail: "DerivedData, old device support files and simulator caches.",
            symbol: "hammer",
            targets: [
                .init("~/Library/Developer/Xcode/DerivedData"),
                .init("~/Library/Developer/Xcode/iOS DeviceSupport"),
                .init("~/Library/Developer/CoreSimulator/Caches"),
            ],
            defaultSelected: true, mode: .trash
        ),
        .init(
            id: "xcodeArchives", name: "Xcode Archives",
            detail: "Archived app builds. Keep these if you need to symbolicate crash logs.",
            symbol: "archivebox",
            targets: [.init("~/Library/Developer/Xcode/Archives")],
            defaultSelected: false, mode: .trash
        ),
        .init(
            id: "homebrew", name: "Homebrew Cache",
            detail: "Downloaded bottles and source archives.",
            symbol: "mug",
            targets: [.init("~/Library/Caches/Homebrew")],
            defaultSelected: true, mode: .trash
        ),
        .init(
            id: "devCaches", name: "Developer Caches",
            detail: "Package caches for npm, pip, Yarn, CocoaPods and Gradle.",
            symbol: "shippingbox",
            targets: [
                .init("~/.npm/_cacache"),
                .init("~/Library/Caches/pip"),
                .init("~/Library/Caches/Yarn"),
                .init("~/.cache/yarn"),
                .init("~/Library/Caches/CocoaPods"),
                .init("~/.gradle/caches"),
            ],
            defaultSelected: true, mode: .trash
        ),
        .init(
            id: "browserCaches", name: "Browser Caches",
            detail: "Cache files only. History, cookies, passwords and profiles are never touched.",
            symbol: "globe",
            targets: [
                .init("~/Library/Caches/com.apple.Safari"),
                .init("~/Library/Caches/Google/Chrome"),
                .init("~/Library/Caches/Firefox/Profiles"),
                .init("~/Library/Caches/Microsoft Edge"),
            ],
            defaultSelected: false, mode: .trash
        ),
        .init(
            id: "mailDownloads", name: "Mail Downloads",
            detail: "Attachments that Mail saved when you opened them.",
            symbol: "paperclip",
            targets: [.init("~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads")],
            defaultSelected: false, mode: .trash
        ),
        .init(
            id: "trash", name: "Empty Trash",
            detail: "Permanently deletes everything in your Trash. This can't be undone.",
            symbol: "trash",
            targets: [.init("~/.Trash")],
            defaultSelected: false, mode: .permanent
        ),
        .init(
            id: "systemLogs", name: "System Logs (view only)",
            detail: "Logs owned by macOS. Shown for information; cleaning them needs admin rights.",
            symbol: "lock.doc",
            targets: [.init("/Library/Logs"), .init("/private/var/log")],
            defaultSelected: false, mode: .listOnly
        ),
    ]
}
