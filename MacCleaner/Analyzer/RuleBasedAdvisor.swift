import Foundation

/// Offline knowledge base of well-known macOS space users. Always available; also grounds
/// the on-device model and caps how permissive its safety rating may be.
enum RuleBasedAdvisor {
    private struct Rule {
        let matches: (_ path: String, _ name: String, _ item: AdvisorItem) -> Bool
        let advice: Advice
    }

    static func advise(_ item: AdvisorItem, safety guardian: SafetyGuard = .standard) -> Advice {
        let path = item.url.abbreviatedPath.lowercased()
        let name = item.name.lowercased()
        var advice = rules.first { $0.matches(path, name, item) }?.advice ?? generic(item)

        // Locations MacCleaner refuses to remove are never "safe to delete".
        if (try? guardian.checkPolicy(SafetyGuard.lexical(item.url.path))) == nil {
            advice.safety = .keep
            advice.reasoning += " MacCleaner protects this location and won't remove it."
        }
        return advice
    }

    // MARK: Known locations

    private static func inside(_ fragment: String) -> (String, String, AdvisorItem) -> Bool {
        { path, _, _ in path.contains(fragment) }
    }

    private static func ext(_ exts: Set<String>) -> (String, String, AdvisorItem) -> Bool {
        { _, name, _ in exts.contains((name as NSString).pathExtension) }
    }

