$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $workspaceRoot
$nodeFolder = Get-ChildItem -LiteralPath (Join-Path $workspaceRoot '.local-tools/node') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($nodeFolder) { $env:PATH = "$($nodeFolder.FullName);$env:PATH" }
$env:XDG_CONFIG_HOME = Join-Path $workspaceRoot '.local-tools/config'
$env:CI = 'true'
$env:DEBUG = ''
$env:FIREBASE_CLI_DISABLE_MOTD = 'true'
& node tools/verify-hosting-build.cjs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& node --test tools/test/hosting-build.test.cjs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& firebase.cmd emulators:exec --only hosting --project demo-senior-transport 'node tools/test-hosting-http.cjs'
exit $LASTEXITCODE
