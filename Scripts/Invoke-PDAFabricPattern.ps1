[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PatternName,

    [Parameter(Mandatory = $true)]
    [string]$ContentInput,

    [Parameter(Mandatory = $false)]
    [object]$Variables = @{},

    [Parameter(Mandatory = $false)]
    [string]$VariablesJson = "",

    [Parameter(Mandatory = $false)]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function Get-PDAFabricPatternRoot {
    param([string]$Root)
    return (Join-Path $Root "PDA-Fabric")
}

function ConvertTo-PDAFabricSafeString {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return [string]$Value
}

function ConvertTo-PDAFabricVariableMap {
    param([object]$InputObject)

    $Map = @{}
    if ($null -eq $InputObject) {
        return $Map
    }

    if ($InputObject -is [hashtable]) {
        foreach ($Key in @($InputObject.Keys)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$Key)) {
                $Map[[string]$Key] = $InputObject[$Key]
            }
        }

        return $Map
    }

    if ($InputObject -is [pscustomobject]) {
        foreach ($Prop in @($InputObject.PSObject.Properties)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$Prop.Name)) {
                $Map[[string]$Prop.Name] = $Prop.Value
            }
        }

        return $Map
    }

    if ($InputObject -is [string]) {
        try {
            return ConvertTo-PDAFabricVariableMap -InputObject ($InputObject | ConvertFrom-Json)
        }
        catch {
            return $Map
        }
    }

    return $Map
}

function Resolve-PDAFabricPattern {
    param(
        [string]$PatternRoot,
        [string]$PatternName
    )

    $NormalizedPattern = ([string]$PatternName -replace '/', '\').Trim()
    $NormalizedPatternNoExt = [System.IO.Path]::ChangeExtension($NormalizedPattern, $null)
    $PatternBaseName = [System.IO.Path]::GetFileNameWithoutExtension($NormalizedPattern)
    $PatternFiles = @(Get-ChildItem -Path $PatternRoot -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)

    foreach ($File in $PatternFiles) {
        $Relative = [System.IO.Path]::GetRelativePath($PatternRoot, $File.FullName) -replace '/', '\'
        $RelativeNoExt = [regex]::Replace($Relative, '\.md$', '')
        $FileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
        $PatternNameValue = $RelativeNoExt -replace '\\', '/'

        if ($Relative -ieq $NormalizedPattern -or
            $RelativeNoExt -ieq $NormalizedPattern -or
            $RelativeNoExt -ieq $NormalizedPatternNoExt -or
            $RelativeNoExt -ieq $PatternBaseName -or
            $FileBaseName -ieq $PatternBaseName -or
            $FileBaseName -ieq $NormalizedPatternNoExt) {
            return [pscustomobject]@{
                path = $File.FullName
                relative_path = $Relative
                pattern_name = $PatternNameValue
                pattern_category = Split-Path $Relative -Parent
            }
        }
    }

    return $null
}

function Merge-PDAFabricVariables {
    param(
        [string]$PatternName,
        [string]$PatternPath,
        [string]$PatternCategory,
        [string]$ContentInput,
        [hashtable]$Variables
    )

    $Merged = @{}
    $Merged.pattern_name = $PatternName
    $Merged.pattern_path = $PatternPath
    $Merged.pattern_category = $PatternCategory
    $Merged.content_input = $ContentInput
    $Merged.content = $ContentInput

    foreach ($Key in @($Variables.Keys)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Key)) {
            $Merged[[string]$Key] = ConvertTo-PDAFabricSafeString $Variables[$Key]
        }
    }

    return $Merged
}

function Invoke-PDAFabricTemplateRender {
    param(
        [string]$TemplateText,
        [hashtable]$Variables
    )

    $Rendered = [string]$TemplateText
    foreach ($Key in @($Variables.Keys | Sort-Object -Unique)) {
        $Value = ConvertTo-PDAFabricSafeString $Variables[$Key]
        $Rendered = $Rendered.Replace("{{${Key}}}", $Value)
        $Rendered = $Rendered.Replace("{{ $Key }}", $Value)
    }

    return $Rendered
}

$Result = $null
try {
    $PatternRoot = Get-PDAFabricPatternRoot -Root $Root
    $Match = Resolve-PDAFabricPattern -PatternRoot $PatternRoot -PatternName $PatternName
    $VariableSource = if (-not [string]::IsNullOrWhiteSpace($VariablesJson)) {
        ConvertTo-PDAFabricVariableMap -InputObject ($VariablesJson | ConvertFrom-Json)
    }
    else {
        ConvertTo-PDAFabricVariableMap -InputObject $Variables
    }

    if (-not $Match) {
        $Result = [pscustomobject]@{
            status = "missing_pattern"
            pattern_root = $PatternRoot
            pattern_name = $PatternName
            pattern_path = ""
            pattern_category = ""
            content_input = $ContentInput
            rendered_prompt = ""
            rendered_prompt_length = 0
            variables = [pscustomobject]@{}
            variable_names = @()
            error = "Pattern not found under $PatternRoot."
        }
    }
    else {
        $TemplateText = Get-Content -Path $Match.path -Raw
        $VariableMap = Merge-PDAFabricVariables -PatternName $Match.pattern_name -PatternPath $Match.relative_path -PatternCategory $Match.pattern_category -ContentInput $ContentInput -Variables $VariableSource
        $RenderedPrompt = Invoke-PDAFabricTemplateRender -TemplateText $TemplateText -Variables $VariableMap

        $Result = [pscustomobject]@{
            status = "success"
            pattern_root = $PatternRoot
            pattern_name = $Match.pattern_name
            pattern_path = $Match.relative_path
            pattern_category = $Match.pattern_category
            content_input = $ContentInput
            rendered_prompt = $RenderedPrompt
            rendered_prompt_length = $RenderedPrompt.Length
            variables = [pscustomobject]$VariableMap
            variable_names = @($VariableMap.Keys | Sort-Object)
            error = ""
        }
    }
}
catch {
    $Result = [pscustomobject]@{
        status = "error"
        pattern_root = Get-PDAFabricPatternRoot -Root $Root
        pattern_name = $PatternName
        pattern_path = ""
        pattern_category = ""
        content_input = $ContentInput
        rendered_prompt = ""
        rendered_prompt_length = 0
        variables = [pscustomobject]@{}
        variable_names = @()
        error = $_.Exception.Message
    }
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 20
    return
}

$Result