    private static let rules: [Rule] = [
        Rule(matches: inside("/library/developer/xcode/deriveddata"), advice: Advice(
            fileType: "Xcode build cache (DerivedData)",
            whatItIs: "Intermediate build products, indexes and logs Xcode creates for every project you open.",
            safety: .safeToDelete,
            reasoning: "Xcode rebuilds it automatically; the only cost is a slower first build.",
            preventGrowth: ["Delete DerivedData for projects you no longer work on.", "In Xcode › Settings › Locations you can move DerivedData to an external disk."],
            cleanupSteps: ["Quit Xcode.", "Move the DerivedData folder (or single project folders inside it) to the Trash."],
            suggestMove: false)),
        Rule(matches: inside("/library/developer/xcode/archives"), advice: Advice(
            fileType: "Xcode archives",
            whatItIs: "Builds you archived for App Store or ad-hoc distribution, including debug symbols (dSYMs).",
            safety: .reviewFirst,
            reasoning: "You need the dSYMs to symbolicate crash reports of versions that are still in users' hands.",
            preventGrowth: ["Keep only the archives of versions that are still shipped.", "Upload dSYMs to your crash reporter, then archive old .xcarchive files elsewhere."],
            cleanupSteps: ["Open Xcode › Window › Organizer › Archives.", "Delete old archives, or move them to external storage."],
            suggestMove: true)),
        Rule(matches: inside("devicesupport"), advice: Advice(
            fileType: "Device support files",
            whatItIs: "Debug symbols Xcode copies from each iOS/watchOS version you've connected a device with.",
            safety: .safeToDelete,
            reasoning: "Xcode copies them again the next time you connect a device running that OS version.",
            preventGrowth: ["Remove folders for OS versions you no longer debug on."],
            cleanupSteps: ["Delete the folders for old OS versions inside iOS DeviceSupport."],
            suggestMove: false)),
        Rule(matches: inside("/library/developer/coresimulator"), advice: Advice(
            fileType: "iOS Simulator devices and runtimes",
            whatItIs: "Simulator devices, their installed apps and data, plus caches.",
            safety: .reviewFirst,
            reasoning: "Deleting files by hand can corrupt simulators. Use Xcode's own tools instead.",
            preventGrowth: ["Remove simulator runtimes you don't test on (Xcode › Settings › Platforms).", "Run `xcrun simctl delete unavailable` after Xcode updates."],
            cleanupSteps: ["In Terminal: `xcrun simctl delete unavailable`.", "Remove old runtimes in Xcode › Settings › Platforms."],
            suggestMove: false)),
        Rule(matches: inside("/library/application support/mobilesync/backup"), advice: Advice(
            fileType: "iPhone / iPad backups",
            whatItIs: "Local Finder backups of your iOS devices.",
            safety: .reviewFirst,
            reasoning: "This may be the only copy of a device's data. Delete only backups of devices you no longer own or that are backed up to iCloud.",
            preventGrowth: ["Use iCloud Backup instead of local backups.", "Keep only the latest backup per device."],
            cleanupSteps: ["Open Finder, select the device › Manage Backups…, and delete old ones there.", "Or move the backup folder to an external drive for archival."],
            suggestMove: true)),
        Rule(matches: inside("/library/containers/com.docker.docker"), advice: Advice(
            fileType: "Docker disk image",
            whatItIs: "The virtual disk that holds all Docker images, containers and volumes.",
            safety: .reviewFirst,
            reasoning: "Deleting it removes every image, container and volume, including databases in volumes.",
            preventGrowth: ["Run `docker system prune` regularly.", "Lower the disk image size limit in Docker Desktop › Settings › Resources."],
            cleanupSteps: ["In Terminal: `docker system prune -a` (removes unused images).", "Use Docker Desktop › Troubleshoot › Clean / Purge data for a full reset."],
            suggestMove: false)),
        Rule(matches: { _, name, _ in name == "docker.raw" }, advice: Advice(
            fileType: "Docker disk image",
            whatItIs: "The virtual disk that holds all Docker images, containers and volumes.",
            safety: .reviewFirst,
            reasoning: "Deleting it removes every image, container and volume.",
            preventGrowth: ["Run `docker system prune` regularly.", "Lower the disk size limit in Docker Desktop settings."],
            cleanupSteps: ["Use `docker system prune -a` rather than deleting the file."],
            suggestMove: false)),
        Rule(matches: { path, name, _ in name == "node_modules" || path.contains("/node_modules/") }, advice: Advice(
            fileType: "JavaScript dependencies (node_modules)",
            whatItIs: "Packages installed by npm, yarn or pnpm for one project.",
            safety: .safeToDelete,
            reasoning: "They are reinstalled from package.json with `npm install`.",
            preventGrowth: ["Use pnpm, which shares one copy of each package across projects.", "Delete node_modules in projects you haven't touched for months."],
            cleanupSteps: ["Move the node_modules folder to the Trash.", "Run `npm install` when you return to the project."],
            suggestMove: false)),
        Rule(matches: { path, name, _ in [".gradle", ".m2", ".npm", ".pnpm-store", ".cargo", "pods"].contains(name) || path.contains("/.gradle/caches") }, advice: Advice(
            fileType: "Package manager cache",
            whatItIs: "Downloaded libraries cached by a build tool (Gradle, Maven, npm, CocoaPods, Cargo…).",
            safety: .safeToDelete,
            reasoning: "Everything here is re-downloaded on demand.",
            preventGrowth: ["Clean the cache periodically with the tool's own command (e.g. `npm cache clean --force`, `gradle --stop` then delete caches)."],
            cleanupSteps: ["Quit IDEs and build daemons.", "Delete the cache folder or use the tool's clean command."],
            suggestMove: false)),
        Rule(matches: inside("/library/caches/homebrew"), advice: Advice(
            fileType: "Homebrew download cache",
            whatItIs: "Bottles and source archives Homebrew downloaded.",
            safety: .safeToDelete,
            reasoning: "Installed packages don't need these files.",
            preventGrowth: ["Run `brew cleanup` after upgrades, or set HOMEBREW_CLEANUP_MAX_AGE_DAYS."],
            cleanupSteps: ["In Terminal: `brew cleanup --prune=all`."],
            suggestMove: false)),
        Rule(matches: inside("/library/caches"), advice: Advice(
            fileType: "Application cache",
            whatItIs: "Temporary data apps keep to load faster (thumbnails, downloaded web content, updates).",
            safety: .safeToDelete,
            reasoning: "Apps recreate caches as needed. Quit the app first so it doesn't write while you delete.",
            preventGrowth: ["Many apps (browsers, Spotify, Slack) let you cap cache size in their settings."],
            cleanupSteps: ["Quit the owning app.", "Use Junk Cleaner › User Caches, which empties caches but keeps the folders."],
            suggestMove: false)),
        Rule(matches: inside("/library/logs"), advice: Advice(
            fileType: "Log files",
            whatItIs: "Diagnostic logs written by apps and macOS.",
            safety: .safeToDelete,
            reasoning: "Logs are only used for troubleshooting.",
            preventGrowth: ["If one app writes huge logs, check its settings for a debug/verbose logging switch."],
            cleanupSteps: ["Use Junk Cleaner › Logs."],
            suggestMove: false)),
        Rule(matches: inside("/library/mail"), advice: Advice(
            fileType: "Mail database and attachments",
            whatItIs: "Your downloaded email messages and attachments for Apple Mail.",
            safety: .keep,
            reasoning: "Deleting files here corrupts Mail. Remove large messages from within Mail instead.",
            preventGrowth: ["In Mail › Settings › Accounts, set 'Download Attachments' to 'Recent' or 'None'."],
            cleanupSteps: ["In Mail, sort by size and delete large old messages, then empty Mail's Trash."],
            suggestMove: false)),
        Rule(matches: { _, name, _ in name.hasSuffix(".photoslibrary") }, advice: Advice(
            fileType: "Photos library",
            whatItIs: "Your Apple Photos library with originals, edits and thumbnails.",
            safety: .keep,
            reasoning: "Never edit or delete files inside the library; that can destroy photos.",
            preventGrowth: ["Turn on iCloud Photos with 'Optimize Mac Storage' to keep only previews locally.", "Delete unwanted videos and screenshots in Photos, then empty Recently Deleted."],
            cleanupSteps: ["Move the whole library to an external drive with Photos closed, then open it from there (hold ⌥ when launching Photos)."],
            suggestMove: true)),
        Rule(matches: { path, name, _ in path.contains("/library/messages") }, advice: Advice(
            fileType: "Messages history and attachments",
            whatItIs: "Your iMessage/SMS history and the photos and videos in it.",
            safety: .keep,
            reasoning: "Deleting files here removes conversation media.",
            preventGrowth: ["Settings › Messages: keep messages for 1 year instead of forever.", "Turn on Messages in iCloud."],
            cleanupSteps: ["System Settings › General › Storage › Messages lets you delete large attachments safely."],
            suggestMove: false)),
        Rule(matches: { path, _, item in path.hasPrefix("~/downloads/") && ["dmg", "pkg", "zip", "iso", "xip"].contains((item.name.lowercased() as NSString).pathExtension) }, advice: Advice(
            fileType: "Downloaded installer or archive",
            whatItIs: "An installer or archive you downloaded. Once the app is installed or the archive extracted, it's usually not needed.",
            safety: .safeToDelete,
            reasoning: "It can be downloaded again. Keep it only if it's a licensed installer you can't re-download.",
            preventGrowth: ["Delete installers right after installing.", "Safari › Settings › General: remove download list items automatically."],
            cleanupSteps: ["Eject the disk image if mounted, then move it to the Trash."],
            suggestMove: false)),
        Rule(matches: ext(["vmdk", "vdi", "qcow2", "vhd", "vhdx", "hdd", "utm", "pvm", "vmwarevm"]), advice: Advice(
            fileType: "Virtual machine disk",
            whatItIs: "The disk of a virtual machine (Parallels, UTM, VMware, VirtualBox).",
            safety: .reviewFirst,
            reasoning: "It contains a whole operating system and its files. Delete only VMs you no longer use.",
            preventGrowth: ["Compact or reclaim disk space from within the VM software.", "Delete old snapshots."],
            cleanupSteps: ["Remove the VM from its app's library, or move it to external storage."],
            suggestMove: true)),
        Rule(matches: { _, name, _ in name.hasSuffix(".xcarchive") }, advice: Advice(
            fileType: "Xcode archive",
            whatItIs: "An archived app build with debug symbols.",
            safety: .reviewFirst,
            reasoning: "Needed to symbolicate crash reports of that version.",
            preventGrowth: ["Keep archives only for shipped versions."],
            cleanupSteps: ["Delete from Xcode Organizer, or move to external storage."],
            suggestMove: true)),
        Rule(matches: inside("/.trash"), advice: Advice(
            fileType: "Trash",
            whatItIs: "Items you already moved to the Trash.",
            safety: .safeToDelete,
            reasoning: "They still use disk space until the Trash is emptied.",
            preventGrowth: ["Finder › Settings › Advanced: remove items from the Trash after 30 days."],
            cleanupSteps: ["Empty the Trash (Junk Cleaner › Trash)."],
            suggestMove: false)),
    ]

