# SSD Remover

[한국어](README.ko.md)

A macOS menu bar utility that helps you safely eject external SSDs/disks.

It automatically detects processes blocking a disk, lets you selectively terminate them, and safely ejects the disk.

## Screenshots

| Volume List | Process List |
|:-:|:-:|
| ![Volume List](screenshots/volume-list.png) | ![Process List](screenshots/process-list.png) |

## Features

- **Menu Bar Resident** - Quick access from the menu bar icon
- **Auto-detect External Disks** - Real-time detection of connected external disks
- **Blocking Process Scan** - Identifies processes holding the disk using `lsof`
- **Process Classification** - Automatically categorizes into Spotlight, system, and user processes
- **Selective Process Termination** - Choose which processes to terminate via checkboxes
- **Graceful Shutdown** - Sends SIGTERM first, falls back to SIGKILL if needed
- **Privilege Escalation** - Requests admin privileges for root process termination
- **Spotlight Warning** - Displays a warning banner when mds/mds_stores is detected
- **Launch at Login** - Auto-launch on system startup
- **CLI Mode** - Available for terminal automation

## Installation

1. Download `SSD_Remover.zip` from the [latest release](https://github.com/eastLight210/SSD_Remover/releases/latest)
2. Unzip the file
3. Move `SSD_Remover.app` to the Applications folder
4. On first launch, if you see an "unidentified developer" warning, right-click > Open to run

## Requirements

- macOS 14.0 (Sonoma) or later

## Build from Source

Requires Xcode 26.0+ and Swift 6.2.

Generate the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# Install XcodeGen (if not installed)
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
open SSD_Remover.xcodeproj
```

## Project Structure

```
SSD_Remover/
├── App/              # Entry point, bootstrap, launch mode detection
├── Models/           # ExternalVolume, BlockingProcess, ProcessGroup
├── Services/         # Shell execution, volume monitoring, process scan/terminate, disk eject
│   └── Protocols/    # Service interfaces (DI for testing)
├── ViewModels/       # AppViewModel, EjectViewModel (state machine)
├── Views/            # SwiftUI views (volume list, process list, progress)
├── Utilities/        # lsof/diskutil parsers, process classifier
├── CLI/              # CLI command parser and runner
└── Resources/        # Info.plist, Assets
```

## Architecture

Uses the **MVVM + Service Layer** pattern.

- **@Observable ViewModel** - State management and UI binding
- **Actor-based Services** - Concurrency safety with Swift Concurrency
- **Protocol-based DI** - Dependency injection for testability

## CLI Usage

```bash
# List external volumes
SSD_Remover --list-volumes

# Scan blocking processes for a volume
SSD_Remover --scan <volume-path>

# Terminate processes and eject
SSD_Remover --terminate-and-eject <volume-path>

# Help
SSD_Remover --help
```

## Testing

```bash
xcodebuild test -scheme SSD_Remover -destination 'platform=macOS'
```

## License

MIT License
