# Unraid Smart Mover

This application integrates with Jellyfin and Unraid's mover to intelligently manage media files between cache and array storage. It moves files from cache to array only after they've been played in Jellyfin and when the cache usage exceeds 90%.

## Features

- Monitors cache disk usage
- Integrates with Jellyfin API to track played media
- Moves files only when cache reaches 90% capacity
- Includes logging and retry mechanisms
- Runs as a scheduled service

## Setup

1. Create a `.env` file in the same directory with the following variables:
```
JELLYFIN_URL=http://your-jellyfin-server:8096
JELLYFIN_API_KEY=your-jellyfin-api-key
CACHE_PATH=/mnt/cache
ARRAY_PATH=/mnt/disk1
```

## Array Path Selection

The `ARRAY_PATH` determines where files are moved when clearing the cache. Choose based on your needs:

### Option 1: Direct Disk Path (Recommended)
```
ARRAY_PATH=/mnt/disk1
```
- Writes files directly to a specific disk
- Guarantees files go to that exact disk
- Use `/mnt/disk2`, `/mnt/disk3`, etc. for other disks
- **Best for:** Users who want predictable, controlled file placement

### Option 2: User Share with Cache Bypass (Unraid 6.9+)
```
ARRAY_PATH=/mnt/user0
```
- Files go to array via user share, bypassing cache
- Unraid distributes files across disks based on your allocation method
- Respects split levels and allocation settings
- **Best for:** Users who want Unraid to manage disk distribution automatically

### Option 3: Standard User Share - NOT RECOMMENDED
```
ARRAY_PATH=/mnt/user    # WARNING!
```
- **Do not use** - this path includes the cache drive
- Files may be written back to cache, defeating the purpose of moving them
- Only use if you fully understand the implications

2. Install the required dependencies:
```bash
pip install -r requirements.txt
```

3. Make the script executable:
```bash
chmod +x smart_mover.py
```

4. Run the application:
```bash
./smart_mover.py
```

## Logging

Logs are stored in `smart_mover.log` with automatic rotation at 10MB and 30-day retention.

## Operation

The script will:
1. Check cache disk usage every hour
2. If usage is above 90%, it will:
   - Fetch played items from Jellyfin
   - Identify matching files in cache
   - Move played files to the array
3. All operations are logged and include retry mechanisms for reliability
