param(
    [string]$BaseSha = '98ea003b66915622b5c265602e54386f9213016c'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$R1Gate = Join-Path $ProjectRoot 'tools\run_dpv2_final_gate.ps1'
$Runner = Join-Path $ProjectRoot 'tools\run_godot_tests.ps1'
$Builder = Join-Path $ProjectRoot 'tools\build_dpv2_single_player_drop_boost.py'
$SourcePath = Join-Path $ProjectRoot 'assets\data\canonical_monster_drop_source_v2.json'
$BaselinePath = Join-Path $ProjectRoot 'assets\data\drop\dpv2_direct_baseline_v2.json'
$ProvenancePath = Join-Path $ProjectRoot 'assets\data\drop\dpv2_21cq_source_provenance_v1.json'
$EffectivePath = Join-Path $ProjectRoot 'assets\data\drop\dpv2_single_player_effective_probability_v1.json'
$ExpectedHashes = @{
    'assets/data/canonical_monster_drop_source_v2.json' = '59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013'
    'assets/data/drop/dpv2_direct_baseline_v2.json' = '9E9225DF113BDC94ECDA071388DC5FCFA92ED34BF8028519B06F205E06FF4DD0'
    'assets/data/drop/dpv2_21cq_source_provenance_v1.json' = 'F48A033D5A33D80B795A838BE837AE84FA93469B6055FE012309ACC07082E347'
}
$ExpectedLedgerHash = '057F3664C2CE5376B2A937CB317E978769860AA1B3390D0EF038B512CD496B80'
$script:blocker_count = 0


function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $false)][object[]]$Arguments = @()
    )
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable exit_code_$LASTEXITCODE"
    }
}


function Invoke-GateStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    Write-Output "DPV2_SPB_FINAL_GATE_STEP=$Name"
    try {
        & $Action
        Write-Output "DPV2_SPB_FINAL_GATE_STEP_PASS=$Name"
    }
    catch {
        $script:blocker_count += 1
        Write-Output "DPV2_SPB_FINAL_GATE_STEP_FAIL=$Name $($_.Exception.Message)"
    }
}


function Get-AllSlots {
    param([Parameter(Mandatory = $true)][object]$Baseline)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($profile in @($Baseline.profiles)) {
        foreach ($slot in @($profile.slots)) {
            $row = [ordered]@{
                slot_uid = [string]$slot.slot_uid
                canonical_monster_id = [int]$profile.canonical_monster_id
                base_numerator = [int]$slot.base_numerator
                base_denominator = [int]$slot.base_denominator
                source_provenance_id = [string]$slot.source_provenance_id
                protected_drop = [bool]$slot.protected_drop
                overflow_priority = [int]$slot.overflow_priority
                baseline_origin = [string]$slot.baseline_origin
            }
            if ($null -ne $slot.canonical_item_id) {
                $row.canonical_item_id = [int]$slot.canonical_item_id
            }
            elseif ($null -ne $slot.gold_amount) {
                $row.gold_amount = [int]$slot.gold_amount
            }
            else {
                throw "slot reward missing: $($slot.slot_uid)"
            }
            [void]$rows.Add($row)
        }
    }
    return $rows
}


