$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$requiredFiles = @(
    'translations.json',
    'translations_skills.json',
    'translations_quests.json',
    'translations_items.json',
    'translations_menu.json',
    'translations_overhead.json',
    'translations_game_message.json',
    'translations_welcome.json',
    'translations_settings.json'
)

$languageDirectories = Get-ChildItem -LiteralPath $repositoryRoot -Directory |
    Where-Object { $_.Name -notin @('scripts', 'correcao') } |
    Sort-Object Name

if ($languageDirectories.Count -eq 0) {
    throw 'Nenhuma pasta de idioma encontrada.'
}

$invalidFiles = New-Object System.Collections.Generic.List[string]

function Get-JsonErrorLocation {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Content,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $lineMatch = [regex]::Match(
        $Message,
        'line\s+(\d+),\s+position\s+(\d+)',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if ($lineMatch.Success) {
        return "linha $($lineMatch.Groups[1].Value), coluna $($lineMatch.Groups[2].Value)"
    }

    $characterMatch = [regex]::Match($Message, '\((\d+)\)')
    if (-not $characterMatch.Success) {
        return $null
    }

    $position = [int]$characterMatch.Groups[1].Value
    $offset = [Math]::Max(0, [Math]::Min($position - 1, $Content.Length))
    $prefix = $Content.Substring(0, $offset)
    $line = ([regex]::Matches($prefix, "`n")).Count + 1
    $lastNewLine = $prefix.LastIndexOf("`n")
    $column = $offset - $lastNewLine
    return "linha $line, coluna $column"
}

function Test-TranslationJson {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $convertFromJson = Get-Command ConvertFrom-Json

    try {
        if ($convertFromJson.Parameters.ContainsKey('AsHashtable')) {
            $json = ConvertFrom-Json -InputObject $content -AsHashtable
        } else {
            Add-Type -AssemblyName System.Web.Extensions
            $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $serializer.MaxJsonLength = [int]::MaxValue
            $json = $serializer.DeserializeObject($content)
        }
    } catch {
        $location = Get-JsonErrorLocation -Content $content -Message $_.Exception.Message
        if ($null -ne $location) {
            throw "$location - $($_.Exception.Message)"
        }
        throw
    }

    if ($json -isnot [System.Collections.IDictionary]) {
        throw 'a raiz deve ser um objeto JSON'
    }

    foreach ($entry in $json.GetEnumerator()) {
        if ($entry.Value -isnot [string]) {
            throw "o valor da chave '$($entry.Key)' deve ser texto"
        }
    }
}

foreach ($languageDirectory in $languageDirectories) {
    foreach ($fileName in $requiredFiles) {
        $filePath = Join-Path $languageDirectory.FullName $fileName
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            [void]$invalidFiles.Add("$filePath - arquivo obrigatorio ausente")
            continue
        }

        try {
            Test-TranslationJson -Path $filePath
        } catch {
            [void]$invalidFiles.Add("$filePath - $($_.Exception.Message)")
        }
    }
}

if ($invalidFiles.Count -gt 0) {
    Write-Host ''
    Write-Host 'ERRO: foram encontrados JSONs invalidos ou ausentes:' -ForegroundColor Red
    foreach ($invalidFile in $invalidFiles) {
        Write-Host "  - $invalidFile" -ForegroundColor Red
    }
    throw 'A publicacao foi cancelada. Corrija os arquivos listados antes de continuar.'
}

Write-Host 'Validacao dos JSONs concluida: todos os arquivos estao no formato aceito pelo plugin.' -ForegroundColor Green
