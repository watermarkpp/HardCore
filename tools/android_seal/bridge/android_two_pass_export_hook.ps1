# Candidate functions only. Dot-sourcing does not run an export.
# Existing build owns JAVA/Android/APPDATA isolation and fixed commit staging.
Set-StrictMode -Version 2.0

function Get-CodeExportHash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-CodeExportFrozen([hashtable]$Hashes) {
    foreach ($Path in $Hashes.Keys) {
        if ((Get-CodeExportHash $Path) -cne $Hashes[$Path]) { throw "Fixed stage input changed: $Path" }
    }
}

function Assert-CodeExportSigner([string]$Apk, [string]$BaselineApk, [string]$ApkSigner) {
    $CandidateText = ((& $ApkSigner verify --verbose --print-certs $Apk 2>&1) -join "`n")
    if ($LASTEXITCODE -ne 0) { throw 'Candidate signature verify failed.' }
    $BaselineText = ((& $ApkSigner verify --print-certs $BaselineApk 2>&1) -join "`n")
    if ($LASTEXITCODE -ne 0) { throw 'Baseline signature verify failed.' }
    $Pattern = '(?m)^Signer #[0-9]+ certificate SHA-256 digest:\s*([0-9a-fA-F]+)\s*$'
    $CandidateIds = @([regex]::Matches($CandidateText, $Pattern) | ForEach-Object {$_.Groups[1].Value.ToLowerInvariant()} | Sort-Object)
    $BaselineIds = @([regex]::Matches($BaselineText, $Pattern) | ForEach-Object {$_.Groups[1].Value.ToLowerInvariant()} | Sort-Object)
    if ($CandidateIds.Count -eq 0 -or ($CandidateIds -join ',') -cne ($BaselineIds -join ',')) { throw 'APK signer differs from baseline.' }
    return @{status='PASS'; certificate_sha256=$CandidateIds; apk_sha256=(Get-CodeExportHash $Apk); apksigner_sha256=(Get-CodeExportHash $ApkSigner)}
}

function Invoke-CodeOfficialExport([string]$GodotConsole, [string]$StageRoot, [string]$Apk, [string]$EvidenceRoot, [string]$Name) {
    $Log = Join-Path $EvidenceRoot "$Name.engine.log"
    $Stdout = Join-Path $EvidenceRoot "$Name.stdout.log"
    $Stderr = Join-Path $EvidenceRoot "$Name.stderr.log"
    # Quotes are required for stage/log paths with spaces. No shell evaluation.
    $Process = Start-Process -FilePath $GodotConsole -ArgumentList @('--headless','--path',('"'+$StageRoot+'"'),'--log-file',('"'+$Log+'"'),'--export-debug','Android',('"'+$Apk+'"')) -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -WindowStyle Hidden -PassThru
    if (-not $Process.WaitForExit(600000)) { $Process.Kill(); throw "Export timed out: $Name" }
    if ($Process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $Apk -PathType Leaf)) { throw "Native export failed: $Name exit=$($Process.ExitCode)" }
    return @{native_exit=$Process.ExitCode; apk=$Apk; apk_sha256=(Get-CodeExportHash $Apk); engine_sha256=(Get-CodeExportHash $GodotConsole); log=$Log; stdout=$Stdout; stderr=$Stderr}
}

