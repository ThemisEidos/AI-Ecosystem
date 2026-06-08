function Remove-PDAAnsiEscapeSequences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    $CleanText = [string]$Text
    $AnsiPatterns = @(
        # CSI sequences, including color and cursor control codes.
        '\u001B\[[0-?]*[ -/]*[@-~]',
        # OSC sequences, terminated by BEL or ST.
        '\u001B\][^\u0007]*(?:\u0007|\u001B\\)',
        # Two-character escape sequences.
        '\u001B[@-Z\\-_]'
    )

    foreach ($Pattern in $AnsiPatterns) {
        $CleanText = [regex]::Replace($CleanText, $Pattern, '')
    }

    return $CleanText
}

function Get-PDAJsonSubstring {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $InputText = Remove-PDAAnsiEscapeSequences -Text $Text
    if ([string]::IsNullOrWhiteSpace($InputText)) {
        return ""
    }

    for ($StartIndex = 0; $StartIndex -lt $InputText.Length; $StartIndex++) {
        $Opening = $InputText[$StartIndex]
        if ($Opening -ne '{' -and $Opening -ne '[') {
            continue
        }

        $Closing = if ($Opening -eq '{') { '}' } else { ']' }
        $Depth = 0
        $InString = $false
        $Escaped = $false

        for ($Index = $StartIndex; $Index -lt $InputText.Length; $Index++) {
            $Char = $InputText[$Index]

            if ($InString) {
                if ($Escaped) {
                    $Escaped = $false
                    continue
                }

                if ($Char -eq '\') {
                    $Escaped = $true
                    continue
                }

                if ($Char -eq '"') {
                    $InString = $false
                }
                continue
            }

            if ($Char -eq '"') {
                $InString = $true
                continue
            }

            if ($Char -eq $Opening) {
                $Depth++
                continue
            }

            if ($Char -eq $Closing) {
                $Depth--
                if ($Depth -eq 0) {
                    return $InputText.Substring($StartIndex, ($Index - $StartIndex + 1))
                }
            }
        }
    }

    return ""
}

function ConvertFrom-PDAMixedJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$SourceName = "output"
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "$SourceName returned empty output."
    }

    $JsonText = Get-PDAJsonSubstring -Text $Text
    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        throw "$SourceName did not contain parseable JSON after stripping ANSI and scanning mixed output."
    }

    try {
        return $JsonText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "$SourceName contained JSON that could not be parsed: $($_.Exception.Message)"
    }
}

function ConvertFrom-PDAFlexibleJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [string]$SourceName = "output"
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "$SourceName returned empty output."
    }

    $Candidates = New-Object System.Collections.Generic.List[string]
    $Trimmed = [string]$Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($Trimmed)) {
        $Candidates.Add($Trimmed)
    }

    $JsonSubstring = Get-PDAJsonSubstring -Text $Text
    if (-not [string]::IsNullOrWhiteSpace($JsonSubstring) -and $JsonSubstring -ne $Trimmed) {
        $Candidates.Add($JsonSubstring)
    }

    foreach ($Candidate in @($Candidates | Select-Object -Unique)) {
        try {
            $Parsed = $Candidate | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            continue
        }

        if ($Parsed -is [string]) {
            $Nested = [string]$Parsed
            if (-not [string]::IsNullOrWhiteSpace($Nested)) {
                $NestedTrimmed = $Nested.Trim()
                if ($NestedTrimmed.StartsWith("{") -or $NestedTrimmed.StartsWith("[")) {
                    try {
                        return $NestedTrimmed | ConvertFrom-Json -ErrorAction Stop
                    }
                    catch {
                        # Fall through and return the outer parsed string if it is the best available result.
                    }
                }
            }
        }

        return $Parsed
    }

    throw "$SourceName contained JSON that could not be parsed after normalization."
}
