# Wavefront

A modern iOS music streaming app with support for local files, Spotify imports, and YouTube downloads.

## Features

- **Local Music Library** - Import and play audio files from your device
- **Spotify Import** - Import tracks, playlists, and albums from Spotify URLs
- **YouTube Downloads** - Download audio from YouTube videos
- **Background Playback** - Continue listening with the app in background
- **Shuffle Modes** - Random and smart shuffle based on track similarity
- **Last.fm Integration** - Scrobbling and metadata enrichment
- **Album Artwork** - Automatic artwork fetching and display
- **SMB Network Shares** - Stream music from network storage

## Requirements

- iOS 16.0+
- Xcode 15+

## Installation

```bash
git clone https://github.com/yeabsiraretta/Wavefront.git
cd Wavefront
open WavefrontApp.xcodeproj
```

Build and run on your device or simulator.

## Usage

### Importing Music

**From Spotify:**
1. Tap the menu icon → "Import from Spotify"
2. Paste a Spotify track, playlist, or album URL
3. Tap Import - downloads happen in background

**From YouTube:**
1. Tap the menu icon → "Import from YouTube"
2. Paste a YouTube video URL
3. Select quality and import

**From Files:**
1. Tap the menu icon → "Import Files"
2. Select audio files from your device

### Playback

- Tap any track to play
- Use the Now Playing bar for controls
- Tap the bar to expand full player
- Swipe for next/previous track

### Shuffle Modes

- **Off** - Play in order
- **Random** - Standard shuffle
- **Smart** - Groups similar tracks together

## Project Structure

```
Wavefront/
├── App/                      # App entry point
├── Sources/Wavefront/
│   ├── Core/Models/          # AudioTrack, etc.
│   ├── Features/
│   │   ├── Library/          # Main music library UI
│   │   └── Settings/         # App settings
│   └── Services/
│       ├── Audio/            # Playback, shuffle
│       ├── Spotify/          # Spotify scraping
│       ├── YouTube/          # YouTube extraction
│       └── LastFM/           # Last.fm API
├── Tests/
└── .github/workflows/        # CI/CD
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```bash
feat: add new feature
fix: resolve bug
docs: update documentation
chore: maintenance task
```

## License

MIT
