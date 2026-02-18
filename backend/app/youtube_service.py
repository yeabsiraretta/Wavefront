"""
YouTube Service - Audio extraction using yt-dlp
"""

import os
import re
import uuid
import asyncio
import logging
from pathlib import Path
from datetime import datetime, timedelta
from dataclasses import dataclass, field
from typing import Optional
from concurrent.futures import ThreadPoolExecutor

import yt_dlp

logger = logging.getLogger(__name__)


@dataclass
class VideoInfo:
    """Video information from YouTube"""
    video_id: str
    title: str
    author: str
    duration: int  # seconds
    thumbnail_url: Optional[str] = None
    description: Optional[str] = None
    upload_date: Optional[str] = None
    view_count: Optional[int] = None
    formats: list = field(default_factory=list)


@dataclass
class DownloadStatus:
    """Download job status"""
    download_id: str
    status: str  # pending, downloading, processing, completed, failed
    progress: float  # 0.0 to 1.0
    title: Optional[str] = None
    file_path: Optional[str] = None
    error: Optional[str] = None
    created_at: datetime = field(default_factory=datetime.now)
    completed_at: Optional[datetime] = None


class YouTubeService:
    """Service for extracting audio from YouTube videos"""
    
    # Quality presets (audio bitrate in kbps)
    QUALITY_PRESETS = {
        "low": 128,
        "medium": 192,
        "high": 320
    }
    
    def __init__(
        self,
        download_dir: Path,
        max_concurrent: int = 3
    ):
        self.download_dir = download_dir
        self.download_dir.mkdir(parents=True, exist_ok=True)
        
        self.max_concurrent = max_concurrent
        self.semaphore = asyncio.Semaphore(max_concurrent)
        self.executor = ThreadPoolExecutor(max_workers=max_concurrent)
        
        # Track active downloads
        self.downloads: dict[str, DownloadStatus] = {}
    
    def _extract_video_id(self, url: str) -> Optional[str]:
        """Extract video ID from various YouTube URL formats"""
        patterns = [
            r'(?:youtube\.com/watch\?v=)([a-zA-Z0-9_-]{11})',
            r'(?:youtu\.be/)([a-zA-Z0-9_-]{11})',
            r'(?:youtube\.com/embed/)([a-zA-Z0-9_-]{11})',
            r'(?:m\.youtube\.com/watch\?v=)([a-zA-Z0-9_-]{11})',
            r'(?:music\.youtube\.com/watch\?v=)([a-zA-Z0-9_-]{11})',
        ]
        
        for pattern in patterns:
            match = re.search(pattern, url)
            if match:
                return match.group(1)
        
        # Check if it's already a video ID
        if len(url) == 11 and re.match(r'^[a-zA-Z0-9_-]+$', url):
            return url
        
        return None
    
    async def get_video_info(self, url: str) -> VideoInfo:
        """Get video information without downloading"""
        video_id = self._extract_video_id(url)
        if not video_id:
            raise ValueError("Invalid YouTube URL")
        
        ydl_opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': False,
        }
        
        loop = asyncio.get_event_loop()
        
        def extract_info():
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                return ydl.extract_info(
                    f"https://www.youtube.com/watch?v={video_id}",
                    download=False
                )
        
        info = await loop.run_in_executor(self.executor, extract_info)
        
        # Extract audio formats
        audio_formats = []
        for f in info.get('formats', []):
            if f.get('acodec') != 'none' and f.get('vcodec') == 'none':
                audio_formats.append({
                    'format_id': f.get('format_id'),
                    'ext': f.get('ext'),
                    'abr': f.get('abr'),
                    'acodec': f.get('acodec'),
                    'filesize': f.get('filesize')
                })
        
        return VideoInfo(
            video_id=video_id,
            title=info.get('title', 'Unknown'),
            author=info.get('uploader', info.get('channel', 'Unknown')),
            duration=info.get('duration', 0),
            thumbnail_url=info.get('thumbnail'),
            description=info.get('description'),
            upload_date=info.get('upload_date'),
            view_count=info.get('view_count'),
            formats=audio_formats
        )
    
    async def start_download(self, url: str, quality: str = "high") -> str:
        """Start a download job and return download_id"""
        video_id = self._extract_video_id(url)
        if not video_id:
            raise ValueError("Invalid YouTube URL")
        
        if quality not in self.QUALITY_PRESETS:
            quality = "high"
        
        download_id = str(uuid.uuid4())
        
        # Create status entry
        self.downloads[download_id] = DownloadStatus(
            download_id=download_id,
            status="pending",
            progress=0.0
        )
        
        # Start download in background
        asyncio.create_task(self._download_audio(download_id, video_id, quality))
        
        return download_id
    
    async def _download_audio(
        self,
        download_id: str,
        video_id: str,
        quality: str
    ):
        """Download and extract audio from video"""
        async with self.semaphore:
            status = self.downloads.get(download_id)
            if not status:
                return
            
            status.status = "downloading"
            
            output_template = str(
                self.download_dir / f"{download_id}_%(title)s.%(ext)s"
            )
            
            bitrate = self.QUALITY_PRESETS.get(quality, 320)
            
            ydl_opts = {
                'format': 'bestaudio/best',
                'outtmpl': output_template,
                'postprocessors': [{
                    'key': 'FFmpegExtractAudio',
                    'preferredcodec': 'm4a',
                    'preferredquality': str(bitrate),
                }],
                'progress_hooks': [
                    lambda d: self._progress_hook(download_id, d)
                ],
                'quiet': True,
                'no_warnings': True,
            }
            
            loop = asyncio.get_event_loop()
            
            def do_download():
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    return ydl.extract_info(
                        f"https://www.youtube.com/watch?v={video_id}",
                        download=True
                    )
            
            try:
                info = await loop.run_in_executor(self.executor, do_download)
                
                # Find the output file
                status.title = info.get('title', 'Unknown')
                
                # Look for the m4a file
                for file in self.download_dir.iterdir():
                    if file.name.startswith(download_id) and file.suffix == '.m4a':
                        status.file_path = str(file)
                        break
                
                if status.file_path:
                    status.status = "completed"
                    status.progress = 1.0
                    status.completed_at = datetime.now()
                    logger.info(f"Download completed: {download_id} - {status.title}")
                else:
                    status.status = "failed"
                    status.error = "Output file not found"
                    logger.error(f"Download failed: {download_id} - File not found")
                    
            except Exception as e:
                status.status = "failed"
                status.error = str(e)
                logger.error(f"Download failed: {download_id} - {e}")
    
    def _progress_hook(self, download_id: str, d: dict):
        """Progress callback for yt-dlp"""
        status = self.downloads.get(download_id)
        if not status:
            return
        
        if d['status'] == 'downloading':
            status.status = "downloading"
            total = d.get('total_bytes') or d.get('total_bytes_estimate', 0)
            downloaded = d.get('downloaded_bytes', 0)
            if total > 0:
                status.progress = downloaded / total * 0.9  # Reserve 10% for processing
        
        elif d['status'] == 'finished':
            status.status = "processing"
            status.progress = 0.95
    
    def get_download_status(self, download_id: str) -> Optional[DownloadStatus]:
        """Get status of a download"""
        return self.downloads.get(download_id)
    
    def list_downloads(self) -> list[dict]:
        """List all downloads"""
        return [
            {
                "download_id": s.download_id,
                "status": s.status,
                "progress": s.progress,
                "title": s.title,
                "created_at": s.created_at.isoformat(),
                "completed_at": s.completed_at.isoformat() if s.completed_at else None
            }
            for s in self.downloads.values()
        ]
    
    async def delete_download(self, download_id: str) -> bool:
        """Delete a download and its file"""
        status = self.downloads.get(download_id)
        if not status:
            return False
        
        # Delete file if exists
        if status.file_path:
            try:
                Path(status.file_path).unlink(missing_ok=True)
            except Exception as e:
                logger.error(f"Failed to delete file: {e}")
        
        # Remove from tracking
        del self.downloads[download_id]
        return True
    
    async def periodic_cleanup(self, hours: int = 24):
        """Periodically clean up old downloads"""
        while True:
            await asyncio.sleep(3600)  # Check every hour
            
            cutoff = datetime.now() - timedelta(hours=hours)
            to_delete = []
            
            for download_id, status in self.downloads.items():
                if status.completed_at and status.completed_at < cutoff:
                    to_delete.append(download_id)
            
            for download_id in to_delete:
                await self.delete_download(download_id)
                logger.info(f"Cleaned up old download: {download_id}")