    // MARK: Generic fallback per kind

    private static func generic(_ item: AdvisorItem) -> Advice {
        let unused = item.lastAccess.map { Date().timeIntervalSince($0) > 365 * 86_400 } ?? false
        let stale = unused ? " It hasn't been opened in over a year." : ""
        switch item.kind {
        case .video, .image, .audio:
            return Advice(
                fileType: item.kind.title, whatItIs: "Personal media.\(stale)", safety: .reviewFirst,
                reasoning: "Media is usually irreplaceable. Make sure another copy exists before deleting.",
                preventGrowth: ["Store finished projects and raw footage on external storage or a NAS.", "Use iCloud Photos with 'Optimize Mac Storage'."],
                cleanupSteps: ["Review and delete what you don't need, or move it to external storage."],
                suggestMove: true)
        case .diskImage:
            return Advice(
                fileType: "Disk image", whatItIs: "A disk image or virtual disk.\(stale)", safety: .reviewFirst,
                reasoning: "Installer images can be re-downloaded; VM disks and backups usually cannot.",
                preventGrowth: ["Delete installer images after installing."],
                cleanupSteps: ["If it's an installer you've used, move it to the Trash."],
                suggestMove: true)
        case .archive:
            return Advice(
                fileType: "Archive", whatItIs: "A compressed archive.\(stale)", safety: .reviewFirst,
                reasoning: "If you've already extracted it, the archive is a duplicate of the extracted files.",
                preventGrowth: ["Delete archives after extracting them."],
                cleanupSteps: ["Check that the extracted files exist, then trash the archive, or move it to external storage."],
                suggestMove: true)
        case .application:
            return Advice(
                fileType: "App or installer", whatItIs: "An application bundle or installer package.", safety: .reviewFirst,
                reasoning: "Remove apps with the Uninstaller so their leftovers go too.",
                preventGrowth: ["Uninstall apps you no longer use."],
                cleanupSteps: ["Use MacCleaner's Uninstaller."],
                suggestMove: false)
        case .developer:
            return Advice(
                fileType: "Developer files", whatItIs: "Build output, dependencies or tool data.", safety: .reviewFirst,
                reasoning: "Build products and dependency folders can be regenerated; source code cannot.",
                preventGrowth: ["Clean build folders of inactive projects."],
                cleanupSteps: ["Run the project's clean command, or delete build/dependency folders only."],
                suggestMove: false)
        case .cache:
            return Advice(
                fileType: "Cache or log", whatItIs: "Temporary data an app can recreate.", safety: .safeToDelete,
                reasoning: "Caches and logs are regenerated. Quit the owning app first.",
                preventGrowth: ["Check the app's settings for a cache size limit."],
                cleanupSteps: ["Use Junk Cleaner to empty caches and logs safely."],
                suggestMove: false)
        case .document:
            return Advice(
                fileType: "Document", whatItIs: "A document or data file.\(stale)", safety: .reviewFirst,
                reasoning: "Documents are usually yours and not recoverable once deleted.",
                preventGrowth: ["Archive finished projects to external storage or iCloud Drive."],
                cleanupSteps: ["Move rarely used documents to iCloud Drive or a NAS."],
                suggestMove: true)
        case .other:
            let inLibrary = item.url.abbreviatedPath.lowercased().hasPrefix("~/library/")
            return Advice(
                fileType: item.isDirectory ? "Folder" : "File",
                whatItIs: inLibrary ? "App data in your Library folder." : "Unrecognized \(item.isDirectory ? "folder" : "file").\(stale)",
                safety: .reviewFirst,
                reasoning: inLibrary
                    ? "Files in ~/Library belong to apps; deleting them can lose settings or data."
                    : "MacCleaner can't tell what this is. Check it before deleting.",
                preventGrowth: ["Look inside to find which sub-folder grows."],
                cleanupSteps: [inLibrary ? "Remove app data with the Uninstaller when you remove the app." : "Reveal it in Finder and decide."],
                suggestMove: !inLibrary)
        }
    }

