param(
    [Parameter(Mandatory = $true)][string]$CompilerPath,
    [Parameter(Mandatory = $true)][string]$FixtureOutput,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$OutputRoot
)
$ErrorActionPreference = 'Stop'
$names = @('dpv2_user_loot_sheet_authority_v1.json', 'compile_disambiguation.json', 'armor_single_slot_audit.json')
function Get-Sha([string]$Path) { if (-not [IO.File]::Exists($Path)) { return '' }; return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash).ToLowerInvariant() }
function Get-TextSha([string]$Text) { $sha=[Security.Cryptography.SHA256]::Create(); try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()} finally{$sha.Dispose()} }
function Seed-Case([string]$Path) { New-Item -ItemType Directory -Path $Path -Force | Out-Null; foreach($name in $names){[IO.File]::WriteAllText((Join-Path $Path $name),"OLD_SENTINEL|$([IO.Path]::GetFileNameWithoutExtension($name))")} }
function Get-OldSha([string]$Name) { Get-TextSha "OLD_SENTINEL|$([IO.Path]::GetFileNameWithoutExtension($Name))" }
$tokens=$null; $parseErrors=$null; $ast=[Management.Automation.Language.Parser]::ParseFile($CompilerPath,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count -ne 0){throw "SUPPLEMENT_PARSE_FAIL: $($parseErrors -join '; ')"}
$functions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)); foreach($f in $functions){.([scriptblock]::Create($f.Extent.Text))}
$realSnapshot=(Get-Command Get-WriteSetSnapshot -CommandType Function).ScriptBlock
$realMove=(Get-Command Move-WriteSetFile -CommandType Function).ScriptBlock
$entries=foreach($name in $names){$text=Get-Content (Join-Path $FixtureOutput $name)-Raw -Encoding UTF8;$v=$text|ConvertFrom-Json;[pscustomobject]@{name=$name;text=$text;schema=if($name -eq $names[0]){[string]$v.schema}else{''}}}
New-Item -ItemType Directory -Path $OutputRoot -Force|Out-Null
$receipt=[ordered]@{schema='hardcore.loot.compiler.write_set_fault_supplement.v1';compiler_sha256=Get-Sha $CompilerPath;fixture=$FixtureOutput;input_hashes=@{};cases=@();process_kill='NOT_RUN';power_loss='NOT_RUN'}
foreach($name in $names){$receipt.input_hashes[$name]=Get-Sha (Join-Path $FixtureOutput $name)}

$case=Join-Path $OutputRoot 'readback_failure_after_first_move'; Seed-Case $case; $script:moveCount=0;$script:readbackFault=$false
function Move-WriteSetFile([string]$Source,[string]$Destination,[bool]$Overwrite){$script:moveCount++; if($Overwrite){[IO.File]::Move($Source,$Destination,$true)}else{[IO.File]::Move($Source,$Destination)}}
function Get-WriteSetSnapshot($Snapshot,[string]$Context){if(-not $script:readbackFault -and $script:moveCount -ge 1 -and $Context -eq 'committed readback'){$script:readbackFault=$true;throw 'INJECTED_COMMITTED_READBACK_FAILURE'};&$realSnapshot $Snapshot $Context}
$failed=$false;$failureMessage='';try{Publish-ValidatedWriteSet $case $entries|Out-Null}catch{$failed=$true;$failureMessage=$_.Exception.Message};if(-not $failed -or -not $script:readbackFault -or $script:moveCount -ne 2){throw "SUPPLEMENT_FAIL: readback fault proof failed moves=$script:moveCount injected=$script:readbackFault"}
foreach($fileName in $names){if((Get-Sha (Join-Path $case $fileName))-ne (Get-OldSha $fileName)){throw "SUPPLEMENT_FAIL: readback rollback old bytes $fileName"}}
$receipt.cases+=[ordered]@{name='readback_failure_after_first_move';status='PASS';actual_move_count=$script:moveCount;injected_fault=$script:readbackFault;exception=$failureMessage;first_after_fault_sha=Get-Sha (Join-Path $case $names[0]);first_old_sha=Get-OldSha $names[0];all_old_bytes_restored=$true}

