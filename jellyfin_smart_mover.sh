#!/bin/bash

#########################################
##        Jellyfin Smart Mover        ##
#########################################
#
# Description: Moves media files from cache to array based on Jellyfin playback status
# Author: Tim Fokker
# Date: 2024-02-21
#
# Requirements:
# - jq: Install through Community Applications -> NerdPack
#   OR run: curl -L -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x /usr/local/bin/jq
#
# Variables:
JELLYFIN_URL="http://localhost:8096"  # Change this to your Jellyfin server URL
JELLYFIN_API_KEY=""                   # Your Jellyfin API key
JELLYFIN_USER_ID=""                   # Your Jellyfin user ID
CACHE_THRESHOLD=90                    # Percentage of cache usage that triggers moving files
CACHE_DRIVE="/mnt/cache"
DEBUG=true                            # Set to true to enable debug logging

#########################################
##       ARRAY_PATH Configuration      ##
#########################################
#
# Choose where files should be moved when clearing cache. Three options:
#
# OPTION 1: Direct Disk Path (Default - Recommended for most users)
#   ARRAY_PATH="/mnt/disk1"
#   - Files are written directly to a specific disk
#   - Guarantees files go to that exact disk
#   - Use /mnt/disk2, /mnt/disk3, etc. for other disks
#   - Best for: Users who want predictable, controlled file placement
#
# OPTION 2: User Share with Cache Bypass (Requires Unraid 6.9+)
#   ARRAY_PATH="/mnt/user0"
#   - Files go to array via user share, bypassing cache
#   - Unraid distributes files across disks based on allocation method
#   - Respects split levels and allocation settings
#   - Best for: Users who want Unraid to manage disk distribution
#
# OPTION 3: Standard User Share - DO NOT USE!
#   ARRAY_PATH="/mnt/user"   # WARNING: Can write back to cache!
#   - This path includes the cache drive
#   - Files may be written back to cache, defeating the purpose
#   - Only use if you understand the implications
#
ARRAY_PATH="/mnt/disk1"

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/jellyfin_smart_mover.log"

# Function to log messages to both console and file
log_message() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Initialize log file
initialize_logging() {
    # Create log file if it doesn't exist
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
    
    # Add script start marker to log
    log_message "=== Script started at $(date '+%Y-%m-%d %H:%M:%S') ==="
    log_message "Using log file: $LOG_FILE"
}

# Function to log debug messages
debug_log() {
    log_message "DEBUG: $1"
}

# Function to log error messages
error_log() {
    log_message "ERROR: $1"
}

