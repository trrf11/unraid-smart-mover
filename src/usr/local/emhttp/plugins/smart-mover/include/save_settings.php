<?php
$cfg_file = "/usr/local/emhttp/plugins/smart-mover/smart-mover.cfg";

// Validate and sanitize inputs
$check_interval = filter_input(INPUT_POST, 'CHECK_INTERVAL', FILTER_VALIDATE_INT, 
    ["options" => ["min_range" => 1, "max_range" => 1440]]);
$cache_threshold = filter_input(INPUT_POST, 'CACHE_THRESHOLD', FILTER_VALIDATE_INT,
    ["options" => ["min_range" => 1, "max_range" => 99]]);
$jellyfin_url = filter_input(INPUT_POST, 'JELLYFIN_URL', FILTER_SANITIZE_URL);
$jellyfin_api_key = filter_input(INPUT_POST, 'JELLYFIN_API_KEY', FILTER_SANITIZE_STRING);
$service_enabled = filter_input(INPUT_POST, 'SERVICE_ENABLED', FILTER_VALIDATE_BOOLEAN);

// Build new config content
$config = [
    "CHECK_INTERVAL" => $check_interval,
    "CACHE_THRESHOLD" => $cache_threshold,
    "JELLYFIN_URL" => $jellyfin_url,
    "JELLYFIN_API_KEY" => $jellyfin_api_key,
    "SERVICE_ENABLED" => $service_enabled ? "true" : "false"
];

// Write to config file
$content = "";
foreach ($config as $key => $value) {
    $content .= "{$key}=\"{$value}\"\n";
}
file_put_contents($cfg_file, $content);

// Restart service if enabled
if ($service_enabled) {
    shell_exec("systemctl restart smart-mover.service");
} else {
    shell_exec("systemctl stop smart-mover.service");
}

// Redirect back to settings page
header("Location: /Settings/SmartMover");