$case=Join-Path $OutputRoot 'rollback_snapshot_failure_retains_backup';Seed-Case $case;$script:moveCount=0;$script:rollbackSnapshotCalls=0
function Move-WriteSetFile([string]$Source,[string]$Destination,[bool]$Overwrite){$script:moveCount++;if($script:moveCount -eq 3){throw 'INJECTED_THIRD_MOVE_FAILURE'};if($Overwrite){[IO.File]::Move($Source,$Destination,$true)}else{[IO.File]::Move($Source,$Destination)}}
function Get-WriteSetSnapshot($Snapshot,[string]$Context){if($script:moveCount -ge 3 -and $Context -eq 'rollback' -and $script:rollbackSnapshotCalls -eq 0){$script:rollbackSnapshotCalls++;throw 'INJECTED_ROLLBACK_READ_FAILURE'};&$realSnapshot $Snapshot $Context}
$failed=$false;$failureMessage='';try{Publish-ValidatedWriteSet $case $entries|Out-Null}catch{$failed=$true;$failureMessage=$_.Exception.Message};if(-not $failed -or $script:rollbackSnapshotCalls -ne 1 -or $script:moveCount -ne 4){throw "SUPPLEMENT_FAIL: rollback read fault proof failed moves=$script:moveCount reads=$script:rollbackSnapshotCalls"}
$secondTarget=Join-Path $case $names[1];$secondBackups=@(Get-ChildItem -LiteralPath $case -Force -File|Where-Object{$_.Name -like "$($names[1]).txnbackup.*"});if($secondBackups.Count -ne 1){throw "SUPPLEMENT_FAIL: exact second backup count=$($secondBackups.Count)"}
$secondOldSha=Get-OldSha $names[1];$secondBackupSha=Get-Sha $secondBackups[0].FullName;if($secondBackupSha -ne $secondOldSha){throw "SUPPLEMENT_FAIL: second backup sha=$secondBackupSha expected=$secondOldSha"}
$secondNewSha=Get-Sha $secondTarget;$expectedSecondNew=Get-TextSha ([string]$entries[1].text);if($secondNewSha -ne $expectedSecondNew){throw 'SUPPLEMENT_FAIL: second target was unexpectedly overwritten during failed rollback'}
if((Get-Sha (Join-Path $case $names[0])) -ne (Get-OldSha $names[0])){throw 'SUPPLEMENT_FAIL: rollback loop did not restore first target'}
if((Get-Sha (Join-Path $case $names[2])) -ne (Get-OldSha $names[2])){throw 'SUPPLEMENT_FAIL: third target changed'}
$receipt.cases+=[ordered]@{name='rollback_snapshot_failure_retains_backup';status='PASS';actual_move_count=$script:moveCount;exception=$failureMessage;rollback_read_fault_injected=$true;second_backup_path=$secondBackups[0].FullName;second_backup_sha256=$secondBackupSha;second_old_sha256=$secondOldSha;second_current_new_sha256=$secondNewSha;first_restored=$true;third_unpublished_old=$true;rollback_loop_continued=$true}

$positive=Join-Path $OutputRoot 'positive_full_compiler';$pwsh=(Get-Command pwsh).Source;$stdout=Join-Path $OutputRoot 'positive_full_compiler.stdout.log';$out=&$pwsh -NoProfile -ExecutionPolicy Bypass -File $CompilerPath -ProjectRoot $ProjectRoot -OutputDir $positive 2>&1;@($out|ForEach-Object{[string]$_})|Set-Content $stdout -Encoding UTF8;$exit=$LASTEXITCODE;if($exit -ne 0){throw "SUPPLEMENT_FAIL: positive compiler exit=$exit"}
$expected=@{'dpv2_user_loot_sheet_authority_v1.json'='3c371628c2d0f51023a5c059439020f756a3762c88c3ae6ea4fa4a5790c99aff';'compile_disambiguation.json'='cae2e67d86c7a119fa24b6b0a7804a0f31e984fae2f34d813395f0e460de6182';'armor_single_slot_audit.json'='b71e42c72067b468f8309a0afdaf2987fd2c55f9dceb5e172ed6a7364350705c'};foreach($name in $names){if((Get-Sha(Join-Path $positive $name))-ne $expected[$name]){throw "SUPPLEMENT_FAIL: positive parity $name"}}
$receipt.cases+=[ordered]@{name='positive_full_compiler';status='PASS';exit_code=$exit;stdout=$stdout;output_sha256=$expected;source_input_rows='126 sheets/4876 named rows'}
$receipt|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutputRoot 'FAULT_SUPPLEMENT_RECEIPT.json') -Encoding UTF8;Write-Output 'WRITE_SET_FAULT_SUPPLEMENT_PASS'