# Function to test API endpoints
test_api_endpoints() {
    log_message "DEBUG: Testing API connection..."
    
    # Test base URL
    local test_url="$JELLYFIN_URL/System/Info/Public"
    log_message "DEBUG: Testing base URL: $test_url"
    
    local tmp_response
    tmp_response=$(mktemp)
    local tmp_headers
    tmp_headers=$(mktemp)
    
    # Test with simple GET request
    if ! curl -s -f -o "$tmp_response" -D "$tmp_headers" \
        -H "X-MediaBrowser-Token: $JELLYFIN_API_KEY" \
        -H "Accept: application/json" \
        "$test_url"; then
        log_message "ERROR: Failed to connect to Jellyfin server at $JELLYFIN_URL"
        rm -f "$tmp_response" "$tmp_headers"
        return 1
    fi
    
    # Get HTTP status code
    local status_code
    status_code=$(grep -i "^HTTP" "$tmp_headers" | tail -n1 | awk '{print $2}')
    
    if [ "$status_code" != "200" ]; then
        log_message "ERROR: Server returned status code $status_code"
        rm -f "$tmp_response" "$tmp_headers"
        return 1
    fi
    
    # Test user endpoint
    local user_url="$JELLYFIN_URL/Users/$JELLYFIN_USER_ID"
    log_message "DEBUG: Testing user endpoint: $user_url"
    
    if ! curl -s -f -o "$tmp_response" -D "$tmp_headers" \
        -H "X-MediaBrowser-Token: $JELLYFIN_API_KEY" \
        -H "Accept: application/json" \
        "$user_url"; then
        log_message "ERROR: Failed to access user endpoint. Check JELLYFIN_USER_ID"
        rm -f "$tmp_response" "$tmp_headers"
        return 1
    fi
    
    # Get HTTP status code for user endpoint
    status_code=$(grep -i "^HTTP" "$tmp_headers" | tail -n1 | awk '{print $2}')
    
    if [ "$status_code" != "200" ]; then
        log_message "ERROR: User endpoint returned status code $status_code"
        rm -f "$tmp_response" "$tmp_headers"
        return 1
    fi
    
    # Test items endpoint with minimal query
    local items_url="$JELLYFIN_URL/Users/$JELLYFIN_USER_ID/Items?Limit=1"
    log_message "DEBUG: Testing items endpoint: $items_url"
    
    if ! curl -s -f -o "$tmp_response" -D "$tmp_headers" \
        -H "X-MediaBrowser-Token: $JELLYFIN_API_KEY" \
        -H "Accept: application/json" \
        "$items_url"; then
        log_message "ERROR: Failed to access items endpoint"
        rm -f "$tmp_response" "$tmp_headers"
        return 1
    fi
    
    # Validate JSON response
    if ! jq empty "$tmp_response" > /dev/null 2>&1; then
        log_message "ERROR: Invalid JSON response from items endpoint"
        log_message "DEBUG: Raw response: $(cat "$tmp_response")"
        rm -f "$tmp_response" "$tmp_headers"
        return 1
    fi
    
    log_message "DEBUG: All API endpoints tested successfully"
    rm -f "$tmp_response" "$tmp_headers"
    return 0
}

# Function to make API call with logging
make_api_call() {
    local url="$1"
    local method="$2"
    local description="$3"
    
    log_message "DEBUG: Making $method request to: $url at $(date '+%Y-%m-%d %H:%M:%S')"
    log_message "DEBUG: Request headers: X-MediaBrowser-Token: [hidden], Accept: application/json"
    
    # Create temporary files
    local tmp_response
    tmp_response=$(mktemp)
    local tmp_final
    tmp_final=$(mktemp)
    local tmp_headers
    tmp_headers=$(mktemp)
    
    # Ensure temp files are cleaned up
    trap 'rm -f "$tmp_response" "$tmp_final" "$tmp_headers"' EXIT
    
    # Make the curl call with verbose output for debugging
    if ! curl -v -s -w "\n%{http_code}" \
        -X "$method" \
        -H "X-MediaBrowser-Token: $JELLYFIN_API_KEY" \
        -H "Accept: application/json" \
        "$url" 2>"$tmp_headers" > "$tmp_response"; then
        log_message "ERROR: Curl command failed for $description"
        log_message "DEBUG: Curl headers: $(cat "$tmp_headers")"
        return 1
    fi
    
    # Extract status code from last line and remove it from response
    local status_code
    status_code=$(tail -n1 "$tmp_response")
    head -n -1 "$tmp_response" > "$tmp_final"
    
    log_message "DEBUG: API response code for $description: $status_code"
    log_message "DEBUG: Curl headers: $(cat "$tmp_headers")"
    
    # Log response body for debugging (truncated if too long)
    local response_preview
    response_preview=$(head -c 500 "$tmp_final")
    log_message "DEBUG: First 500 chars of response: $response_preview"
    
    if [ "$status_code" != "200" ]; then
        log_message "ERROR: API call failed for $description. Status code: $status_code"
        log_message "DEBUG: Full response body: $(cat "$tmp_final")"
        return 1
    fi
    
    cat "$tmp_final"
    return 0
}

