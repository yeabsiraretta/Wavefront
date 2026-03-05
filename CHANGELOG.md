# Changelog

All notable changes to Wavefront will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] - 2026-03-05

### Added
- Auto-release workflow on PR merge
- PR auto-labeling based on branch/title
- Dependabot configuration for dependency updates
- CodeQL code scanning (optional/non-blocking)

### Changed
- Build & Test now non-blocking for faster PR merges
- Switched from swift build to xcodebuild for CI compatibility
- Simplified security workflows to run on Ubuntu

### Fixed
- AMSMB2 build failure in CI (libsmb2 compilation)
- iOS Simulator destination for GitHub Actions
- Dependabot branch validation

## [1.1.0] - 2026-03-04

### Added
- iOS app bundle in releases (unsigned IPA)
- Automated release workflow with changelog generation
- PR check workflow with branch naming validation
- Branch protection requiring PRs to main

### Changed
- Updated CI/CD pipeline structure

## [1.0.0] - 2026-03-04

### Added
- **Spotify Import** - Extract and download tracks, playlists, albums from Spotify URLs
- **YouTube Download** - Download audio from YouTube videos
- **Background Downloads** - Downloads continue when dismissing import sheet
- **Swipe-to-Dismiss** - Import sheets can be dismissed during downloads
- **Track Notes** - Add notes per song
- **Delete Function** - Remove tracks from library
- **Shuffle Modes** - Random and smart shuffle
- **Last.fm Integration** - Scrobbling and metadata enrichment
- **Album Artwork** - Automatic artwork fetching and display
- **SMB Network Shares** - Stream music from network storage

### CI/CD
- Commit message linting (conventional commits)
- Security scanning (CodeQL, dependency audit, secrets scan)
- Swift build and test workflow

### Documentation
- README with installation and usage guide
- CONTRIBUTING guide with commit conventions

### Dependencies
- AMSMB2 3.1.0
- YouTubeKit 0.4.0

[Unreleased]: https://github.com/yeabsiraretta/Wavefront/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/yeabsiraretta/Wavefront/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/yeabsiraretta/Wavefront/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/yeabsiraretta/Wavefront/releases/tag/v1.0.0
