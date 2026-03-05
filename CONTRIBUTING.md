# Contributing to Wavefront

## Development Setup

### Prerequisites

- **Xcode 15+** with iOS 16+ SDK
- **SwiftLint** (optional): `brew install swiftlint`
- **SwiftFormat** (optional): `brew install swiftformat`

### Initial Setup

```bash
# Clone the repository
git clone https://github.com/yeabsiraretta/Wavefront.git
cd Wavefront

# Build the project
swift build

# Run tests
swift test
```

## Commit Message Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/). Commit messages are validated via GitHub Actions.

### Format

```
type: description
```

or with scope:

```
type(scope): description
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Code style (formatting, etc.) |
| `refactor` | Code refactoring |
| `test` | Adding or updating tests |
| `chore` | Maintenance tasks |
| `perf` | Performance improvements |
| `ci` | CI/CD changes |
| `build` | Build system changes |
| `revert` | Revert a previous commit |

### Rules

- Single line only
- Max 72 characters
- No trailing period
- Must start with a valid type

### Examples

```bash
git commit -m "feat: add Spotify playlist import"
git commit -m "fix(player): resolve background playback issue"
git commit -m "docs: update README with setup instructions"
git commit -m "chore: update dependencies"
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

## Project Structure

```
Wavefront/
├── App/                      # Xcode app entry point
├── Sources/Wavefront/        # Main library source
│   ├── Core/Models/          # Data models
│   ├── Features/             # Feature modules (Library, Settings)
│   ├── Services/             # Business logic services
│   │   ├── Audio/            # AudioPlayer, ShuffleService
│   │   ├── Spotify/          # SpotifyExtractor
│   │   ├── YouTube/          # YouTubeKitExtractor
│   │   └── LastFM/           # LastFMService
│   └── Protocols/            # Protocol definitions
├── Tests/WavefrontTests/     # Test files
├── .github/workflows/        # GitHub Actions (CI, commit linting)
└── Package.swift             # Swift Package definition
```

## Making Changes

1. Create a feature branch: `git checkout -b feature/my-feature`
2. Make your changes
3. Run tests: `swift test`
4. Commit with conventional format: `git commit -m "feat: add my feature"`
5. Push: `git push origin feature/my-feature`
6. Create a Pull Request

## Troubleshooting

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

### Commit rejected by CI

Ensure your commit message follows the conventional format:

```bash
# Wrong
git commit -m "fixed bug"

# Correct
git commit -m "fix: resolve playback issue"
```
