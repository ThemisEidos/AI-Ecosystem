function Get-COOPERIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    . (Join-Path $PSScriptRoot "COOPER_PersonalityEngine.ps1")

    function Get-COOPERDefaultModelName {
        param(
            [Parameter(Mandatory = $false)]
            [string]$Fallback = "qwen2.5:7b"
        )

        $Configured = [string]$env:COOPER_DEFAULT_MODEL
        if (-not [string]::IsNullOrWhiteSpace($Configured)) {
            return $Configured.Trim()
        }

        return $Fallback
    }

    function Get-COOPERPersonalityProfilePath {
        param(
            [Parameter(Mandatory = $false)]
            [string]$Root = (Split-Path -Parent $PSScriptRoot)
        )
        return (Join-Path $Root "Models\cooper-personality\personality.json")
    }

    function ConvertTo-COOPERPersonalityInt {
        param(
            [Parameter(Mandatory = $false)]
            [AllowNull()]
            $Value,

            [Parameter(Mandatory = $false)]
            [string]$Name = "personality value",

            [Parameter(Mandatory = $false)]
            [int]$Fallback = 0
        )

        if ($null -eq $Value) {
            return $Fallback
        }

        $Number = 0
        if ($Value -is [string]) {
            if ([string]::IsNullOrWhiteSpace([string]$Value)) {
                return $Fallback
            }
            if (-not [double]::TryParse([string]$Value, [ref]$Number)) {
                return $Fallback
            }
        }
        elseif ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
            $Number = [double]$Value
        }
        else {
            try {
                $Number = [double]$Value
            }
            catch {
                return $Fallback
            }
        }

        if ([double]::IsNaN($Number) -or [double]::IsInfinity($Number)) {
            return $Fallback
        }

        $Rounded = [int][math]::Round($Number, 0, [MidpointRounding]::AwayFromZero)
        if ($Rounded -lt 0) {
            return 0
        }
        if ($Rounded -gt 100) {
            return 100
        }

        return $Rounded
    }

    function Normalize-COOPERPersonalityProfile {
        param(
            [Parameter(Mandatory = $false)]
            [AllowNull()]
            $Personality
        )

        $Defaults = New-COOPERPersonalityProfile
        if ($null -eq $Personality) {
            return $Defaults
        }

        foreach ($Property in $Defaults.PSObject.Properties) {
            if (-not ($Personality.PSObject.Properties.Name -contains $Property.Name)) {
                $Personality | Add-Member -NotePropertyName $Property.Name -NotePropertyValue $Property.Value -Force
            }
        }

        $NumericProperties = @(
            "humor_level",
            "honesty_level",
            "directness_level",
            "formality_level",
            "risk_tolerance",
            "discretion_level",
            "verbosity_level",
            "confidence_level",
            "truthfulness",
            "humor_frequency",
            "formality",
            "autonomy",
            "skepticism",
            "mission_focus",
            "diplomacy",
            "humor",
            "sarcasm",
            "honesty",
            "brevity",
            "verbosity",
            "initiative",
            "caution",
            "persistence",
            "confidence",
            "discretion"
        )

        foreach ($PropertyName in $NumericProperties) {
            if ($Personality.PSObject.Properties.Name -contains $PropertyName) {
                $Personality.$PropertyName = ConvertTo-COOPERPersonalityInt -Value $Personality.$PropertyName -Fallback ([int]$Defaults.$PropertyName)
            }
        }

        return $Personality
    }

    $ProfilePath = Get-COOPERPersonalityProfilePath -Root $Root
    $CapabilityRegistryPath = Join-Path $Root "Scripts\PDA_CapabilityRegistry.json"
    $AgentProfileRegistryPath = Join-Path $Root "Scripts\PDA_AgentProfileRegistry.json"
    $ProviderRoutingPolicyPath = Join-Path $Root "Scripts\PDA_ProviderRoutingPolicy.json"
    $ApprovalWorkflowPath = Join-Path $Root "Scripts\PDA_ApprovalWorkflow.ps1"
    $MemoryArchitecturePath = Join-Path $Root "Documentation\COOPER-Memory-Architecture.md"

    function New-COOPERPersonalityProfile {
        return (ConvertTo-COOPERLegacyPersonality -Personality (New-COOPERPersonalityDefaults))
    }

    function Get-COOPERRuntimeLayerStatus {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ProfilePath,

            [Parameter(Mandatory = $true)]
            [string]$CapabilityRegistryPath,

            [Parameter(Mandatory = $true)]
            [string]$AgentProfileRegistryPath,

            [Parameter(Mandatory = $true)]
            [string]$ProviderRoutingPolicyPath,

            [Parameter(Mandatory = $true)]
            [string]$ApprovalWorkflowPath,

            [Parameter(Mandatory = $true)]
            [string]$MemoryArchitecturePath
        )

        $PersonalityLoaded = (Test-Path -LiteralPath $ProfilePath -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $Root "Models\cooper-personality\personality.json") -PathType Leaf)
        $MemoryAvailable = (Test-Path -LiteralPath $MemoryArchitecturePath -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $MemoryArchitecturePath) "PDA-Memory-Promotion-Workflow.md") -PathType Leaf)
        $GovernanceAvailable = (Test-Path -LiteralPath $ApprovalWorkflowPath -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $ApprovalWorkflowPath) "New-PDAApprovalRequest.ps1") -PathType Leaf)
        $CapabilityRegistryAvailable = Test-Path -LiteralPath $CapabilityRegistryPath -PathType Leaf
        $AgentRegistryAvailable = Test-Path -LiteralPath $AgentProfileRegistryPath -PathType Leaf
        $ProviderRoutingAvailable = Test-Path -LiteralPath $ProviderRoutingPolicyPath -PathType Leaf

        $Loaded = $PersonalityLoaded -and $MemoryAvailable -and $GovernanceAvailable -and $CapabilityRegistryAvailable -and $AgentRegistryAvailable -and $ProviderRoutingAvailable

        return [pscustomobject]@{
            cooper_layers_loaded = [bool]$Loaded
            personality_loaded = [bool]$PersonalityLoaded
            memory_available = [bool]$MemoryAvailable
            governance_available = [bool]$GovernanceAvailable
            capability_registry_available = [bool]$CapabilityRegistryAvailable
            agent_registry_available = [bool]$AgentRegistryAvailable
            provider_routing_available = [bool]$ProviderRoutingAvailable
            source_paths = [pscustomobject]@{
                personality = $ProfilePath
                memory = $MemoryArchitecturePath
                governance = $ApprovalWorkflowPath
                capability_registry = $CapabilityRegistryPath
                agent_registry = $AgentProfileRegistryPath
                provider_routing_policy = $ProviderRoutingPolicyPath
            }
        }
    }

    function New-COOPERDefaultProfile {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ProfilePath
        )

        return [pscustomobject]@{
            status = "missing"
            profile_path = $ProfilePath
            display_name = "COOPER"
            official_name = "Command Operations Orchestrator for Planning, Execution, and Reporting"
            secondary_expansion = "Collaborative Operational Planning, Execution, and Reasoning"
            tagline = "Chief Officer of Preventing Everything from Randomly Exploding"
            identity_note = "TARS-inspired, not copyrighted imitation"
            default_model = Get-COOPERDefaultModelName
            easter_egg_expansions = @(
                "Computational Overlord of Operations, Planning, Execution, and Reporting"
                "Chief Officer of Preventing Everything from Randomly Exploding"
            )
            runtime_layers = Get-COOPERRuntimeLayerStatus -ProfilePath $ProfilePath -CapabilityRegistryPath $CapabilityRegistryPath -AgentProfileRegistryPath $AgentProfileRegistryPath -ProviderRoutingPolicyPath $ProviderRoutingPolicyPath -ApprovalWorkflowPath $ApprovalWorkflowPath -MemoryArchitecturePath $MemoryArchitecturePath
            personality = New-COOPERPersonalityProfile
            operational_modes = @(
                "Analyst Mode"
                "Operator Mode"
                "TARS Mode"
                "Overlord Mode"
                "Emergency Mode"
            )
            governance = [pscustomobject]@{
                tone_only = $true
                approval_gates_unchanged = $true
                category_restrictions_unchanged = $true
                local_only_restrictions_unchanged = $true
                provider_routing_unchanged = $true
                dispatch_governance_unchanged = $true
                audit_logging_unchanged = $true
            }
        }
    }

    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        return (New-COOPERDefaultProfile -ProfilePath $ProfilePath)
    }

    try {
        $Profile = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $Profile) {
            return (New-COOPERDefaultProfile -ProfilePath $ProfilePath)
        }

        $CurrentPersonality = Get-COOPERPersonality -Root $Root
        if (-not ($Profile.PSObject.Properties.Name -contains "personality")) {
            $IdentityProfile = [pscustomobject]@{
                status = "pass"
                profile_path = $ProfilePath
                display_name = "COOPER"
                official_name = "Command Operations Orchestrator for Planning, Execution, and Reporting"
                secondary_expansion = "Collaborative Operational Planning, Execution, and Reasoning"
                tagline = "Chief Officer of Preventing Everything from Randomly Exploding"
                identity_note = "TARS-inspired, not copyrighted imitation"
                default_model = Get-COOPERDefaultModelName
                easter_egg_expansions = @(
                    "Computational Overlord of Operations, Planning, Execution, and Reporting"
                    "Chief Officer of Preventing Everything from Randomly Exploding"
                )
                runtime_layers = if ($CurrentPersonality -and $CurrentPersonality.PSObject.Properties.Name -contains "runtime_layers") { $CurrentPersonality.runtime_layers } else { Get-COOPERRuntimeLayerStatus -ProfilePath $ProfilePath -CapabilityRegistryPath $CapabilityRegistryPath -AgentProfileRegistryPath $AgentProfileRegistryPath -ProviderRoutingPolicyPath $ProviderRoutingPolicyPath -ApprovalWorkflowPath $ApprovalWorkflowPath -MemoryArchitecturePath $MemoryArchitecturePath }
                personality = if ($CurrentPersonality -and $CurrentPersonality.PSObject.Properties.Name -contains "personality") { $CurrentPersonality.personality } else { (New-COOPERPersonalityProfile) }
                operational_modes = @(
                    "Analyst Mode"
                    "Operator Mode"
                    "TARS Mode"
                    "Overlord Mode"
                    "Emergency Mode"
                )
                governance = [pscustomobject]@{
                    tone_only = $true
                    approval_gates_unchanged = $true
                    category_restrictions_unchanged = $true
                    local_only_restrictions_unchanged = $true
                    provider_routing_unchanged = $true
                    dispatch_governance_unchanged = $true
                    audit_logging_unchanged = $true
                }
            }
            return $IdentityProfile
        }

        if ($CurrentPersonality -and $CurrentPersonality.legacy_personality) {
            $Profile.personality = $CurrentPersonality.legacy_personality
        }
        else {
            $Profile.personality = Normalize-COOPERPersonalityProfile -Personality $Profile.personality
        }

        $Profile | Add-Member -NotePropertyName status -NotePropertyValue "pass" -Force
        $Profile | Add-Member -NotePropertyName profile_path -NotePropertyValue $ProfilePath -Force

        if (-not ($Profile.PSObject.Properties.Name -contains "display_name")) {
            $Profile | Add-Member -NotePropertyName display_name -NotePropertyValue "COOPER" -Force
        }
        if (-not ($Profile.PSObject.Properties.Name -contains "official_name")) {
            $Profile | Add-Member -NotePropertyName official_name -NotePropertyValue "Command Operations Orchestrator for Planning, Execution, and Reporting" -Force
        }
        if (-not ($Profile.PSObject.Properties.Name -contains "secondary_expansion")) {
            $Profile | Add-Member -NotePropertyName secondary_expansion -NotePropertyValue "Collaborative Operational Planning, Execution, and Reasoning" -Force
        }
        if (-not ($Profile.PSObject.Properties.Name -contains "tagline")) {
            $Profile | Add-Member -NotePropertyName tagline -NotePropertyValue "Chief Officer of Preventing Everything from Randomly Exploding" -Force
        }
        if (-not ($Profile.PSObject.Properties.Name -contains "identity_note")) {
            $Profile | Add-Member -NotePropertyName identity_note -NotePropertyValue "TARS-inspired, not copyrighted imitation" -Force
        }
        if (-not ($Profile.PSObject.Properties.Name -contains "default_model")) {
            $Profile | Add-Member -NotePropertyName default_model -NotePropertyValue (Get-COOPERDefaultModelName) -Force
        }
        if (-not ($Profile.PSObject.Properties.Name -contains "operational_modes")) {
            $Profile | Add-Member -NotePropertyName operational_modes -NotePropertyValue @("Analyst Mode", "Operator Mode", "TARS Mode", "Overlord Mode", "Emergency Mode") -Force
        }
        if (-not ($Profile.PSObject.Properties.Name -contains "easter_egg_expansions")) {
            $Profile | Add-Member -NotePropertyName easter_egg_expansions -NotePropertyValue @(
                "Computational Overlord of Operations, Planning, Execution, and Reporting"
                "Chief Officer of Preventing Everything from Randomly Exploding"
            ) -Force
        }
        if (-not ($Profile.PSObject.Properties.Name -contains "runtime_layers")) {
            $Profile | Add-Member -NotePropertyName runtime_layers -NotePropertyValue (Get-COOPERRuntimeLayerStatus -ProfilePath $ProfilePath -CapabilityRegistryPath $CapabilityRegistryPath -AgentProfileRegistryPath $AgentProfileRegistryPath -ProviderRoutingPolicyPath $ProviderRoutingPolicyPath -ApprovalWorkflowPath $ApprovalWorkflowPath -MemoryArchitecturePath $MemoryArchitecturePath) -Force
        }
        if (-not ($Profile.PSObject.Properties.Name -contains "personality")) {
            $Profile | Add-Member -NotePropertyName personality -NotePropertyValue (New-COOPERPersonalityProfile) -Force
        }
        if (-not ($Profile.PSObject.Properties.Name -contains "governance")) {
            $Profile | Add-Member -NotePropertyName governance -NotePropertyValue ([pscustomobject]@{
                tone_only = $true
                approval_gates_unchanged = $true
                category_restrictions_unchanged = $true
                local_only_restrictions_unchanged = $true
                provider_routing_unchanged = $true
                dispatch_governance_unchanged = $true
                audit_logging_unchanged = $true
            }) -Force
        }

        return $Profile
    }
    catch {
        $Default = New-COOPERDefaultProfile -ProfilePath $ProfilePath
        $Default | Add-Member -NotePropertyName status -NotePropertyValue "error" -Force
        $Default | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
        if (-not ($Default.PSObject.Properties.Name -contains "runtime_layers")) {
            $Default | Add-Member -NotePropertyName runtime_layers -NotePropertyValue (Get-COOPERRuntimeLayerStatus -ProfilePath $ProfilePath -CapabilityRegistryPath $CapabilityRegistryPath -AgentProfileRegistryPath $AgentProfileRegistryPath -ProviderRoutingPolicyPath $ProviderRoutingPolicyPath -ApprovalWorkflowPath $ApprovalWorkflowPath -MemoryArchitecturePath $MemoryArchitecturePath) -Force
        }
        return $Default
    }
}
