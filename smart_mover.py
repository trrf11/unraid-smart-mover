#!/usr/bin/env python3
import os
import time
import json
from pathlib import Path
import requests
import psutil
from tenacity import retry, stop_after_attempt, wait_exponential
from loguru import logger
import sys

# Configure logging
logger.add("/boot/config/plugins/user.scripts/smart_mover.log", rotation="10 MB", retention="30 days", level="INFO")

class SmartMover:
    def __init__(self, config_path="/boot/config/plugins/user.scripts/smart_mover_config.json"):
        self.config_path = config_path
        self.load_config()
        
        if not all([self.jellyfin_url, self.jellyfin_api_key]):
            raise ValueError("Missing Jellyfin configuration")

    def load_config(self):
        """Load configuration from JSON file."""
        default_config = {
            "jellyfin_url": "",
            "jellyfin_api_key": "",
            "cache_threshold": 90,
            "check_interval": 60
        }
        
        try:
            if os.path.exists(self.config_path):
                with open(self.config_path, 'r') as f:
                    config = json.load(f)
            else:
                config = default_config
                with open(self.config_path, 'w') as f:
                    json.dump(default_config, f, indent=4)
                    
            self.jellyfin_url = config.get('jellyfin_url', '')
            self.jellyfin_api_key = config.get('jellyfin_api_key', '')
            self.cache_threshold = config.get('cache_threshold', 90)
            self.cache_path = '/mnt/cache'
            self.array_path = '/mnt/user'
            self.check_interval = config.get('check_interval', 60)
            
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            raise

    def get_cache_usage_percentage(self):
        """Get the current cache disk usage percentage."""
        try:
            usage = psutil.disk_usage(self.cache_path)
            return (usage.used / usage.total) * 100
        except Exception as e:
            logger.error(f"Error getting cache usage: {e}")
            return 0

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    def get_played_items(self):
        """Get list of played items from Jellyfin."""
        headers = {
            'X-MediaBrowser-Token': self.jellyfin_api_key
        }
        
        try:
            response = requests.get(
                f"{self.jellyfin_url}/Users/*/Items",
                headers=headers,
                params={
                    'IsPlayed': 'true',
                    'Recursive': 'true',
                    'IncludeItemTypes': 'Movie,Episode'
                }
            )
            response.raise_for_status()
            return response.json().get('Items', [])
        except Exception as e:
            logger.error(f"Error fetching played items from Jellyfin: {e}")
            raise

    def get_cache_files(self):
        """Get list of media files in cache."""
        cache_files = []
        for ext in ['.mp4', '.mkv', '.avi', '.m4v']:
            cache_files.extend(Path(self.cache_path).rglob(f'*{ext}'))
        return cache_files

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    def move_file(self, source_path, dest_path):
        """Move a file from cache to array."""
        try:
            dest_dir = os.path.dirname(dest_path)
            os.makedirs(dest_dir, exist_ok=True)
            
            # Use Unraid's mover command
            os.system(f'mv "{source_path}" "{dest_path}"')
            logger.info(f"Moved file: {source_path} -> {dest_path}")
            return True
        except Exception as e:
            logger.error(f"Error moving file {source_path}: {e}")
            raise

    def check_and_move(self):
        """Main function to check conditions and move files if necessary."""
        try:
            cache_usage = self.get_cache_usage_percentage()
            logger.info(f"Current cache usage: {cache_usage:.2f}%")
            
            if cache_usage < self.cache_threshold:
                logger.info("Cache usage below threshold, no action needed")
                return
            
            played_items = self.get_played_items()
            cache_files = self.get_cache_files()
            
            moved_count = 0
            for played_item in played_items:
                for cache_file in cache_files:
                    if played_item['Name'] in str(cache_file):
                        dest_path = str(cache_file).replace(self.cache_path, self.array_path)
                        if self.move_file(str(cache_file), dest_path):
                            moved_count += 1
            
            logger.info(f"Moved {moved_count} files to array")
            
        except Exception as e:
            logger.error(f"Error in check_and_move: {e}")

def main():
    try:
        mover = SmartMover()
        while True:
            mover.check_and_move()
            time.sleep(mover.check_interval * 60)  # Convert minutes to seconds
    except Exception as e:
        logger.error(f"Smart Mover failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
