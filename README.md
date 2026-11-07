# MacCleaner

A free, open-source CleanMyMac alternative for Apple Silicon Macs. It's a native SwiftUI app with no telemetry and no accounts. It makes no network requests unless you choose a cloud AI provider in Settings.

| Feature | What it does |
|---|---|
| **Junk Cleaner** | Finds user caches, logs, Xcode DerivedData and device support files, Homebrew, npm/pip/Yarn/CocoaPods/Gradle caches, browser caches, Mail downloads and the Trash. You preview every file before removing it. |
| **Uninstaller** | Removes an app together with its leftovers in `~/Library` (Application Support, Caches, Preferences, Containers, Group Containers, Saved State, LaunchAgents and more). Sort the app list by name, size, last used or date added to spot apps you never open. |
| **Disk Analyzer** | Drill down through folder sizes with a donut chart, plus: a **Breakdown** by file type, age and top folder; **Largest** files with filters (type, size, age, name, location) and a **Space Hogs** list of the folders that really hold the space; **Old Files**; **Duplicates** (content-compared with SHA-256, extra copies go to the Trash); **History** of disk usage over time with folder-by-folder comparison; **Explain with AI** / **Analyze Results** (what a file is, whether it's safe to delete, how to stop it growing, how to clean up) using Apple's on-device model, with built-in rules as fallback; and **Move to external drive, NAS or iCloud Drive** (copy → verify → original to Trash). |
| **Settings** | A sidebar page (also ⌘,) with General (menu-bar monitor, Full Disk Access, reset), Disk Analyzer (default folder, space-hog / old-file / duplicate thresholds, usage history), Uninstaller (default sort, Apple apps) and AI (provider, endpoint, model, key, privacy) settings. |
| **System Monitor** | A menu-bar popover and dashboard showing CPU (with history), memory, disk, battery and thermal state. Thermal state matters on the fanless M4 MacBook Air. |

## Screenshots

| Overview | Junk Cleaner |
|---|---|
| ![Overview](docs/screenshots/overview.png) | ![Junk Cleaner](docs/screenshots/cleaner.png) |
| **Uninstaller** | **Disk Analyzer** |
| ![Uninstaller](docs/screenshots/uninstaller.png) | ![Disk Analyzer](docs/screenshots/analyzer.png) |

## Safety
- **Files go to the Trash by default.** The only permanent deletion is the "Empty Trash" category, and it is off by default.
- Every deletion passes `SafetyGuard`. Only paths inside your home folder or `/Applications` are allowed. `/System`, `/usr`, `/Library`, `/private`, iCloud Drive, cloud storage, Keychains, Mail, Messages and the Photos library are always blocked. Paths that go through a symlink are rejected.
- Moving files to another disk copies them, verifies the copy (size, file count and SHA-256 for files up to 2 GB), and only then moves the original to the Trash. Sources pass the same `SafetyGuard` checks as deletion.
- AI analysis uses Apple's on-device model by default (macOS 26+ with Apple Intelligence), so nothing leaves the Mac. In **Settings › AI** you can instead choose **Azure OpenAI, OpenAI, Anthropic Claude, Google Gemini, Ollama** (local or on your network) or any **OpenAI-compatible** server (LM Studio, OpenRouter, Groq…). API keys are stored in the Keychain. Only paths, names, sizes and dates are sent (optionally just the last two folders of each path), never file contents, and only when you click Explain or Analyze. Whatever the model says, safety ratings can never be more permissive than the built-in rules and `SafetyGuard`.
- Apple apps (`com.apple.*`) can't be uninstalled. Leftovers that match only by folder name start unchecked.

## Install
Requirements: an Apple Silicon Mac, macOS 14+ and Xcode 16+ (Xcode 26+ to include on-device AI; older Xcode builds use the built-in rules).

```bash
git clone https://github.com/microsoft-powerbi-dev/mac-cleaner.git && cd mac-cleaner
./scripts/install.sh
```
The script installs XcodeGen with Homebrew if needed, builds a Release copy, installs it to `/Applications/MacCleaner.app` and opens it. Pass `--no-open` to skip launching it. Run the script again to update.

To remove the app, its preferences and its Full Disk Access entry:
```bash
./scripts/uninstall.sh
```

## Build for development
```bash
brew install xcodegen
xcodegen                 # run from the repo root; generates MacCleaner.xcodeproj from project.yml
open MacCleaner.xcodeproj
```
Then press **⌘R** to run or **⌘U** to run the tests.


## Full Disk Access
macOS hides caches, Mail downloads and the Trash from apps until you allow it:
**System Settings → Privacy & Security → Full Disk Access →** turn on **MacCleaner**, then reopen the app.
The app shows a banner with a shortcut while access is off.

Note: builds are ad-hoc signed ("Sign to Run Locally"). macOS may forget the permission after you rebuild. If that happens, remove MacCleaner from the list and add it again.

## Project layout
```
MacCleaner/App          App entry point, main window, menu-bar extra
MacCleaner/Core         SafetyGuard, FileSizer, Trasher, Mover, FileHasher, StorageDestinations, Permissions
MacCleaner/Cleaner      Cleanup catalog, scanner, UI
MacCleaner/Uninstaller  App inventory, leftover finder, UI
MacCleaner/Analyzer     Disk scanner, file kinds, filters/space hogs, duplicates, usage history, advisor (rules + on-device AI), UI
MacCleaner/Monitor      Mach/IOKit stats, menu-bar and dashboard UI
MacCleanerTests         Safety, leftover-matching, catalog, analyzer, duplicate and mover tests
scripts                 install.sh / uninstall.sh
docs/screenshots        README images
```
To add a cleanup category, add an entry to `CleanupCatalog.all`. The catalog tests check that every new path passes the safety policy.

## Credits
The cleanup-target lists and the preview-before-delete approach come from these MIT-licensed projects:
PureMac, [Mole](https://github.com/tw93/Mole) and Dusty. No code was copied.

## License
MIT