function Invoke-TwoPassAndroidCodeExport {
    param(
        [Parameter(Mandatory=$true)][string]$StageRoot,
        [Parameter(Mandatory=$true)][string]$GodotConsole,
        [Parameter(Mandatory=$true)][string]$Python,
        [Parameter(Mandatory=$true)][string]$OutputApk,
        [Parameter(Mandatory=$true)][string]$EvidenceRoot,
        [Parameter(Mandatory=$true)][string]$SourceCommit,
        [Parameter(Mandatory=$true)][string]$TemplateApk,
        [Parameter(Mandatory=$true)][string]$ExpectedTemplateSha256,
        [Parameter(Mandatory=$true)][string]$BaselineApk,
        [Parameter(Mandatory=$true)][string]$ApkSigner,
        [Parameter(Mandatory=$true)][scriptblock]$RegenerateStageCatalogue,
        [Parameter(Mandatory=$true)][scriptblock]$VerifyProductionBuild
    )
    $StageRoot = (Resolve-Path -LiteralPath $StageRoot).Path
    $EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
    if ($EvidenceRoot.Equals($StageRoot, [StringComparison]::OrdinalIgnoreCase) -or $EvidenceRoot.StartsWith($StageRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must stay outside the frozen stage.' }
    New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
    if ((Get-CodeExportHash $TemplateApk) -cne $ExpectedTemplateSha256) { throw 'Approved template changed.' }
    # Called AFTER the existing successful stage import and version/build-info
    # setup. Callback must actually capture namespace/current context in this
    # stage and run the existing strict producer/catalogue generator. It returns
    # bound artifacts, not a boolean PASS. Never rebind old metadata by editing it.
    $Inputs = & $RegenerateStageCatalogue $StageRoot $EvidenceRoot
    foreach ($Name in @('SourceCatalogue','SourcePlan','Producer','Namespace','EntryId')) {
        if (-not $Inputs.ContainsKey($Name)) { throw "Missing stage generation result: $Name" }
    }
    $NamespaceValue = Get-Content -LiteralPath $Inputs.Namespace -Raw | ConvertFrom-Json
    if ($NamespaceValue.engine.binary_sha256 -cne (Get-CodeExportHash $GodotConsole)) { throw 'Stage namespace belongs to another executing editor image.' }
    if ($NamespaceValue.project_godot_sha256 -cne (Get-CodeExportHash (Join-Path $StageRoot 'project.godot')) -or $NamespaceValue.global_script_class_cache_sha256 -cne (Get-CodeExportHash (Join-Path $StageRoot '.godot/global_script_class_cache.cfg'))) { throw 'Stage namespace context is stale; actual stage capture is required.' }
    $Fixed = @{}
    $SealTool = Join-Path $PSScriptRoot 'build_android_seal.py'
    $VerifyTool = Join-Path $PSScriptRoot 'verify_final_export.py'
    $FrozenCollector = Join-Path (Split-Path $PSScriptRoot -Parent) 'export_identity_tool/collector.py'
    foreach ($Path in @((Join-Path $StageRoot 'project.godot'),(Join-Path $StageRoot '.godot/global_script_class_cache.cfg'),(Join-Path $StageRoot 'export_presets.cfg'),(Join-Path $StageRoot 'assets/generated/build_info.json'),$Inputs.SourceCatalogue,$Inputs.SourcePlan,$Inputs.Producer,$Inputs.Namespace,$GodotConsole,$TemplateApk,$SealTool,$VerifyTool,$FrozenCollector,(Join-Path $PSScriptRoot 'android_two_pass_export_hook.ps1'))) {
        $Fixed[$Path] = Get-CodeExportHash $Path
    }
    $Metadata = Join-Path $StageRoot 'scripts/features/generated/internal_code_android_export_data.gd'
    if (-not (Test-Path -LiteralPath $Metadata -PathType Leaf) -or [IO.File]::ReadAllText($Metadata) -notmatch '(?m)^const AVAILABLE := false\s*$') { throw 'First export requires the tracked unavailable placeholder, with no class_name.' }
    $FirstApk = Join-Path $EvidenceRoot 'first-unavailable-export.apk'
    if (Test-Path -LiteralPath $FirstApk) { throw 'First export path already exists.' }
    $First = Invoke-CodeOfficialExport $GodotConsole $StageRoot $FirstApk $EvidenceRoot 'first'
    $FirstSigner = Assert-CodeExportSigner $FirstApk $BaselineApk $ApkSigner
    Assert-CodeExportFrozen $Fixed
    $SealJson = Join-Path $EvidenceRoot 'android-export-seal.json'
    $SealGd = Join-Path $EvidenceRoot 'internal_code_android_export_data.gd'
    & $Python -B $SealTool --source-catalogue $Inputs.SourceCatalogue --expected-source-catalogue-sha256 $Fixed[$Inputs.SourceCatalogue] --source-plan $Inputs.SourcePlan --expected-source-plan-sha256 $Fixed[$Inputs.SourcePlan] --producer $Inputs.Producer --expected-producer-sha256 $Fixed[$Inputs.Producer] --namespace $Inputs.Namespace --expected-namespace-sha256 $Fixed[$Inputs.Namespace] --source-root $StageRoot --apk $FirstApk --expected-apk-sha256 $First.apk_sha256 --template $TemplateApk --expected-template-sha256 $ExpectedTemplateSha256 --source-commit $SourceCommit --entry-id $Inputs.EntryId --output-gd $SealGd --output-json $SealJson
    if ($LASTEXITCODE -ne 0) { throw 'Strict source/export seal generation failed.' }
    $SealGdHash = Get-CodeExportHash $SealGd
    Copy-Item -LiteralPath $SealGd -Destination $Metadata
    # No version mutation, build-info regeneration, timestamp change, manual
    # class-cache edit or source regeneration is permitted between these passes.
    Assert-CodeExportFrozen $Fixed
    if (Test-Path -LiteralPath $OutputApk) { throw 'Final APK path already exists.' }
    $Final = Invoke-CodeOfficialExport $GodotConsole $StageRoot $OutputApk $EvidenceRoot 'final'
    Assert-CodeExportFrozen $Fixed
    if ((Get-CodeExportHash $Metadata) -cne $SealGdHash) { throw 'Generated metadata source changed during export.' }
    $FinalSigner = Assert-CodeExportSigner $OutputApk $BaselineApk $ApkSigner
    $Receipt = Join-Path $EvidenceRoot 'final-export-identity-receipt.json'
    & $Python -B $VerifyTool --seal-json $SealJson --expected-seal-json-sha256 (Get-CodeExportHash $SealJson) --seal-gd $Metadata --expected-seal-gd-sha256 $SealGdHash --source-plan $Inputs.SourcePlan --expected-source-plan-sha256 $Fixed[$Inputs.SourcePlan] --source-root $StageRoot --apk $OutputApk --expected-apk-sha256 $Final.apk_sha256 --template $TemplateApk --expected-template-sha256 $ExpectedTemplateSha256 --source-commit $SourceCommit --output $Receipt
    if ($LASTEXITCODE -ne 0) { throw 'Final export identity changed or is incomplete.' }
    # Existing verify_android_build.ps1 remains the package/version/splash/runtime
    # resource acceptance owner. Callback must throw on any failure.
    & $VerifyProductionBuild $OutputApk $SourceCommit
    @{schema_version=1; source_commit=$SourceCommit; fixed_inputs=$Fixed; first_export=$First; final_export=$Final; first_signer=$FirstSigner; final_signer=$FinalSigner; generated_metadata_sha256=$SealGdHash; seal_json_sha256=(Get-CodeExportHash $SealJson); exact_export_receipt_sha256=(Get-CodeExportHash $Receipt); runtime_native_image_sha='MISSING'; native_token_device_acceptance='NOT_RUN'} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'two-pass-build-receipt.json') -Encoding UTF8
    return $Final
}
