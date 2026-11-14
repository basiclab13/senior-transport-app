param([switch]$EnableProductionAi, [switch]$EnableStorageWorkPhotos)
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $workspaceRoot
$productionAiFlag = if ($EnableProductionAi) { 'true' } else { 'false' }
$workPhotoFlag = if ($EnableStorageWorkPhotos) { 'true' } else { 'false' }
& flutter build web --release --dart-define=USE_FIREBASE_EMULATORS=false "--dart-define=ENABLE_PRODUCTION_AI=$productionAiFlag" "--dart-define=ENABLE_STORAGE_WORK_PHOTOS=$workPhotoFlag" --base-href /
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# Generated Flutter tool metadata is not used by the deployed application.
# Remove this single known file so the local server and upload set agree.
$buildMarker = Join-Path $workspaceRoot 'build/web/.last_build_id'
if (Test-Path -LiteralPath $buildMarker) { Remove-Item -LiteralPath $buildMarker }
& node (Join-Path $PSScriptRoot 'verify-hosting-build.cjs') --record
exit $LASTEXITCODE
