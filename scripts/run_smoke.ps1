param(
    [Parameter(Mandatory = $false)]
    [string]$GodotPath
)

if (-not $GodotPath -or $GodotPath.Trim() -eq "") {
    $GodotPath = $env:GODOT_PATH
}

if (-not $GodotPath -or $GodotPath.Trim() -eq "") {
    Write-Error "Godot path not provided. Use -GodotPath or set GODOT_PATH."
    exit 1
}

$arguments = @("--headless", "--script", "res://tests/run_headless.gd")
$output = & $GodotPath @arguments 2>&1 | Out-String
Write-Output $output

if ($output -match "SMOKE PASS") {
    exit 0
}
if ($output -match "SMOKE FAIL") {
    exit 1
}
if ($output -match "SCRIPT ERROR" -or $output -match "ERROR:") {
    exit 1
}

exit 1
