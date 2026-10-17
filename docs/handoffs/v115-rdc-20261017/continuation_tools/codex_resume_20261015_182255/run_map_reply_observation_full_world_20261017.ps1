param([Parameter(Mandatory=$true)][string]$Label,[ValidateSet('kernel')][string]$Mode='kernel')
$ErrorActionPreference='Stop'
$r='C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore'
Set-Location -LiteralPath $r
$override=Join-Path $r 'override.cfg'
if(Test-Path -LiteralPath $override){throw 'Existing override must not be replaced'}
[IO.File]::WriteAllText($override,"[hardcore]`ndiagnostics/main_boot_trace=true`ndiagnostics/full_world_test_timeout_seconds=120`ndiagnostics/full_world_native_manifest_path=`"res://outputs/v115_multicore/codex_resume_20261015_182255/SOURCE_MANIFEST.map_reply_observation_20261017.json`"`ndiagnostics/full_world_native_manifest_sha256=`"0f3b37d1f43279e9b4633870768e64f610581a354afba777c9b404b7ac496178`"`n",[Text.UTF8Encoding]::new($false))
$hash=(Get-FileHash -LiteralPath $override -Algorithm SHA256).Hash
$scenes=@('tests/framework/multicore_v115_script_semantic_20261015.tscn','tests/framework/main_feature_command_loans_20261016.tscn','tests/framework/code_preparation_engine_namespace_capture_test.tscn','tests/framework/code_preparation_native_symbol_probe_test.tscn','tests/framework/code_preparation_scalar_math_probe_test.tscn')
$timeout=30
if($Mode -eq 'kernel'){$scenes=@('tests/framework/character_source_full_world_20261016.tscn');$timeout=60}
$inputs=@('override.cfg','outputs/v115_multicore/root_integration_20261014/SEMANTIC_SOURCE_INPUTS.json','outputs/v115_multicore/codex_resume_20261015_182255/EXACT_FIREWALL_IMPORT_CACHE_REUSE_20261016.json','outputs/v115_multicore/codex_resume_20261015_182255/SOURCE_MANIFEST.map_reply_observation_20261017.json')
$engine=Join-Path $r 'outputs/v115_multicore/codex_resume_20261015_182255/windows_map_reply_observation_20261017_build/Godot_v115-stable_win64_console.exe'
$rc=1
try {
 & (Join-Path $r 'tools/run_multicore_v115_tests.ps1') -Label $Label -TestPaths $scenes -GodotExecutable $engine -TimeoutSeconds $timeout -ApprovedFullWorld120 -ExternalInputPaths $inputs
 $rc=$LASTEXITCODE
} finally {
 if((Get-FileHash -LiteralPath $override -Algorithm SHA256).Hash -ne $hash){throw 'Scoped override changed; preserve rather than remove'}
 Remove-Item -LiteralPath $override
}
exit $rc
