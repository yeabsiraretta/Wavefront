# Wavefront YouTube Backend

FastAPI backend service for extracting audio from YouTube videos using yt-dlp.

## Features

- **Video Info**: Get metadata without downloading
- **Audio Extraction**: Download and convert to M4A format
- **Quality Options**: Low (128kbps), Medium (192kbps), High (320kbps)
- **Progress Tracking**: Real-time download progress
- **Auto Cleanup**: Old downloads cleaned up automatically
- **Docker Support**: Easy deployment with Docker Compose

## Quick Start

### Local Development

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Install ffmpeg (required for audio conversion)
# macOS: brew install ffmpeg
# Ubuntu: sudo apt install ffmpeg

# Run the server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Docker

```bash
cd backend

# Build and run
docker-compose up -d

# View logs
docker-compose logs -f

# Stop
docker-compose down
```

## API Endpoints

### Health Check
```
GET /health
```

### Get Video Info
```
POST /api/v1/video/info
Content-Type: application/json

{
  "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
}
```

Response:
```json
{
  "video_id": "dQw4w9WgXcQ",
  "title": "Rick Astley - Never Gonna Give You Up",
  "author": "Rick Astley",
  "duration": 212,
  "thumbnail_url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg",
  "formats": [...]
}
```

### Start Download
```
POST /api/v1/download/start
Content-Type: application/json

{
  "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  "quality": "high"
}
```

Response:
```json
{
  "download_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "started",
  "message": "Download started. Use /api/v1/download/status to check progress."
}
```

### Check Download Status
```
GET /api/v1/download/status/{download_id}
```

Response:
```json
{
  "download_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "progress": 1.0,
  "title": "Rick Astley - Never Gonna Give You Up"
}
```

### Download File
```
GET /api/v1/download/file/{download_id}
```

Returns the audio file as `audio/m4a`.

### Stream File
```
GET /api/v1/download/stream/{download_id}
```

Streams the audio file (for direct playback).

### Delete Download
```
DELETE /api/v1/download/{download_id}
```

### List All Downloads
```
GET /api/v1/downloads
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DOWNLOAD_DIR` | `/tmp/wavefront_downloads` | Directory for downloaded files |
| `MAX_CONCURRENT_DOWNLOADS` | `3` | Maximum parallel downloads |
| `CLEANUP_AFTER_HOURS` | `24` | Hours after which completed downloads are deleted |

## iOS App Integration

Configure the backend URL in your iOS app:

```swift
// In your ViewModel or App setup
viewModel.backendURL = URL(string: "http://your-server:8000")
```

The app will automatically use the backend for YouTube imports when configured.

## Development

### API Documentation

Once running, visit:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### Project Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI application
│   └── youtube_service.py   # yt-dlp integration
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
└── README.md
```

## Deployment

### Docker (Recommended)

```bash
# Build image
docker build -t wavefront-youtube-api .

# Run container
docker run -d \
  -p 8000:8000 \
  -v wavefront-downloads:/tmp/wavefront_downloads \
  --name wavefront-api \
  wavefront-youtube-api
```

### Systemd Service

Create `/etc/systemd/system/wavefront-api.service`:

```ini
[Unit]
Description=Wavefront YouTube API
After=network.target

[Service]
User=wavefront
WorkingDirectory=/opt/wavefront/backend
ExecStart=/opt/wavefront/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

Then:
```bash
sudo systemctl enable wavefront-api
sudo systemctl start wavefront-api
```

## Security Considerations

- Configure CORS properly for production
- Use HTTPS in production (reverse proxy recommended)
- Consider rate limiting for public deployments
- Monitor disk usage (downloads can be large)

## License

Part of the Wavefront project.