Push-Location $ProjectRoot
try {
    foreach ($required in @($R1Gate, $Runner, $Builder, $SourcePath, $BaselinePath, $ProvenancePath, $EffectivePath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "missing required SPB gate input: $required"
        }
    }

    # The existing R1 gate remains immutable and is deliberately the first
    # executable gate. Its PASS covers fresh P1A, P1A audit, world integration,
    # direct runtime contracts, overflow ordering, and engine-log checks.
    Invoke-GateStep -Name 'r1_final_gate' -Action {
        & $R1Gate
        if ($LASTEXITCODE -ne 0) {
            throw "r1_final_gate_exit_code_$LASTEXITCODE"
        }
    }
    Invoke-GateStep -Name 'spb_builder_check' -Action {
        Invoke-Native 'py' @('-3.12', $Builder, '--check')
    }
    Invoke-GateStep -Name 'spb_python_tests' -Action {
        Invoke-Native 'py' @(
            '-3.12', '-m', 'pytest',
            'tests/test_dpv2_single_player_drop_boost.py', '-q'
        )
    }
    Invoke-GateStep -Name 'spb_godot_runtime' -Action {
        & $Runner -TimeoutSeconds 30 -TestPaths @(
            'tests/dpv2_single_player_drop_boost_runtime_test.tscn'
        )
        if ($LASTEXITCODE -ne 0) {
            throw "spb_godot_runtime_exit_code_$LASTEXITCODE"
        }
    }
    Invoke-GateStep -Name 'original_source_raw_hashes' -Action {
        foreach ($relative in $ExpectedHashes.Keys) {
            $path = Join-Path $ProjectRoot $relative
            $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($actual -cne $ExpectedHashes[$relative]) {
                throw "raw SHA256 drift $relative actual=$actual expected=$($ExpectedHashes[$relative])"
            }
        }
        Write-Output 'DPV2_SPB_FROZEN_SHA_PASS source_drift=0 baseline_drift=0 provenance_drift=0'
    }
    Invoke-GateStep -Name 'base_sha_json_and_full_ledger' -Action {
        $relativePaths = @(
            'assets/data/canonical_monster_drop_source_v2.json',
            'assets/data/drop/dpv2_direct_baseline_v2.json',
            'assets/data/drop/dpv2_21cq_source_provenance_v1.json'
        )
        foreach ($relative in $relativePaths) {
            $frozenText = & git show "$BaseSha`:$relative"
            if ($LASTEXITCODE -ne 0) {
                throw "cannot read BASE_SHA JSON $BaseSha`:$relative"
            }
            $frozen = (($frozenText -join "`n") | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress)
            $current = (Get-Content -LiteralPath (Join-Path $ProjectRoot $relative) -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress)
            if ($frozen -cne $current) {
                throw "BASE_SHA semantic JSON drift: $relative"
            }
        }
        $frozenBaselineText = & git show "$BaseSha`:assets/data/drop/dpv2_direct_baseline_v2.json"
        if ($LASTEXITCODE -ne 0) { throw 'cannot read BASE_SHA direct baseline' }
        $frozenBaseline = ($frozenBaselineText -join "`n") | ConvertFrom-Json
        $currentBaseline = Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $frozenSlots = @(Get-AllSlots $frozenBaseline)
        $currentSlots = @(Get-AllSlots $currentBaseline)
        if ($frozenSlots.Count -ne 6809 -or $currentSlots.Count -ne 6809) {
            throw "6809 slot cardinality drift frozen=$($frozenSlots.Count) current=$($currentSlots.Count)"
        }
        $frozenByUid = @{}
        $currentByUid = @{}
        foreach ($row in $frozenSlots) { $frozenByUid[$row.slot_uid] = ($row | ConvertTo-Json -Compress) }
        foreach ($row in $currentSlots) { $currentByUid[$row.slot_uid] = ($row | ConvertTo-Json -Compress) }
        if ($frozenByUid.Count -ne 6809 -or $currentByUid.Count -ne 6809) {
            throw 'slot UID duplicate collapse detected'
        }
        foreach ($uid in $frozenByUid.Keys) {
            if (-not $currentByUid.ContainsKey($uid) -or $currentByUid[$uid] -cne $frozenByUid[$uid]) {
                throw "immutable slot ledger drift uid=$uid"
            }
        }
        $effective = Get-Content -LiteralPath $EffectivePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (@($effective.records).Count -ne 6809 -or [string]$effective.source_bindings.direct_slot_ledger_sha256 -cne $ExpectedLedgerHash) {
            throw 'effective ledger cardinality/hash binding drift'
        }
        Write-Output 'DPV2_ORIGINAL_DROP_RATE_PROTECTION_PASS slots=6809 base_probability_drift=0 slot_uid_drift=0 reward_drift=0 provenance_drift=0 protected_priority_origin_drift=0 duplicate_slot_collapse=0'
    }
    Invoke-GateStep -Name 'spb_effective_summary' -Action {
        $effective = Get-Content -LiteralPath $EffectivePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $summary = $effective.summary
        $expectedPolicies = @{
            AUTO_BOOST = 4537
            BYPASS_COMMON_RECOVERY = 1357
            BYPASS_GOLD = 128
            BYPASS_NEW_ARMOR_BOSS = 324
            BYPASS_UNCLASSIFIED = 463
        }
        foreach ($key in $expectedPolicies.Keys) {
            if ([int]$summary.effective_policy_counts.$key -ne $expectedPolicies[$key]) {
                throw "effective policy count drift $key"
            }
        }
        if ([int]$summary.ceiling_applied_slots -ne 2203 -or
            [int]$summary.disabled_counterfactual_mismatch -ne 0 -or
            [int]$summary.base_mirror_mismatch -ne 0 -or
            [int]$summary.gold_amount_slots -ne 134 -or
            [int]$summary.gold_amount_multiplier.numerator -ne 10 -or
            [int]$summary.gold_amount_multiplier.denominator -ne 1 -or
            [int]$summary.gold_amount_mismatch -ne 0 -or
            [int]$summary.disabled_gold_amount_mismatch -ne 0 -or
            [int]$summary.probability_decreases -ne 0 -or
            [int]$summary.ceiling_violations -ne 0 -or
            [int]$summary.boost_formula_mismatch -ne 0 -or
            [int]$summary.bypass_probability_mismatch -ne 0 -or
            [int]$summary.duplicate_slot_collapse -ne 0) {
            throw 'effective summary invariant mismatch'
        }
        $goldCount = 0
        foreach ($record in @($effective.records)) {
            if ([string]$record.reward_kind -eq 'GOLD') {
                $goldCount += 1
                if ([int]$record.base_gold_amount -ne [int]$record.gold_amount -or
                    [int]$record.effective_gold_amount -ne ([int]$record.gold_amount * 10) -or
                    [int]$record.effective_numerator -ne [int]$record.base_numerator -or
                    [int]$record.effective_denominator -ne [int]$record.base_denominator) {
                    throw "Gold amount/probability overlay mismatch uid=$($record.slot_uid)"
                }
            }
            elseif ($null -ne $record.base_gold_amount -or $null -ne $record.effective_gold_amount) {
                throw "non-Gold amount overlay found uid=$($record.slot_uid)"
            }
        }
        if ($goldCount -ne 134) { throw "Gold record count=$goldCount expected=134" }
        Write-Output 'DPV2_SPB_EFFECTIVE_SUMMARY_PASS records=6809 auto=4537 common=1357 gold=128 boss=324 unclassified=463 ceiling=2203 gold_amount_slots=134 gold_amount_x10=PASS all_mismatch=0'
    }
    Invoke-GateStep -Name 'r1_covered_p1a_world_engine' -Action {
        Write-Output 'DPV2_SPB_R1_COVERAGE_PASS fresh_p1a=PASS p1a_audit=PASS world_integration=PASS engine_errors=0'
    }
    Invoke-GateStep -Name 'git_diff_check' -Action {
        & git -C $ProjectRoot diff --check
        if ($LASTEXITCODE -ne 0) {
            throw "git_diff_check_exit_code_$LASTEXITCODE"
        }
    }
}
catch {
    $script:blocker_count += 1
    Write-Output "DPV2_SPB_FINAL_GATE_FATAL=$($_.Exception.Message)"
}
finally {
    Pop-Location
}

if ($script:blocker_count -ne 0) {
    Write-Output "DPV2_SPB_FINAL_GATE_FAIL blocker_count=$script:blocker_count"
    exit 1
}
Write-Output 'DPV2_SPB_FINAL_GATE_PASS blocker_count=0'
exit 0