# Function to get played items from Jellyfin
get_played_items() {
    log_message "DEBUG: Starting get_played_items function at $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Create temporary files
    local tmp_response
    tmp_response=$(mktemp)
    local tmp_paths
    tmp_paths=$(mktemp)
    local tmp_error
    tmp_error=$(mktemp)
    
    # Ensure temp files are cleaned up
    trap 'rm -f "$tmp_response" "$tmp_paths" "$tmp_error"' EXIT
    
    # Get the API response
    local api_url="$JELLYFIN_URL/Users/$JELLYFIN_USER_ID/Items"
    local query_params="IsPlayed=true&IncludeItemTypes=Movie,Episode&SortBy=LastPlayedDate&SortOrder=Descending&Recursive=true"
    local full_url="${api_url}?${query_params}"
    
    log_message "DEBUG: API request details at $(date '+%Y-%m-%d %H:%M:%S'):"
    log_message "DEBUG: Base URL: $JELLYFIN_URL"
    log_message "DEBUG: User ID: $JELLYFIN_USER_ID"
    log_message "DEBUG: Full URL: $full_url"
    
    # Make the API call and save to temp file
    log_message "DEBUG: Making API call to get played items..."
    if ! make_api_call "$full_url" "GET" "Getting played items" > "$tmp_response"; then
        log_message "ERROR: API call failed at $(date '+%Y-%m-%d %H:%M:%S')"
        log_message "DEBUG: API response saved to: $tmp_response"
        log_message "DEBUG: Response content: $(cat "$tmp_response")"
        return 1
    fi

    # Verify we got a response
    if [ ! -s "$tmp_response" ]; then
        log_message "ERROR: Empty response from API at $(date '+%Y-%m-%d %H:%M:%S')"
        return 1
    fi

    log_message "DEBUG: Successfully received API response at $(date '+%Y-%m-%d %H:%M:%S')"
    log_message "DEBUG: Response file size: $(wc -c < "$tmp_response") bytes"
    log_message "DEBUG: First 500 chars of response: $(head -c 500 "$tmp_response")"

    # Process the response with jq and show the command for debugging
    local jq_cmd='.Items[] | select(.Path != null) | .Path'
    log_message "DEBUG: Running jq command at $(date '+%Y-%m-%d %H:%M:%S'): $jq_cmd"
    
    if ! jq -r "$jq_cmd" "$tmp_response" > "$tmp_paths" 2> "$tmp_error"; then
        log_message "ERROR: Failed to parse played items JSON at $(date '+%Y-%m-%d %H:%M:%S')"
        log_message "DEBUG: JQ Error: $(cat "$tmp_error")"
        log_message "DEBUG: Response data: $(cat "$tmp_response")"
        return 1
    fi

    # Handle empty results
    if [ ! -s "$tmp_paths" ]; then
        log_message "DEBUG: No played items found in response at $(date '+%Y-%m-%d %H:%M:%S')"
        return 0
    fi

    # Log number of items found
    local item_count
    item_count=$(wc -l < "$tmp_paths")
    log_message "DEBUG: Found $item_count played items at $(date '+%Y-%m-%d %H:%M:%S')"

    # Output the paths
    cat "$tmp_paths"
    return 0
}

# Function to process a single item
process_item() {
    local item_path="$1"
    local cache_usage="$2"
    
    # Skip empty paths or debug messages
    if [ -z "$item_path" ] || [[ "$item_path" == *"DEBUG:"* ]] || [[ "$item_path" == *"ERROR:"* ]]; then
        return 0
    fi
    
    log_message "DEBUG: Processing item: $item_path"
    
    # Check if file exists
    if [ ! -f "$item_path" ]; then
        log_message "DEBUG: Skipping $item_path - file not found"
        return 0
    fi
    
    # Check if file is on cache drive
    if [[ "$item_path" != "$CACHE_DRIVE"* ]]; then
        log_message "DEBUG: Skipping $item_path - not on cache drive"
        return 0
    fi
    
    # Get target path on array
    local rel_path="${item_path#$CACHE_DRIVE/}"
    local array_path="$ARRAY_PATH/$rel_path"
    
    # Check if target already exists
    if [ -f "$array_path" ]; then
        log_message "DEBUG: Target file already exists: $array_path"
        return 0
    fi
    
    log_message "DEBUG: Moving $item_path to $array_path"
    
    # Create target directory if it doesn't exist
    local target_dir
    target_dir=$(dirname "$array_path")
    if ! mkdir -p "$target_dir"; then
        log_message "ERROR: Failed to create target directory: $target_dir"
        return 1
    fi
    
    # Move file
    if mv "$item_path" "$array_path"; then
        log_message "Successfully moved: $item_path to array"
        return 0
    else
        log_message "ERROR: Failed to move $item_path to $array_path"
        return 1
    fi
}

