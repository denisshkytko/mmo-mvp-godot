param(
  [string]$GodotPath
)

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
  $GodotPath = $env:GODOT_PATH
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
  Write-Host "ERROR: Godot path not provided. Use -GodotPath or set GODOT_PATH env var."
  exit 2
}

if (-not (Test-Path $GodotPath)) {
  Write-Host "ERROR: Godot executable not found at: $GodotPath"
  exit 2
}

# temp files for capturing output without PowerShell NativeCommandError noise
$tmpOut = [System.IO.Path]::GetTempFileName()
$tmpErr = [System.IO.Path]::GetTempFileName()

try {
  $args = @("--headless", "--script", "res://tests/run_headless.gd")

  $p = Start-Process -FilePath $GodotPath `
                     -ArgumentList $args `
                     -NoNewWindow `
                     -Wait `
                     -PassThru `
                     -RedirectStandardOutput $tmpOut `
                     -RedirectStandardError  $tmpErr

  $outText = ""
  if (Test-Path $tmpOut) { $outText += (Get-Content -Raw -Encoding UTF8 $tmpOut) }
  if (Test-Path $tmpErr) { $outText += (Get-Content -Raw -Encoding UTF8 $tmpErr) }

  # Print full Godot output
  if (-not [string]::IsNullOrWhiteSpace($outText)) {
    Write-Host $outText
  }

  # Decide result based on output markers
  if ($outText -match "SMOKE PASS") { exit 0 }
  if ($outText -match "SMOKE FAIL") { exit 1 }
  if ($outText -match "SCRIPT ERROR") { exit 1 }
  if ($outText -match "ERROR:") { exit 1 }

  # fallback: if nothing matched, consider it failure
  exit 1
}
finally {
  if (Test-Path $tmpOut) { Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue }
  if (Test-Path $tmpErr) { Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue }
}
