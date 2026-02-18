# Contributing to Wavefront

## Development Setup

### Prerequisites

- **Xcode 15+** with iOS 16+ SDK
- **Node.js 18+** (for Git hooks)
- **SwiftLint** (optional but recommended): `brew install swiftlint`
- **SwiftFormat** (optional but recommended): `brew install swiftformat`

### Initial Setup

```bash
# Clone the repository
git clone <repository-url>
cd Wavefront

# Install Node dependencies (sets up Husky hooks)
npm install

# Build the project
swift build

# Run tests
swift test
```

## Git Hooks

This project uses [Husky](https://typicode.github.io/husky/) for Git hooks.

### Pre-commit Hook

Runs automatically before each commit:

1. **SwiftLint** - Checks code style (if installed)
2. **SwiftFormat** - Verifies code formatting (if installed)
3. **Build Check** - Ensures the project compiles

To skip (not recommended):
```bash
git commit --no-verify -m "Your message"
```

### Pre-push Hook

Runs automatically before each push:

1. **Full Build** - Compiles the entire project
2. **Unit Tests** - Runs all Swift tests
3. **iOS Tests** - Runs simulator tests (if Xcode available)

To skip (not recommended):
```bash
git push --no-verify
```

## Testing

### Running Tests

```bash
# Run all tests via Swift
swift test

# Run tests via Xcode (includes iOS-specific tests)
xcodebuild test \
  -scheme Wavefront \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test class
swift test --filter UserLibraryTests

# Run with verbose output
swift test --verbose
```

### Test Structure

```
Tests/WavefrontTests/
├── Models/
│   ├── AudioTrackTests.swift
│   ├── AudioFormatTests.swift
│   ├── SMBConfigurationTests.swift
│   └── UserLibraryTests.swift
├── Services/
│   ├── AudioPlayerTests.swift
│   ├── AudioSourceManagerTests.swift
│   ├── MetadataServiceTests.swift
│   └── YouTubeDownloaderTests.swift
├── Sources/
│   ├── LocalAudioSourceTests.swift
│   └── SMBAudioSourceTests.swift
├── Protocols/
│   └── AudioSourceErrorTests.swift
├── Integration/
│   └── AudioSourceIntegrationTests.swift
└── Mocks/
    └── MockAudioSource.swift
```

### Test Coverage Areas

| Area | Description |
|------|-------------|
| Models | AudioTrack, AudioFormat, SMBConfiguration, UserLibrary |
| Services | AudioPlayer, AudioSourceManager, MetadataService, YouTubeDownloader |
| Sources | LocalAudioSource, SMBAudioSource |
| Protocols | AudioSourceError |
| Integration | Multi-source scenarios |

### SMB Integration Tests

SMB tests are gated by environment variables:

```bash
export SMB_TEST_HOST="192.168.1.100"
export SMB_TEST_SHARE="Music"
export SMB_TEST_USER="username"
export SMB_TEST_PASS="password"
swift test
```

## Code Style

### SwiftLint

Configuration: `.swiftlint.yml`

```bash
# Check for issues
swiftlint lint

# Auto-fix issues
swiftlint lint --fix
```

### SwiftFormat

Configuration: `.swiftformat`

```bash
# Check formatting
swiftformat Sources Tests --lint

# Auto-format
swiftformat Sources Tests
```

## npm Scripts

```bash
npm run lint        # Run SwiftLint
npm run lint:fix    # Auto-fix SwiftLint issues
npm run format      # Format code with SwiftFormat
npm run format:check # Check formatting
npm run test        # Run Swift tests
npm run test:ios    # Run iOS simulator tests
npm run build       # Build project
npm run clean       # Clean build artifacts
```

## Project Structure

```
Wavefront/
├── App/                    # Xcode app entry point
├── Sources/Wavefront/      # Main library source
│   ├── Models/
│   ├── Views/
│   ├── ViewModels/
│   ├── Services/
│   ├── Sources/            # AudioSource implementations
│   └── Protocols/
├── Tests/WavefrontTests/   # Test files
├── Resources/              # Assets, Info.plist
├── .husky/                 # Git hooks
├── .swiftlint.yml          # SwiftLint config
├── .swiftformat            # SwiftFormat config
└── Package.swift           # Swift Package definition
```

## Making Changes

1. Create a feature branch: `git checkout -b feature/my-feature`
2. Make your changes
3. Run tests: `swift test`
4. Commit (hooks will run): `git commit -m "Add my feature"`
5. Push (hooks will run): `git push origin feature/my-feature`
6. Create a Pull Request

## Troubleshooting

### Hooks not running

```bash
# Reinstall Husky
npm run prepare
```

### SwiftLint/SwiftFormat not found

```bash
brew install swiftlint swiftformat
```

### Build failures

```bash
# Clean and rebuild
swift package clean
swift build
```