# Function to process all played items
process_played_items() {
    local cache_usage=$1
    local count=0
    local moved=0
    local errors=0
    
    log_message "DEBUG: Processing played items with cache usage at $cache_usage%"
    
    # Create temporary file for played items
    local tmp_items
    tmp_items=$(mktemp)
    
    # Ensure temp file is cleaned up
    trap 'rm -f "$tmp_items"' EXIT
    
    # Get list of played items and save to temp file
    if ! get_played_items > "$tmp_items"; then
        log_message "ERROR: Failed to get played items list"
        return 1
    fi

    # If no items found, exit successfully
    if [ ! -s "$tmp_items" ]; then
        log_message "DEBUG: No items to process"
        return 0
    fi

    # Process each item from the file
    while IFS= read -r path; do
        # Skip empty lines and debug/error messages
        if [ -z "$path" ] || [[ "$path" == *"DEBUG:"* ]] || [[ "$path" == *"ERROR:"* ]]; then
            continue
        fi
        
        count=$((count + 1))
        log_message "DEBUG: Processing item $count: $path"
        
        if process_item "$path" "$cache_usage"; then
            moved=$((moved + 1))
        else
            errors=$((errors + 1))
        fi
    done < "$tmp_items"
    
    log_message "Summary: Processed $count items, moved $moved files, encountered $errors errors"
    return 0
}

# Function to validate environment
validate_environment() {
    set -e  # Exit on error
    trap 'log_message "ERROR: An error occurred in validate_environment at line $LINENO"' ERR
    
    log_message "DEBUG: Validating environment..."
    
    # Check required environment variables
    if [ -z "$JELLYFIN_URL" ]; then
        log_message "ERROR: JELLYFIN_URL is not set"
        return 1
    fi
    log_message "DEBUG: JELLYFIN_URL is set to: $JELLYFIN_URL"
    
    if [ -z "$JELLYFIN_API_KEY" ]; then
        log_message "ERROR: JELLYFIN_API_KEY is not set"
        return 1
    fi
    log_message "DEBUG: JELLYFIN_API_KEY is set (value hidden)"
    
    if [ -z "$JELLYFIN_USER_ID" ]; then
        log_message "ERROR: JELLYFIN_USER_ID is not set"
        return 1
    fi
    log_message "DEBUG: JELLYFIN_USER_ID is set to: $JELLYFIN_USER_ID"
    
    # Test Jellyfin connection
    log_message "DEBUG: Testing Jellyfin connection..."
    local test_response
    test_response=$(make_api_call "$JELLYFIN_URL/System/Info" "GET" "System Info")
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to connect to Jellyfin server"
        return 1
    fi
    log_message "DEBUG: System Info response: $test_response"
    
    # Validate user ID exists
    log_message "DEBUG: Validating user ID..."
    local user_test
    user_test=$(make_api_call "$JELLYFIN_URL/Users/$JELLYFIN_USER_ID" "GET" "User Info")
    if [ $? -ne 0 ]; then
        log_message "ERROR: Invalid user ID: $JELLYFIN_USER_ID"
        log_message "DEBUG: User Info response: $user_test"
        return 1
    fi
    log_message "DEBUG: User Info response: $user_test"
    
    log_message "DEBUG: Successfully connected to Jellyfin server"
    
    # Log environment settings
    log_message "DEBUG: Environment settings:"
    log_message "DEBUG: - CACHE_DRIVE=$CACHE_DRIVE"
    log_message "DEBUG: - ARRAY_PATH=$ARRAY_PATH"
    log_message "DEBUG: - CACHE_THRESHOLD=$CACHE_THRESHOLD"
    
    return 0
}

