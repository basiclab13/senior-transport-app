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
# The Firebase CLI does not consistently export a Functions endpoint to exec.
# HTTP regression tests must use the configured loopback endpoint, never infer
# or fall back to a deployed Callable URL.
$testFirebaseConfig = Get-Content -LiteralPath (Join-Path $workspaceRoot 'firebase.json') -Raw | ConvertFrom-Json
$testFunctionsConfig = $testFirebaseConfig.emulators.functions
if ($testFunctionsConfig.host -ne '127.0.0.1' -or $testFunctionsConfig.port -lt 1 -or $testFunctionsConfig.port -gt 65535) {
    throw 'Loopback Functions Emulator configuration is required.'
}
$env:FUNCTIONS_EMULATOR_HOST = "127.0.0.1:$($testFunctionsConfig.port)"
& firebase.cmd emulators:exec --only auth,firestore,functions,storage --project demo-senior-transport 'npm.cmd --prefix functions test'
exit $LASTEXITCODE
