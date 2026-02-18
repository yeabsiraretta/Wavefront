FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for yt-dlp and ffmpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/

# Create download directory
RUN mkdir -p /tmp/wavefront_downloads

# Environment variables
ENV PYTHONUNBUFFERED=1
ENV DOWNLOAD_DIR=/tmp/wavefront_downloads
ENV MAX_CONCURRENT_DOWNLOADS=3
ENV CLEANUP_AFTER_HOURS=24

# Expose port
EXPOSE 8000

# Run the application
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