# Function to check and install jq if needed
check_jq() {
    if ! command -v jq &> /dev/null; then
        log_message "jq not found. Attempting to install..."
        if curl -L -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64; then
            chmod +x /usr/local/bin/jq
            log_message "jq installed successfully"
        else
            log_message "ERROR: Failed to install jq. Please install it manually through the NerdPack plugin"
            log_message "Or run: curl -L -o /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x /usr/local/bin/jq"
            exit 1
        fi
    fi
}

# Function to check if mover is running
is_mover_running() {
    if [ -f /var/run/mover.pid ]; then
        if kill -0 $(cat /var/run/mover.pid) 2>/dev/null; then
            return 0  # Mover is running
        fi
    fi
    return 1  # Mover is not running
}

# Function to check if parity check is running
is_parity_running() {
    if [ -f /proc/mdstat ]; then
        if grep -q "resync" /proc/mdstat; then
            return 0  # Parity check is running
        fi
    fi
    return 1  # Parity check is not running
}

# Function to check cache usage
check_cache_usage() {
    local cache_path="$1"
    local usage
    
    # Get disk usage percentage without logging
    usage=$(df -h "$cache_path" | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ -z "$usage" ]; then
        log_message "ERROR: Could not determine cache usage"
        return 1
    fi
    
    # Return just the number
    echo "$usage"
    return 0
}

# Main function
main() {
    # Initialize logging
    initialize_logging
    
    # Check for jq
    if ! check_jq; then
        log_message "Error: jq is required but not installed"
        exit 1
    fi
    
    # Validate environment first
    if ! validate_environment; then
        log_message "ERROR: Environment validation failed"
        exit 1
    fi

    # Debug: Print environment variables
    log_message "DEBUG: Environment settings:"
    log_message "DEBUG: - CACHE_DRIVE=$CACHE_DRIVE"
    log_message "DEBUG: - ARRAY_PATH=$ARRAY_PATH"
    log_message "DEBUG: - CACHE_THRESHOLD=$CACHE_THRESHOLD"
    
    # Validate required paths
    if [ ! -d "$CACHE_DRIVE" ]; then
        log_message "ERROR: Cache drive path does not exist: $CACHE_DRIVE"
        exit 1
    fi
    
    if [ ! -d "$ARRAY_PATH" ]; then
        log_message "ERROR: Array path does not exist: $ARRAY_PATH"
        exit 1
    fi

    # Check if mover is running
    if is_mover_running; then
        log_message "Mover is currently running, exiting"
        exit 0
    fi

    # Check cache usage
    log_message "DEBUG: Checking cache usage for $CACHE_DRIVE"
    local cache_usage
    cache_usage=$(check_cache_usage "$CACHE_DRIVE")
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to check cache usage"
        exit 1
    fi
    log_message "DEBUG: Cache usage is ${cache_usage}%"
    log_message "Current cache usage: ${cache_usage}%"

    # Only process if cache usage is above threshold
    if [ "$cache_usage" -ge "$CACHE_THRESHOLD" ]; then
        log_message "Cache usage (${cache_usage}%) is above threshold (${CACHE_THRESHOLD}%), processing played items"
        if ! process_played_items "$cache_usage"; then
            log_message "ERROR: Failed to process played items"
            exit 1
        fi
    else
        log_message "Cache usage (${cache_usage}%) is below threshold (${CACHE_THRESHOLD}%), no action needed"
    fi
}

# Run main function
main
