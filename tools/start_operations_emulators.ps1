param([switch]$ImportSnapshot)
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $workspaceRoot
$nodeFolder = Get-ChildItem -LiteralPath (Join-Path $workspaceRoot '.local-tools/node') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
$javaFolder = Get-ChildItem -LiteralPath (Join-Path $workspaceRoot '.local-tools/java') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($nodeFolder) { $env:PATH = "$($nodeFolder.FullName);$env:PATH" }
if ($javaFolder) { $env:PATH = "$($javaFolder.FullName)/bin;$env:PATH" }
$env:XDG_CONFIG_HOME = Join-Path $workspaceRoot '.local-tools/config'
$env:CI = 'true'
$env:DEBUG = ''
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '60'
$env:FIREBASE_CLI_DISABLE_MOTD = 'true'
$emulatorArguments = @('emulators:start', '--only', 'auth,firestore,functions', '--project', 'demo-senior-transport')
if ($ImportSnapshot) {
  $snapshotPath = Join-Path $workspaceRoot '.emulator-data/operations-20x80-20261113'
  if (!(Test-Path -LiteralPath (Join-Path $snapshotPath 'firebase-export-metadata.json'))) { throw 'Local operations snapshot not found' }
  $emulatorArguments += "--import=$snapshotPath"
}
& firebase.cmd @emulatorArguments
exit $LASTEXITCODE
