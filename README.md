# Jellyfin Smart Mover for Unraid

Intelligently moves played media from cache to array based on Jellyfin watch status. Only moves files you've already watched when cache usage exceeds your threshold.

## Features

- **Smart Moving** - Only moves media marked as played in Jellyfin
- **Cache Threshold** - Triggers only when cache usage exceeds configured percentage
- **Safe Transfers** - Uses rsync to verify transfers before removing source files
- **Media-Aware** - Movies move with entire folder (including subtitles), TV episodes move individually with matching subtitles
- **Path Translation** - Handles Docker container path mapping automatically
- **Cleanup** - Removes empty directories after moving files
- **Dry-Run Mode** - Preview what would be moved without making changes
- **Detailed Reporting** - Summary shows movies/episodes with video and subtitle counts

## Requirements

- Unraid with User Scripts plugin
- Jellyfin server with API access
- `jq` (auto-installs or via NerdPack)

## Quick Start

1. Copy `jellyfin_smart_mover.sh` to User Scripts
2. Edit the configuration variables at the top of the script
3. Run with `--dry-run` to test
4. Schedule as desired

## Configuration

### Required Settings

| Variable | Description | Example |
|----------|-------------|---------|
| `JELLYFIN_URL` | Jellyfin server URL | `http://your-server:8096` |
| `JELLYFIN_API_KEY` | API key from Jellyfin Dashboard > API Keys | 32-char hex string |
| `JELLYFIN_USER_ID` | User ID (32-char hex, found in user URL) | 32-char hex string |

### Cache Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `CACHE_DRIVE` | `/mnt/cache` | Cache drive path |
| `CACHE_THRESHOLD` | `90` | Percentage that triggers moving |

### Media Pool Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `MOVIES_POOL` | `movies-pool` | Movies share name |
| `TV_POOL` | `tv-pool` | TV shows share name |

### Path Mapping (Docker)

If Jellyfin runs in Docker with different mount paths:

| Variable | Description | Example |
|----------|-------------|---------|
| `JELLYFIN_PATH_PREFIX` | Path as seen by Jellyfin | `/media/media` |
| `LOCAL_PATH_PREFIX` | Corresponding Unraid path | `/mnt/cache/media` |

### Array Destination

| Option | Path | Use Case |
|--------|------|----------|
| Direct Disk | `/mnt/disk1` | Predictable placement on specific disk |
| User Share (bypass cache) | `/mnt/user0` | Let Unraid manage distribution |
| User Share | `/mnt/user` | **Not recommended** - may write back to cache |

## Usage

```bash
# Dry-run (preview only)
./jellyfin_smart_mover.sh --dry-run

# Live run
./jellyfin_smart_mover.sh
```

### Example Output

```
=========================================
Dry-run summary: Processed 150 played items from Jellyfin
=========================================
  Movies: 3 would be moved
    - Video files: 3
    - Subtitle files: 2
  TV Episodes: 12 would be moved
    - Video files: 12
    - Subtitle files: 8
  -----------------------------------------
  Total: 25 files (15 video, 10 subtitles)
  Skipped: 135 items (not on cache or already on array)
```

## How It Works

1. Checks if cache usage exceeds threshold
2. Queries Jellyfin API for all played movies and episodes
3. Translates Jellyfin paths to local Unraid paths
4. For each played item found on cache:
   - **Movies**: Moves entire folder (video + subtitles + extras)
   - **TV Episodes**: Moves video file + matching subtitle files (by S##E## pattern)
5. Uses rsync for safe transfer (verifies before deleting source)
6. Cleans up empty directories

## License

MIT
