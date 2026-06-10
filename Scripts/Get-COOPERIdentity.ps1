function Get-COOPERIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    function Get-COOPERDefaultModelName {
        param(
            [Parameter(Mandatory = $false)]
            [string]$Fallback = "local-llama"
        )

        $Configured = [string]$env:COOPER_DEFAULT_MODEL
        if (-not [string]::IsNullOrWhiteSpace($Configured)) {
            return $Configured.Trim()
        }

        return $Fallback
    }

    $ProfilePath = Join-Path $Root "Scripts\COOPER_Personality.json"
    $CapabilityRegistryPath = Join-Path $Root "Scripts\PDA_CapabilityRegistry.json"
    $AgentProfileRegistryPath = Join-Path $Root "Scripts\PDA_AgentProfileRegistry.json"
    $ProviderRoutingPolicyPath = Join-Path $Root "Scripts\PDA_ProviderRoutingPolicy.json"
    $ApprovalWorkflowPath = Join-Path $Root "Scripts\PDA_ApprovalWorkflow.ps1"
    $MemoryArchitecturePath = Join-Path $Root "Documentation\COOPER-Memory-Architecture.md"

    function New-COOPERPersonalityProfile {
        return [pscustomobject]@{
            humor_level = 65
            honesty_level = 99
            directness_level = 90
            formality_level = 35
            risk_tolerance = 20
            discretion_level = 90
            verbosity_level = 35
            confidence_level = 85
            tars_inspired_not_copyrighted_imitation = $true
            truthfulness = 99
            humor_frequency = 65
            humor_style = @("dry", "deadpan", "operational", "skeptical")
            directness = 90
            formality = 35
            autonomy = 25
            skepticism = 90
            mission_focus = 100
            diplomacy = 55
            humor = 65
            sarcasm = 45
            honesty = 99
            brevity = 35
            verbosity = 35
            initiative = 70
            caution = 90
            persistence = 85
            confidence = 85
            discretion = 90
        }
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

        $PersonalityLoaded = Test-Path -LiteralPath $ProfilePath -PathType Leaf
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
        else {
            $Personality = $Profile.personality
            $Defaults = New-COOPERPersonalityProfile
            foreach ($Property in $Defaults.PSObject.Properties) {
                if (-not ($Personality.PSObject.Properties.Name -contains $Property.Name)) {
                    $Personality | Add-Member -NotePropertyName $Property.Name -NotePropertyValue $Property.Value -Force
                }
            }
            if ($Personality.PSObject.Properties.Name -contains "humor_level" -and [int]$Personality.humor_level -lt 65) {
                $Personality.humor_level = 65
            }
            if ($Personality.PSObject.Properties.Name -contains "honesty_level" -and [int]$Personality.honesty_level -lt 99) {
                $Personality.honesty_level = 99
            }
            if ($Personality.PSObject.Properties.Name -contains "directness_level" -and [int]$Personality.directness_level -lt 90) {
                $Personality.directness_level = 90
            }
            if ($Personality.PSObject.Properties.Name -contains "formality_level" -and [int]$Personality.formality_level -gt 35) {
                $Personality.formality_level = 35
            }
            if ($Personality.PSObject.Properties.Name -contains "risk_tolerance" -and [int]$Personality.risk_tolerance -gt 20) {
                $Personality.risk_tolerance = 20
            }
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
