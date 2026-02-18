"""
Wavefront YouTube Import Backend
FastAPI server for extracting audio from YouTube videos using yt-dlp
"""

import os
import asyncio
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from pydantic import BaseModel, HttpUrl
from dotenv import load_dotenv

from .youtube_service import YouTubeService, VideoInfo, DownloadStatus

load_dotenv()

# Configuration
DOWNLOAD_DIR = Path(os.getenv("DOWNLOAD_DIR", "/tmp/wavefront_downloads"))
MAX_CONCURRENT_DOWNLOADS = int(os.getenv("MAX_CONCURRENT_DOWNLOADS", "3"))
CLEANUP_AFTER_HOURS = int(os.getenv("CLEANUP_AFTER_HOURS", "24"))

# Ensure download directory exists
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

# Initialize service
youtube_service = YouTubeService(
    download_dir=DOWNLOAD_DIR,
    max_concurrent=MAX_CONCURRENT_DOWNLOADS
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events"""
    # Startup: Start cleanup task
    cleanup_task = asyncio.create_task(
        youtube_service.periodic_cleanup(hours=CLEANUP_AFTER_HOURS)
    )
    yield
    # Shutdown: Cancel cleanup task
    cleanup_task.cancel()
    try:
        await cleanup_task
    except asyncio.CancelledError:
        pass


app = FastAPI(
    title="Wavefront YouTube API",
    description="Backend service for extracting audio from YouTube videos",
    version="1.0.0",
    lifespan=lifespan
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Request/Response models
class VideoInfoRequest(BaseModel):
    url: str


class DownloadRequest(BaseModel):
    url: str
    quality: str = "high"  # low, medium, high


class DownloadResponse(BaseModel):
    download_id: str
    status: str
    message: str


class StatusResponse(BaseModel):
    download_id: str
    status: str
    progress: float
    title: str | None = None
    error: str | None = None


# API Endpoints
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "wavefront-youtube-api"}


@app.post("/api/v1/video/info")
async def get_video_info(request: VideoInfoRequest) -> VideoInfo:
    """
    Get video information without downloading
    
    Returns title, author, duration, thumbnail, and available formats
    """
    try:
        info = await youtube_service.get_video_info(request.url)
        return info
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get video info: {str(e)}")


@app.post("/api/v1/download/start")
async def start_download(
    request: DownloadRequest,
    background_tasks: BackgroundTasks
) -> DownloadResponse:
    """
    Start an audio download in the background
    
    Returns a download_id to track progress
    """
    try:
        download_id = await youtube_service.start_download(
            url=request.url,
            quality=request.quality
        )
        return DownloadResponse(
            download_id=download_id,
            status="started",
            message="Download started. Use /api/v1/download/status to check progress."
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to start download: {str(e)}")


@app.get("/api/v1/download/status/{download_id}")
async def get_download_status(download_id: str) -> StatusResponse:
    """
    Check the status of a download
    """
    status = youtube_service.get_download_status(download_id)
    if status is None:
        raise HTTPException(status_code=404, detail="Download not found")
    
    return StatusResponse(
        download_id=download_id,
        status=status.status,
        progress=status.progress,
        title=status.title,
        error=status.error
    )


@app.get("/api/v1/download/file/{download_id}")
async def get_download_file(download_id: str):
    """
    Download the audio file once extraction is complete
    """
    status = youtube_service.get_download_status(download_id)
    if status is None:
        raise HTTPException(status_code=404, detail="Download not found")
    
    if status.status != "completed":
        raise HTTPException(
            status_code=400, 
            detail=f"Download not ready. Current status: {status.status}"
        )
    
    if status.file_path is None or not Path(status.file_path).exists():
        raise HTTPException(status_code=404, detail="File not found")
    
    file_path = Path(status.file_path)
    
    return FileResponse(
        path=file_path,
        filename=file_path.name,
        media_type="audio/m4a"
    )


@app.get("/api/v1/download/stream/{download_id}")
async def stream_download_file(download_id: str):
    """
    Stream the audio file (for direct playback)
    """
    status = youtube_service.get_download_status(download_id)
    if status is None:
        raise HTTPException(status_code=404, detail="Download not found")
    
    if status.status != "completed":
        raise HTTPException(
            status_code=400,
            detail=f"Download not ready. Current status: {status.status}"
        )
    
    if status.file_path is None or not Path(status.file_path).exists():
        raise HTTPException(status_code=404, detail="File not found")
    
    file_path = Path(status.file_path)
    file_size = file_path.stat().st_size
    
    async def iterfile():
        async with aiofiles.open(file_path, "rb") as f:
            while chunk := await f.read(65536):  # 64KB chunks
                yield chunk
    
    return StreamingResponse(
        iterfile(),
        media_type="audio/m4a",
        headers={
            "Content-Length": str(file_size),
            "Content-Disposition": f'attachment; filename="{file_path.name}"'
        }
    )


@app.delete("/api/v1/download/{download_id}")
async def delete_download(download_id: str):
    """
    Delete a download and its associated file
    """
    success = await youtube_service.delete_download(download_id)
    if not success:
        raise HTTPException(status_code=404, detail="Download not found")
    
    return {"status": "deleted", "download_id": download_id}


@app.get("/api/v1/downloads")
async def list_downloads():
    """
    List all active and completed downloads
    """
    downloads = youtube_service.list_downloads()
    return {"downloads": downloads}


# Import aiofiles for streaming
import aiofiles


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