    // MARK: Whole-scan report

    static func summarize(_ input: ScanSummaryInput) -> ScanReport {
        var findings: [ScanReport.Finding] = []
        for item in (input.hogs + input.largestFiles).prefix(12) {
            let advice = advise(item)
            findings.append(.init(
                title: "\(advice.fileType): \(item.url.abbreviatedPath)",
                detail: "\(advice.reasoning) \(advice.cleanupSteps.first ?? "")",
                safety: advice.safety, url: item.url, size: item.size
            ))
        }
        if let waste = input.duplicateWaste, waste > 0 {
            findings.append(.init(
                title: "Duplicate files", detail: "Removing extra copies would free about \(Format.bytes(waste)). Review them in the Duplicates tab.",
                safety: .reviewFirst, url: nil, size: waste
            ))
        }

        let free = Double(input.volumeFree) / Double(max(input.volumeTotal, 1))
        var headline = "\(Format.bytes(input.rootSize)) in \((input.rootPath as NSString).abbreviatingWithTildeInPath); \(Format.bytes(input.volumeFree)) free on disk (\(Format.percent(free)))."
        if let growth = input.growthSincePrevious, growth.bytes != 0 {
            headline += " It \(growth.bytes > 0 ? "grew" : "shrank") by \(Format.bytes(abs(growth.bytes))) since \(Format.date(growth.since))."
        }

        let safe = findings.filter { $0.safety == .safeToDelete }.reduce(Int64(0)) { $0 + $1.size }
        var tips: [String] = []
        if safe > 0 { tips.append("About \(Format.bytes(safe)) of what's listed is safe to delete outright.") }
        if free < 0.15 { tips.append("Less than 15% of the disk is free; macOS needs room for updates, swap and snapshots.") }
        let top = input.kindTotals.sorted { $0.value > $1.value }.prefix(2).map(\.key)
        for kind in top {
            switch kind {
            case .video, .image: tips.append("Media is your largest category: move finished projects to external storage or use iCloud Photos with Optimize Mac Storage.")
            case .developer: tips.append("Developer files dominate: clean DerivedData, node_modules and simulator runtimes of inactive projects.")
            case .cache: tips.append("Caches are large: run Junk Cleaner regularly and cap cache sizes in browsers and chat apps.")
            case .diskImage: tips.append("Disk images and VMs are large: delete used installers and compact VM disks.")
            case .archive: tips.append("Many archives: delete them after extracting, or move them to external storage.")
            default: break
            }
        }
        tips.append("Rescan monthly and use the History tab to see which folders keep growing.")
        return ScanReport(headline: headline, findings: findings, tips: tips, engine: .rules)
    }
}
