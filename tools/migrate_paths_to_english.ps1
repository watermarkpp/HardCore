param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [string]$ManifestPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ".git"))) {
    throw "Not a Git worktree: $ProjectRoot"
}

$NameMap = [ordered]@{
    "地面" = "ground"
    "装饰物1" = "decorations_1"
    "新增石板地面" = "new_stone_ground"
    "地图出入口" = "map_entrances"
    "地毯" = "carpets"
    "地面涂鸦" = "ground_graffiti"
    "地面血渍" = "ground_bloodstains"
    "城墙" = "city_walls"
    "小尺寸装饰物没有碰撞体积只是贴图" = "small_decorations_visual_only"
    "尸体没有碰撞体积只是贴图" = "corpses_visual_only"
    "房子帐篷" = "houses_and_tents"
    "摊贩摊位" = "vendor_stalls"
    "树木" = "trees"
    "王座" = "thrones"
    "立柱" = "pillars"
    "路灯" = "street_lamps"
    "路障" = "barricades"
    "MSE固定64" = "mse_fixed_64"
    "圣坛" = "shrines"
    "寺庙" = "temples"
    "沙漠洞穴" = "desert_caves"
    "深林" = "deep_forest"
    "A套" = "set_a"
    "B套" = "set_b"
    "MSE深林44" = "mse_deep_forest_44"
    "倒木" = "fallen_logs"
    "树墩" = "tree_stumps"
    "独立树木" = "standalone_trees"
    "草地覆盖" = "grass_cover"
    "基础草地组_01" = "basic_grass_set_01"
    "基础草地组_02" = "basic_grass_set_02"
    "深草地组" = "deep_grass_set"
    "泥地组_01" = "mud_ground_set_01"
    "泥地组_02" = "mud_ground_set_02"
    "土路组_01" = "dirt_road_set_01"
    "土路组_02" = "dirt_road_set_02"
    "石板路组_01" = "stone_road_set_01"
    "石板路组_02" = "stone_road_set_02"
    "水面组" = "water_surface_set"
    "水岸过渡组_01" = "shoreline_transition_set_01"
    "水岸过渡组_02" = "shoreline_transition_set_02"
    "石地组" = "stone_ground_set"
    "裂石地组" = "cracked_stone_ground_set"
    "矿区岩地组" = "mine_rock_ground_set"
    "地面裂缝污渍杂草覆盖层_01" = "ground_cracks_stains_weeds_overlay_01"
    "地面覆盖层_02" = "ground_overlay_02"
    "普通树组_01" = "normal_tree_set_01"
    "普通树组_02" = "normal_tree_set_02"
    "枯树组" = "dead_tree_set"
    "小石头组" = "small_rock_set"
    "小石头组补充" = "small_rock_supplement"
    "中型岩石组" = "medium_rock_set"
    "大型岩石组" = "large_rock_set"
    "栅栏组_01" = "fence_set_01"
    "栅栏组_02" = "fence_set_02"
    "野外小装饰组" = "wilderness_small_decor_set"
    "野外边界组" = "wilderness_boundary_set"
    "野外入口组" = "wilderness_entrance_set"
    "2D美术与技术标准_v1.md" = "2D_Art_and_Technical_Standards_v1.md"
    "BICH-BOSS-1_骷髅精灵与尸王校准报告.md" = "BICH-BOSS-1_Skeleton_Spirit_and_Corpse_King_Calibration_Report.md"
    "BICH-CITY-1_哥特比奇主城样板报告.md" = "BICH-CITY-1_Gothic_Bich_City_Prototype_Report.md"
    "BICH-CLOSE-1_比奇垂直切片缺口审计.md" = "BICH-CLOSE-1_Bich_Vertical_Slice_Gap_Audit.md"
    "BICH-COMMUNITY-DATA-1_社区数据库搜索与采用报告.md" = "BICH-COMMUNITY-DATA-1_Community_Database_Research_and_Adoption_Report.md"
    "BICH-COMMUNITY-DATA-2_选择性导入报告.md" = "BICH-COMMUNITY-DATA-2_Selective_Import_Report.md"
    "BICH-COMMUNITY-DATA-3_经典掉落运行接入报告.md" = "BICH-COMMUNITY-DATA-3_Classic_Drop_Runtime_Integration_Report.md"
    "BICH-CONTENT-CLOSE_原MAP阻挡与内容收口报告.md" = "BICH-CONTENT-CLOSE_Original_MAP_Collision_and_Content_Closure_Report.md"
    "BICH-DATA-1_数据来源与覆盖审计.md" = "BICH-DATA-1_Data_Source_and_Coverage_Audit.md"
    "BICH-GAP-CLOSE-1_缺口清理与阻塞清单.md" = "BICH-GAP-CLOSE-1_Gap_Cleanup_and_Blocker_List.md"
    "BICH-HOTFIX-1_移动复活与返回键修复报告.md" = "BICH-HOTFIX-1_Movement_Respawn_and_Back_Button_Report.md"
    "BICH-MANUAL_人工地图协作规则.md" = "BICH-MANUAL_Manual_Map_Collaboration_Rules.md"
    "BICH-MAP-1_比奇区域地图骨架.md" = "BICH-MAP-1_Bich_Region_Map_Skeleton.md"
    "BICH-MAP-2_NPC与怪物生态.md" = "BICH-MAP-2_NPC_and_Monster_Ecology.md"
    "BICH-MAP-2_兽人古墓D001-D003验收报告.md" = "BICH-MAP-2_Orc_Tomb_D001-D003_Acceptance_Report.md"
    "BICH-MAP-3_天然洞穴D011-D012验收报告.md" = "BICH-MAP-3_Natural_Cave_D011-D012_Acceptance_Report.md"
    "BICH-MAP-3_碰撞与试玩接入.md" = "BICH-MAP-3_Collision_and_Playtest_Integration.md"
    "BICH-MAP-SIZE-1_原始尺寸与统一坐标验收报告.md" = "BICH-MAP-SIZE-1_Original_Size_and_Unified_Coordinates_Report.md"
    "BICH-MAP-SIZE-2_矿区与尸王殿原尺寸验收报告.md" = "BICH-MAP-SIZE-2_Mine_and_Corpse_King_Hall_Original_Size_Report.md"
    "BICH-MILESTONE-1_比奇完整闭环阶段验收报告.md" = "BICH-MILESTONE-1_Bich_Complete_Loop_Acceptance_Report.md"
    "BICH-MONSTER-ANIMATION-1_比奇怪物客户端动作补全报告.md" = "BICH-MONSTER-ANIMATION-1_Bich_Monster_Client_Animation_Report.md"
    "BICH-WARRIOR-1_比奇战士基础战斗与技能数据化报告.md" = "BICH-WARRIOR-1_Bich_Warrior_Combat_and_Skill_Data_Report.md"
    "BRAND-INTRO-1_游戏图标与开场动画报告.md" = "BRAND-INTRO-1_Game_Icon_and_Intro_Animation_Report.md"
    "Codex崩溃自检记录.md" = "Codex_Crash_Self_Check_Record.md"
    "COMPLETE-ITEM-SYSTEM-1_完整物品与地面掉落外观报告.md" = "COMPLETE-ITEM-SYSTEM-1_Item_and_Ground_Drop_Visual_Report.md"
    "COMPLETE-LOCAL-MIR-SCAN-1_本地多端全量拆解验收报告.md" = "COMPLETE-LOCAL-MIR-SCAN-1_Local_Multi_Client_Extraction_Report.md"
    "M1_2D美术技术标准_验收报告.md" = "M1_2D_Art_Technical_Standards_Acceptance_Report.md"
    "M2_战士人物美术简报.md" = "M2_Warrior_Character_Art_Brief.md"
    "M6-1_Android验收报告.md" = "M6-1_Android_Acceptance_Report.md"
    "M6-2_荣耀90真机验收报告.md" = "M6-2_Honor_90_Device_Acceptance_Report.md"
    "M8-1_比奇矿区资源与地图验收报告.md" = "M8-1_Bich_Mine_Assets_and_Map_Acceptance_Report.md"
    "M8-2_沃玛寺庙资源与地图验收报告.md" = "M8-2_Wooma_Temple_Assets_and_Map_Acceptance_Report.md"
    "M8-3_沃玛森林与自然洞穴验收报告.md" = "M8-3_Wooma_Forest_and_Natural_Cave_Acceptance_Report.md"
    "M8-4_毒蛇山谷与山谷矿区验收报告.md" = "M8-4_Viper_Valley_and_Valley_Mine_Acceptance_Report.md"
    "MAP-EDITOR-ROADMAP_通用地图生产线.md" = "MAP-EDITOR-ROADMAP_Generic_Map_Production_Pipeline.md"
    "MIR2-DATA-1_服务端数据校准报告.md" = "MIR2-DATA-1_Server_Data_Calibration_Report.md"
    "MIR2-DATA-3_服务端导入差异报告.md" = "MIR2-DATA-3_Server_Import_Difference_Report.md"
    "MIR-SOURCE-PRIORITY-1_客户端与服务端主辅资料分级报告.md" = "MIR-SOURCE-PRIORITY-1_Client_and_Server_Source_Priority_Report.md"
    "MSE-R1-GATE_验收报告.md" = "MSE-R1-GATE_Acceptance_Report.md"
    "MSE-STAGE-0_核心底座验收报告.md" = "MSE-STAGE-0_Core_Foundation_Acceptance_Report.md"
    "MSE-STAGE-1_空白地面与虚拟Chunk验收报告.md" = "MSE-STAGE-1_Blank_Ground_and_Virtual_Chunk_Acceptance_Report.md"
    "MSE-STAGE-2_地面笔刷与ChunkBake验收报告.md" = "MSE-STAGE-2_Ground_Brush_and_Chunk_Bake_Acceptance_Report.md"
    "MSE-STAGE-3_校准Ghost与Footprint验收报告.md" = "MSE-STAGE-3_Ghost_and_Footprint_Calibration_Report.md"
    "MSE-STAGE-4_对象实例语义验收报告.md" = "MSE-STAGE-4_Object_Instance_Semantics_Acceptance_Report.md"
    "MSE-STAGE-5_地貌碰撞与Walkable预览验收报告.md" = "MSE-STAGE-5_Terrain_Collision_and_Walkable_Preview_Report.md"
    "MSE-STAGE-6_地图玩法语义验收报告.md" = "MSE-STAGE-6_Map_Gameplay_Semantics_Acceptance_Report.md"
    "MSE-STAGE-7_BuildRuntime与导出门禁验收报告.md" = "MSE-STAGE-7_Build_Runtime_and_Export_Gate_Report.md"
    "MSE-STAGE-8_运行时契约与MSE最终验收报告.md" = "MSE-STAGE-8_Runtime_Contract_and_Final_Acceptance_Report.md"
    "MSE-V3.4.5_施工决策与人机协作规范.md" = "MSE-V3.4.5_Implementation_Decisions_and_Collaboration_Standard.md"
    "MSE-V3.4.5-R1_逻辑Tile与素材Schema修订.md" = "MSE-V3.4.5-R1_Logical_Tile_and_Asset_Schema_Revision.md"
    "NPC-FACING-1_经典NPC交互转向施工报告.md" = "NPC-FACING-1_Classic_NPC_Interaction_Facing_Report.md"
    "PROJECT-OPTIMIZATION-1_项目瘦身与工具归档报告.md" = "PROJECT-OPTIMIZATION-1_Project_Slimming_and_Tool_Archive_Report.md"
    "SAVE-MENU-1_游戏菜单与安全回城报告.md" = "SAVE-MENU-1_Game_Menu_and_Safe_Return_Report.md"
    "SAVE-MULTI-1_多角色与启动选择系统报告.md" = "SAVE-MULTI-1_Multi_Character_and_Startup_Selection_Report.md"
    "UI-GOTHIC-PREVIEW-1_暗黑哥特界面审图样板.md" = "UI-GOTHIC-PREVIEW-1_Dark_Gothic_UI_Review_Prototype.md"
    "V1.5_A_B批次审核与正式Palette提升报告.md" = "V1.5_A_B_Batch_Review_and_Palette_Promotion_Report.md"
    "V1.5_素材本地处理报告.json" = "V1.5_Local_Asset_Processing_Report.json"
    "V1.5_素材本地处理验收报告.md" = "V1.5_Local_Asset_Processing_Acceptance_Report.md"
    "WARRIOR-SKILL-VISUAL-AUDIT-2_战士技能八方向动画审计报告.md" = "WARRIOR-SKILL-VISUAL-AUDIT-2_Warrior_Eight_Direction_Animation_Audit.md"
    "WORLD-SPATIAL-STABILITY-1_空间规则统一与Godot稳定性报告.md" = "WORLD-SPATIAL-STABILITY-1_Spatial_Rules_and_Godot_Stability_Report.md"
    "三职业技能战斗参数基线_v1.md" = "Three_Profession_Skill_Combat_Parameter_Baseline_v1.md"
    "五层架构规范与迁移表.md" = "Five_Layer_Architecture_Standard_and_Migration_Matrix.md"
    "单机版地图尺寸规划.md" = "Offline_Map_Size_Plan.md"
    "原始地图尺寸审计报告.md" = "Original_Map_Size_Audit_Report.md"
    "启动地图编辑器.cmd" = "Launch_Map_Editor.cmd"
    "客户端全量资源目录.md" = "Complete_Client_Resource_Catalog.md"
    "总规划_任务结构图.md" = "Total_Project_Plan_Task_Structure.md"
    "总规划_进度续表.md" = "Total_Project_Progress_Continuation.md"
    "施工记录.md" = "Construction_Log.md"
    "服务端数据参考索引.md" = "Server_Data_Reference_Index.md"
    "测试执行规范.md" = "Test_Execution_Standard.md"
    "装备自定义指南.md" = "Equipment_Customization_Guide.md"
    "项目总目录.md" = "Project_Master_Index.md"
    "比奇任务.txt" = "Bich_Quest.txt"
    "骷髅精灵.txt" = "Skeleton_Spirit.txt"
}

