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
$env:FIREBASE_CLI_DISABLE_MOTD = 'true'
& firebase.cmd emulators:exec --only auth,firestore,functions --project demo-senior-transport 'npm.cmd --prefix functions test'
exit $LASTEXITCODE
