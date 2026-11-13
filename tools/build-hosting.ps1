$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $workspaceRoot
& flutter build web --release --dart-define=USE_FIREBASE_EMULATORS=false --base-href /
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# Generated Flutter tool metadata is not used by the deployed application.
# Remove this single known file so the local server and upload set agree.
$buildMarker = Join-Path $workspaceRoot 'build/web/.last_build_id'
if (Test-Path -LiteralPath $buildMarker) { Remove-Item -LiteralPath $buildMarker }
& node (Join-Path $PSScriptRoot 'verify-hosting-build.cjs') --record
exit $LASTEXITCODE