function Convert-RelativePath([string]$RelativePath) {
    $parts = $RelativePath -split "[\\/]"
    $converted = foreach ($part in $parts) {
        if ($NameMap.Contains($part)) { $NameMap[$part] } else { $part }
    }
    return ($converted -join "/")
}

function Is-Excluded([string]$FullName) {
    $relative = $FullName.Substring($ProjectRoot.Length).TrimStart([char[]]@('\', '/'))
    return $relative -match "^(\.git|\.godot|outputs|dev_art_sources|tools[\\/]godot-4\.7)([\\/]|$)"
}

Push-Location $ProjectRoot
try {
    $trackedBefore = @(git -c core.quotepath=false ls-files)
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed" }
    $pathMappings = @()
    foreach ($oldPath in $trackedBefore) {
        $newPath = Convert-RelativePath $oldPath
        if ($newPath -ne $oldPath) {
            $pathMappings += [pscustomobject]@{ old = $oldPath; new = $newPath }
        }
    }

    $entries = @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Force -ErrorAction Stop |
        Where-Object { -not (Is-Excluded $_.FullName) -and $_.Name -match "[\u4e00-\u9fff]" })
    $unknown = @($entries | Where-Object { -not $NameMap.Contains($_.Name) } | Select-Object -ExpandProperty Name -Unique)
    if ($unknown.Count -gt 0) {
        throw "Missing English mappings: $($unknown -join ', ')"
    }

    $existingDestinations = @()
    foreach ($entry in $entries) {
        $destination = Join-Path (Split-Path $entry.FullName -Parent) $NameMap[$entry.Name]
        if (Test-Path -LiteralPath $destination) {
            $existingDestinations += $destination
        }
    }
    if ($existingDestinations.Count -gt 0) {
        throw "Destination paths already exist: $($existingDestinations -join ', ')"
    }

    $dirtyBefore = @{}
    foreach ($record in @(git -c core.quotepath=false status --porcelain=v1 --untracked-files=all)) {
        if ($record.Length -ge 4) { $dirtyBefore[$record.Substring(3)] = $true }
    }

    $referenceMappings = @()
    $directoryEntries = @($entries | Where-Object { $_.PSIsContainer })
    foreach ($entry in $directoryEntries) {
        $oldRelative = $entry.FullName.Substring($ProjectRoot.Length + 1).Replace("\", "/")
        $referenceMappings += [pscustomobject]@{ old = $oldRelative; new = (Convert-RelativePath $oldRelative) }
    }
    $referenceMappings += $pathMappings
    foreach ($key in $NameMap.Keys) {
        if ([IO.Path]::GetExtension([string]$key)) {
            $referenceMappings += [pscustomobject]@{ old = [string]$key; new = [string]$NameMap[$key] }
        }
    }
    $referenceMappings = @($referenceMappings | Sort-Object { $_.old.Length } -Descending)

    $textExtensions = @(".gd", ".tscn", ".tres", ".godot", ".cfg", ".json", ".md", ".txt", ".ps1", ".py", ".cmd", ".csv", ".tsv", ".yaml", ".yml", ".ini", ".xml")
    $pendingReferenceChanges = @{}
    foreach ($oldTrackedPath in $trackedBefore) {
        $currentPath = Convert-RelativePath $oldTrackedPath
        $fullPath = Join-Path $ProjectRoot $oldTrackedPath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
        if ([IO.Path]::GetExtension($fullPath).ToLowerInvariant() -notin $textExtensions) { continue }
        $bytes = [IO.File]::ReadAllBytes($fullPath)
        if ($bytes -contains 0) { continue }
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        $updated = $text
        foreach ($mapping in $referenceMappings) {
            $updated = $updated.Replace($mapping.old, $mapping.new)
            $updated = $updated.Replace($mapping.old.Replace("/", "\"), $mapping.new.Replace("/", "\"))
        }
        if ($updated -ne $text) {
            if ($dirtyBefore.ContainsKey($oldTrackedPath)) {
                throw "Path-reference update overlaps a pre-existing dirty file: $oldTrackedPath"
            }
            $pendingReferenceChanges[$currentPath] = $updated
        }
    }

    foreach ($entry in @($entries | Sort-Object { $_.FullName.Length } -Descending)) {
        Rename-Item -LiteralPath $entry.FullName -NewName $NameMap[$entry.Name]
    }

    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    foreach ($relativePath in $pendingReferenceChanges.Keys) {
        [IO.File]::WriteAllText((Join-Path $ProjectRoot $relativePath), $pendingReferenceChanges[$relativePath], $utf8NoBom)
    }

    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $safeBranch = (git branch --show-current).Replace("/", "_")
        $ManifestPath = Join-Path $ProjectRoot "outputs/path_migration/$safeBranch.json"
    } elseif (-not [IO.Path]::IsPathRooted($ManifestPath)) {
        $ManifestPath = Join-Path $ProjectRoot $ManifestPath
    }
    New-Item -ItemType Directory -Path (Split-Path $ManifestPath -Parent) -Force | Out-Null
    $manifest = [ordered]@{
        project_root = $ProjectRoot
        branch = (git branch --show-current)
        path_mappings = $pathMappings
        reference_files = @($pendingReferenceChanges.Keys | Sort-Object)
    }
    [IO.File]::WriteAllText($ManifestPath, ($manifest | ConvertTo-Json -Depth 5), $utf8NoBom)

    $stagePaths = [Collections.Generic.List[string]]::new()
    foreach ($mapping in $pathMappings) {
        $stagePaths.Add($mapping.old)
        $stagePaths.Add($mapping.new)
    }
    foreach ($path in $pendingReferenceChanges.Keys) { $stagePaths.Add($path) }
    $pathspecFile = Join-Path (Split-Path $ManifestPath -Parent) "stage-paths.txt"
    [IO.File]::WriteAllText($pathspecFile, (($stagePaths | Sort-Object -Unique) -join "`n") + "`n", $utf8NoBom)
    git add -A --pathspec-from-file=$pathspecFile
    if ($LASTEXITCODE -ne 0) { throw "git add failed" }
    git diff --cached --check
    if ($LASTEXITCODE -ne 0) { throw "staged path migration failed validation" }
    Write-Output "PATH_MIGRATION_READY"
    Write-Output "ROOT=$ProjectRoot"
    Write-Output "RENAMED_TRACKED_PATHS=$($pathMappings.Count)"
    Write-Output "UPDATED_REFERENCE_FILES=$($pendingReferenceChanges.Count)"
    Write-Output "MANIFEST=$ManifestPath"
} finally {
    Pop-Location
}
