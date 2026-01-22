#!/bin/bash

# Install required Python packages if not already installed
pip3 install --no-cache-dir requests psutil tenacity loguru

# Create the config file if it doesn't exist
CONFIG_FILE="/boot/config/plugins/user.scripts/smart_mover_config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << EOF
{
    "jellyfin_url": "http://localhost:8096",
    "jellyfin_api_key": "",
    "cache_threshold": 90,
    "check_interval": 60
}
EOF
fi

# Run the Python script
python3 /boot/config/plugins/user.scripts/smart_mover.py
