param(
    [string]$WeliveDir = "",
    [string]$WechatId = "",
    [string]$OutDir = "",
    [switch]$SkipInit,
    [switch]$NoElevate
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-QuotedArgument {
    param([string]$Value)

    return '"' + ($Value -replace '"', '\"') + '"'
}

function Restart-AsAdministrator {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters
    )

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (ConvertTo-QuotedArgument $ScriptPath)
    )

    foreach ($key in $Parameters.Keys) {
        if ($key -eq "NoElevate") {
            continue
        }

        $value = $Parameters[$key]
        if ($value -is [switch] -or $value -is [bool]) {
            if ($value) {
                $arguments += "-$key"
            }
            continue
        }

        if ($null -ne $value -and [string]$value -ne "") {
            $arguments += "-$key"
            $arguments += ConvertTo-QuotedArgument ([string]$value)
        }
    }

    Start-Process -FilePath "powershell.exe" -ArgumentList ($arguments -join " ") -Verb RunAs
}

function ConvertTo-SafeFileName {
    param([Parameter(Mandatory)][string]$Name)

    $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    $builder = [Text.StringBuilder]::new()

    foreach ($char in $Name.ToCharArray()) {
        if ($invalidChars -contains $char) {
            [void]$builder.Append("_")
        } else {
            [void]$builder.Append($char)
        }
    }

    $safeName = $builder.ToString().Trim()
    if ($safeName -eq "") {
        return "welive_chat"
    }

    return $safeName.TrimEnd(".", " ")
}

function New-WeliveMarkdownPath {
    param(
        [Parameter(Mandatory)][string]$OutDir,
        [Parameter(Mandatory)][string]$Alias
    )

    $chatRecordSuffix = -join @([char]0x804A, [char]0x5929, [char]0x8BB0, [char]0x5F55)
    return Join-Path $OutDir "$(ConvertTo-SafeFileName $Alias)`_$chatRecordSuffix.md"
}

function Resolve-WeliveDirectory {
    param(
        [string]$WeliveDir,
        [Parameter(Mandatory)][string]$ScriptRoot
    )

    if ([string]::IsNullOrWhiteSpace($WeliveDir)) {
        return (Resolve-Path -LiteralPath $ScriptRoot).Path
    }

    return (Resolve-Path -LiteralPath $WeliveDir).Path
}

function ConvertFrom-WeliveContactsText {
    param([Parameter(Mandatory)][string]$Text)

    try {
        $parsed = $Text | ConvertFrom-Json
        return @($parsed | ForEach-Object {
            [pscustomobject]@{
                alias = [string]$_.alias
                username = [string]$_.username
            }
        })
    } catch {
        $trimmed = $Text.Trim()
        if (-not ($trimmed.StartsWith("[") -and $trimmed.EndsWith("]"))) {
            throw "contacts output is not a JSON array and could not be parsed"
        }

        $body = $trimmed.Substring(1, $trimmed.Length - 2)
        if ($body.Trim() -eq "") {
            return @()
        }

        return @($body -split "\},\{" | ForEach-Object {
            $record = $_
            $usernameMatch = [regex]::Match($record, '"username"\s*:\s*"([^"]*)"')
            $aliasMatch = [regex]::Match($record, '"alias"\s*:\s*"([^"]*)"')

            if ($usernameMatch.Success -or $aliasMatch.Success) {
                [pscustomobject]@{
                    alias = if ($aliasMatch.Success) { $aliasMatch.Groups[1].Value } else { "" }
                    username = if ($usernameMatch.Success) { $usernameMatch.Groups[1].Value } else { "" }
                }
            }
        })
    }
}

function Find-WeliveContactByAlias {
    param(
        [Parameter(Mandatory)][object[]]$Contacts,
        [Parameter(Mandatory)][string]$Alias
    )

    $matches = @($Contacts | Where-Object { [string]$_.alias -eq $Alias })

    if ($matches.Count -eq 0) {
        throw "No contact found for alias '$Alias'. Please confirm the contact's WeChat ID and try again."
    }

    if ($matches.Count -gt 1) {
        $usernames = ($matches | ForEach-Object { $_.username }) -join ", "
        throw "Multiple contacts found for alias '$Alias': $usernames. Please inspect contacts_raw.json manually."
    }

    if ([string]::IsNullOrWhiteSpace([string]$matches[0].username)) {
        throw "Contact '$Alias' was found, but its username/wxid is empty."
    }

    return $matches[0]
}

function Invoke-WeliveCommandCaptured {
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = & $ExePath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "welive.exe $($Arguments -join ' ') failed with exit code $exitCode.`n$output"
    }

    return @($output)
}

function Invoke-WeliveCommandInteractive {
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    & $ExePath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "welive.exe $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

function Invoke-ExportWeliveChat {
    param(
        [string]$WeliveDir,
        [string]$WechatId,
        [string]$OutDir,
        [switch]$SkipInit,
        [switch]$NoElevate
    )

    if (-not $NoElevate -and -not (Test-IsAdministrator)) {
        Write-Host "Administrator PowerShell is required. Requesting elevation..."
        Restart-AsAdministrator -ScriptPath $PSCommandPath -Parameters $PSBoundParameters
        return
    }

    $weliveDirPath = Resolve-WeliveDirectory -WeliveDir $WeliveDir -ScriptRoot $PSScriptRoot
    $exePath = Join-Path $weliveDirPath "welive.exe"
    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "welive.exe not found: $exePath"
    }

    if ([string]::IsNullOrWhiteSpace($OutDir)) {
        $OutDir = $weliveDirPath
    }

    $outDirPath = if (Test-Path -LiteralPath $OutDir) {
        (Resolve-Path -LiteralPath $OutDir).Path
    } else {
        New-Item -ItemType Directory -Path $OutDir | Out-Null
        (Resolve-Path -LiteralPath $OutDir).Path
    }

    Push-Location $weliveDirPath
    try {
        if (-not $SkipInit) {
            Write-Host "Running welive init..."
            Invoke-WeliveCommandInteractive -ExePath $exePath -Arguments @("init")
        }

        Write-Host "Exporting contacts_raw.json..."
        $contactsOutput = Invoke-WeliveCommandCaptured -ExePath $exePath -Arguments @("contacts")
        $contactsText = $contactsOutput -join [Environment]::NewLine
        $contactsPath = Join-Path $outDirPath "contacts_raw.json"
        Set-Content -LiteralPath $contactsPath -Value $contactsText -Encoding UTF8

        if ([string]::IsNullOrWhiteSpace($WechatId)) {
            $WechatId = Read-Host "Enter contact WeChat ID (alias)"
        }

        $contacts = ConvertFrom-WeliveContactsText -Text $contactsText
        $contact = Find-WeliveContactByAlias -Contacts $contacts -Alias $WechatId
        $markdownPath = New-WeliveMarkdownPath -OutDir $outDirPath -Alias $WechatId

        Write-Host "Matched wxid: $($contact.username)"
        Write-Host "Exporting chat markdown: $markdownPath"

        Invoke-WeliveCommandInteractive -ExePath $exePath -Arguments @(
            "export-session",
            "--session-id", [string]$contact.username,
            "--readable",
            "--parse-content",
            "--asc",
            "--lite",
            "--out", $markdownPath
        )

        Write-Host "Export complete: $markdownPath"
        Write-Host "Contacts cache: $contactsPath"
    } finally {
        Pop-Location
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    Invoke-ExportWeliveChat @PSBoundParameters
}
