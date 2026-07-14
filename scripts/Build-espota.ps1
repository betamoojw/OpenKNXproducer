####################################################################################################
#   Open ■
#   ┬────┴  Build espota standalone binary
#   ■ KNX   2024 OpenKNX - Erkan Çolak
#
# Repackages the plain tools/esptools/espota.py into a single self-contained executable
# (espota.exe on Windows, espota on mac/linux) using PyInstaller, and drops it into the
# matching tools/esptools/<OS> folder so the release picks up the current version.
#
# The installer uses espota.py directly on mac/linux; this script is mainly needed to refresh
# the bundled Windows espota.exe. Run it from the OpenKNXproducer repo root:  ./scripts/Build-espota.ps1
####################################################################################################

param(
  [switch]$Verbose = $false,
  [string]$Source  = "tools/esptools/espota.py"   # path to the espota.py to package
)

$checkmarkChar = [char]::ConvertFromUtf32(0x2714)
$infoChar      = [char]::ConvertFromUtf32(0x2139)

# --- detect OS + target folder ---------------------------------------------------------------
$IsWinEnv = -not ($IsLinux -or $IsMacOS)
$osFolder = if ($IsWinEnv) { "Windows/x64" } elseif ($IsMacOS) { "MacOS" } else { "Linux" }
$exeName  = if ($IsWinEnv) { "espota.exe" } else { "espota" }
$destDir  = "tools/esptools/$osFolder"
$destPath = "$destDir/$exeName"

if (-not (Test-Path -Path $Source)) {
  Write-Host "ERROR: espota source not found at '$Source'." -ForegroundColor Red
  exit 1
}

# --- ensure PyInstaller is available (user space, on consent) --------------------------------
function Get-PyCommand {
  foreach ($c in @('python3', 'python')) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { return $c }
  }
  return $null
}

$py = Get-PyCommand
if (-not $py) {
  Write-Host "ERROR: Python not found. Please install Python 3 first." -ForegroundColor Red
  exit 1
}

# is PyInstaller importable?
& $py -c "import PyInstaller" 2>$null
if ($LASTEXITCODE -ne 0) {
  $answer = Read-Host "PyInstaller not found. Install it in user space (pip --user)? (y/n)"
  if ($answer -eq 'y') {
    & $py -m pip install --user pyinstaller
    if ($LASTEXITCODE -ne 0) {
      Write-Host "- Retry with --user --break-system-packages (PEP 668) ..." -ForegroundColor Yellow
      & $py -m pip install --user --break-system-packages pyinstaller
    }
  }
  & $py -c "import PyInstaller" 2>$null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: PyInstaller still not available. Install manually: $py -m pip install --user pyinstaller" -ForegroundColor Red
    exit 1
  }
}

# --- build ------------------------------------------------------------------------------------
$work = Join-Path ([System.IO.Path]::GetTempPath()) "openknx-espota-build"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -Path $work -ItemType Directory | Out-Null

Write-Host "- Packaging '$Source' -> '$destPath' with PyInstaller ..." -ForegroundColor Green -NoNewline
$piArgs = @(
  "-m", "PyInstaller",
  "--onefile", "--console", "--clean",
  "--name", "espota",
  "--distpath", (Join-Path $work "dist"),
  "--workpath", (Join-Path $work "build"),
  "--specpath", $work,
  $Source
)
if ($Verbose) { & $py @piArgs } else { & $py @piArgs *> (Join-Path $work "pyinstaller.log") }

$built = Join-Path $work "dist/$exeName"
if (-not (Test-Path $built)) {
  Write-Host "`tERROR" -ForegroundColor Red
  Write-Host "PyInstaller did not produce '$built'. See log: $(Join-Path $work 'pyinstaller.log')" -ForegroundColor Red
  exit 1
}

if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
Copy-Item -Path $built -Destination $destPath -Force
if (-not $IsWinEnv) { Start-Process chmod -ArgumentList "+x", $destPath -NoNewWindow -Wait -ErrorAction SilentlyContinue }
Write-Host "`t$checkmarkChar Done" -ForegroundColor Green

# --- cleanup ----------------------------------------------------------------------------------
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue

Write-Host "$infoChar espota packaged: $destPath" -ForegroundColor Cyan
