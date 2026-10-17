param([Parameter(Mandatory=$true)][string]$Label)
$ErrorActionPreference='Stop'
$r='C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore'
Set-Location -LiteralPath $r
if(Test-Path -LiteralPath (Join-Path $r 'override.cfg')){throw 'No hidden production override permitted in Native cold capture'}
$scenes=@('tests/framework/multicore_v115_script_semantic_20261015.tscn','tests/framework/code_preparation_engine_namespace_capture_test.tscn','tests/framework/code_preparation_native_symbol_probe_test.tscn','tests/framework/code_preparation_scalar_math_probe_test.tscn')
$inputs=@('outputs/v115_multicore/root_integration_20261014/SEMANTIC_SOURCE_INPUTS.json','outputs/v115_multicore/codex_resume_20261015_182255/SOURCE_MANIFEST.map_reply_observation_20261017.json')
$engine=Join-Path $r 'outputs/v115_multicore/codex_resume_20261015_182255/windows_map_reply_observation_20261017_build/Godot_v115-stable_win64_console.exe'
& (Join-Path $r 'tools/run_multicore_v115_tests.ps1') -Label $Label -TestPaths $scenes -GodotExecutable $engine -TimeoutSeconds 30 -ExternalInputPaths $inputs
exit $LASTEXITCODE
