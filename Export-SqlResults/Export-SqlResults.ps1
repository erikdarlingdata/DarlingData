<#
.SYNOPSIS
    Runs a query or procedure and exports every result set to CSV, spilling
    artifact XML (execution plans, deadlock graphs, blocked process reports)
    and oversized text (query text, repro scripts, DDL) to individual files
    instead of trying to cram them into a cell.

.DESCRIPTION
    Built for the DarlingData toolkit - sp_QuickieStore, sp_QuickieCache,
    sp_PressureDetector, sp_HealthParser, sp_HumanEvents, sp_HumanEventsBlockViewer,
    sp_QueryReproBuilder, sp_IndexCleanup - plus sp_BlitzLock and anything else
    that returns multiple result sets with XML scattered through them.

    Uses System.Data.SqlClient directly - no PowerShell module required, so it
    runs on a locked-down production server without installing anything. Works
    in Windows PowerShell 5.1 and PowerShell 7.

    Values are classified by their first XML node, not by substring sniffing:

      root ShowPlanXML                       -> .sqlplan  (always spills)
      root deadlock / deadlock-list          -> .xdl      (always spills)
      root blocked-process-report,
           blocked-process, blocking-process -> .xml      (always spills)
      root event (raw XE wrapper)            -> .xml      (always spills)
      other XML                              -> .xml      (spills over -InlineMaxChars)
      plain text                             -> .sql/.txt (spills over -InlineMaxChars)

    The DarlingData procs wrap query text, repro scripts, and plans that fail
    casting to xml in processing instructions (<?query ...?>, <?statement_text ...?>,
    <?_ ...?>, <?query_plan ...?>) to make them clickable in SSMS. Those wrappers
    are stripped on export: wrapped plans land as openable .sqlplan files, and
    query text / scripts land as runnable .sql files - inline cells get the
    unwrapped text too.

    Spilled files go under files\ and the CSV cell holds the relative path.
    Spills are deduplicated by content hash - procs like sp_HealthParser repeat
    the same deadlock graph on every process/frame row, so identical values
    share one file. manifest.csv correlates result set, row, column, and file
    (many cells can map to one file). Server messages
    (RAISERROR WITH NOWAIT progress, PRINT output) stream to the console and to
    messages.log. GO batch separators are honored in -Query and -InputFile.

.EXAMPLE
    .\Export-SqlResults.ps1 -ServerInstance . -Database master -Query "EXEC dbo.sp_QuickieStore @get_all_databases = 1;" -OutDir C:\temp\quickiestore

.EXAMPLE
    .\Export-SqlResults.ps1 -ServerInstance PROD01 -Database master -InputFile .\healthparser.sql -OutDir C:\temp\prod01-healthparser -CommandTimeout 600

.EXAMPLE
    .\Export-SqlResults.ps1 -ServerInstance PROD01 -Database master -Query "EXEC dbo.sp_HumanEventsBlockViewer @session_name = N'blocked_process_report';" -OutDir C:\temp\prod01-blocking -Credential (Get-Credential)

.NOTES
    Copyright 2026 Darling Data, LLC
    https://www.erikdarling.com/

    Released under MIT license

    For support, head over to GitHub:
    https://code.erikdarling.com
#>
[CmdletBinding(DefaultParameterSetName = 'Query')]
param(
    [Parameter(Mandatory)]
    [string]$ServerInstance,

    [string]$Database = 'master',

    [Parameter(Mandatory, ParameterSetName = 'Query')]
    [string]$Query,

    [Parameter(Mandatory, ParameterSetName = 'File')]
    [string]$InputFile,

    [Parameter(Mandatory)]
    [string]$OutDir,

    # Values longer than this spill to their own file - XML and plain text alike.
    # Keeps short values inline for triage; artifact XML (plans, deadlock graphs,
    # blocked process reports) always spills regardless of size.
    [int]$InlineMaxChars = 8000,

    [int]$CommandTimeout = 600,

    # SQL auth. Omit entirely for Windows auth. Passed as a SqlCredential so the
    # password never lands in the connection string.
    [pscredential]$Credential,

    # Collapse newlines inside CSV cells to single spaces. Off by default:
    # quoted CSV fields carry embedded newlines fine (Excel included), and
    # collapsing destroys query text formatting.
    [switch]$FlattenNewlines,

    # Prefix cells starting with = + - @ with a single quote so Excel doesn't
    # evaluate them as formulas (query text starting with -- is the usual
    # victim). Off by default because it alters the raw data.
    [switch]$ExcelSafe
)

$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'File') {
    if (-not (Test-Path $InputFile)) { throw "InputFile not found: $InputFile" }
    $Query = Get-Content $InputFile -Raw
}

# Resolve OutDir against the PowerShell location, not the process CWD, so
# relative paths work with the raw .NET file APIs used below.
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$filesDir     = Join-Path $OutDir 'files'
$messagesPath = Join-Path $OutDir 'messages.log'

# Split on GO batch separators (line-start only, sqlcmd-style; GO <n> repeats).
function Split-SqlBatches {
    param([string]$Sql)

    $batches = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder

    foreach ($line in ($Sql -split "`r?`n")) {
        if ($line -match '^\s*GO(?:\s+(\d+))?\s*$') {
            $repeat = 1
            if ($Matches[1]) { $repeat = [int]$Matches[1] }
            $text = $sb.ToString()
            if ($text.Trim().Length -gt 0) {
                for ($r = 0; $r -lt $repeat; $r++) { $batches.Add($text) }
            }
            [void]$sb.Clear()
        }
        else {
            [void]$sb.AppendLine($line)
        }
    }

    $text = $sb.ToString()
    if ($text.Trim().Length -gt 0) { $batches.Add($text) }

    return ,$batches
}

# Render a reader value as text without losing anything to culture or
# PowerShell's default casts: datetime2 keeps its fractional seconds, and
# varbinary handles/hashes come out as 0x hex instead of a byte list.
function Format-SqlValue {
    param($Value)

    if ($Value -is [datetime]) {
        return $Value.ToString('yyyy-MM-dd HH:mm:ss.fffffff', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [System.DateTimeOffset]) {
        return $Value.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [byte[]]) {
        if ($Value.Length -eq 0) { return '0x' }
        return '0x' + [System.BitConverter]::ToString($Value).Replace('-', '')
    }
    if ($Value -is [timespan]) {
        return $Value.ToString('c')
    }
    return [string]$Value
}

# Classify a value by its first XML node. Returns Text (unwrapped if it was a
# processing instruction), Ext, and whether it always spills. Artifacts meant
# to be opened in a tool always spill - a 4KB deadlock graph is useless inline,
# because its value is being openable as a graph.
function Resolve-Field {
    param(
        [string]$Value,
        [bool]$LooksXml,
        [string]$ColumnName
    )

    if ($LooksXml) {
        $head = $Value.Substring(0, [Math]::Min(600, $Value.Length))
        $m = [regex]::Match(
            $head,
            '(?s)^\s*(?:<\?xml\b.*?\?>\s*)?(?:<!--.*?-->\s*)*<(?<pi>\?)?(?<name>[A-Za-z_][\w.\-]*)'
        )
        if ($m.Success) {
            $nodeName = $m.Groups['name'].Value

            if ($m.Groups['pi'].Success) {
                if ($nodeName -eq 'xml') {
                    # A bare xml declaration with nothing recognizable after it.
                    return @{ Text = $Value; Ext = '.xml'; Always = $false }
                }

                # DarlingData processing-instruction wrapper: strip it and
                # classify the payload. Plans that failed casting to xml become
                # openable .sqlplan files; query text and scripts become .sql.
                $inner = $Value -replace '(?s)^\s*<\?[A-Za-z_][\w.\-]*\s?', ''
                $inner = $inner -replace '(?s)\s*\?>\s*$', ''

                if ($inner.TrimStart().StartsWith('<ShowPlanXML')) {
                    return @{ Text = $inner; Ext = '.sqlplan'; Always = $true }
                }
                return @{ Text = $inner; Ext = '.sql'; Always = $false }
            }

            switch -Regex ($nodeName) {
                '^ShowPlanXML$' {
                    return @{ Text = $Value; Ext = '.sqlplan'; Always = $true }
                }
                '^deadlock(-list)?$' {
                    return @{ Text = $Value; Ext = '.xdl'; Always = $true }
                }
                '^(blocked-process-report|blocked-process|blocking-process)$' {
                    return @{ Text = $Value; Ext = '.xml'; Always = $true }
                }
                '^event$' {
                    return @{ Text = $Value; Ext = '.xml'; Always = $true }
                }
                default {
                    return @{ Text = $Value; Ext = '.xml'; Always = $false }
                }
            }
        }

        # Declared xml (or starts with <) but no recognizable node.
        return @{ Text = $Value; Ext = '.xml'; Always = $false }
    }

    # Plain text: long query text and generated scripts land as .sql, the rest as .txt.
    $ext = '.txt'
    if ($ColumnName -match '(?i)sql|script|statement|query|text|definition|command|ddl') {
        $ext = '.sql'
    }
    return @{ Text = $Value; Ext = $ext; Always = $false }
}

function ConvertTo-CsvField {
    param([string]$Value)

    if ($null -eq $Value) { return '' }

    $v = $Value
    if ($FlattenNewlines) {
        $v = $v -replace "`r`n", ' ' -replace "[`r`n]", ' '
    }
    if ($ExcelSafe -and $v.Length -gt 0 -and $v.Substring(0, 1) -match '[=+\-@]') {
        $v = "'" + $v
    }
    if ($v -match '[",\r\n]') {
        return '"' + ($v -replace '"', '""') + '"'
    }
    return $v
}

# Build the connection with SqlConnectionStringBuilder so a stray ; in a value
# can't rewrite the string, and pass SQL auth as a SqlCredential so the
# password never lands in the connection string at all. The builder is an
# IDictionary, so PowerShell property syntax would hit the keyword indexer -
# use explicit keyword keys.
$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$csb['Data Source']            = $ServerInstance
$csb['Initial Catalog']        = $Database
$csb['Application Name']       = 'Export-SqlResults'
$csb['TrustServerCertificate'] = $true

if ($Credential) {
    $pw = $Credential.Password.Copy()
    $pw.MakeReadOnly()
    $sqlCredential = New-Object System.Data.SqlClient.SqlCredential($Credential.UserName, $pw)
    $conn = New-Object System.Data.SqlClient.SqlConnection($csb.ToString(), $sqlCredential)
}
else {
    $csb['Integrated Security'] = $true
    $conn = New-Object System.Data.SqlClient.SqlConnection($csb.ToString())
}

# These procs narrate progress with RAISERROR WITH NOWAIT - keep it.
$conn.add_InfoMessage({
    param($sender, $e)
    foreach ($srvMsg in $e.Errors) {
        $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $srvMsg.Message
        Write-Host "  $line" -ForegroundColor DarkGray
        Add-Content -Path $messagesPath -Value $line -Encoding UTF8
    }
})

$batches = Split-SqlBatches -Sql $Query
if ($batches.Count -eq 0) { throw 'No executable SQL found in the input.' }

$manifest = New-Object System.Collections.Generic.List[object]
$spillIndex = @{}
$sha = [System.Security.Cryptography.SHA256]::Create()
$setNo = 0

try {
    $conn.Open()
    Write-Host "connected: $ServerInstance / $Database" -ForegroundColor Green

    foreach ($batch in $batches) {
        $cmd = $conn.CreateCommand()
        try {
            $cmd.CommandText    = $batch
            $cmd.CommandTimeout = $CommandTimeout

            $reader = $cmd.ExecuteReader()
            try {
                do {
                    $setNo++
                    if ($reader.FieldCount -eq 0) { continue }

                    $cols = @(0..($reader.FieldCount - 1) | ForEach-Object { $reader.GetName($_) })
                    # Columns whose declared type is xml; used alongside a content sniff below.
                    $xmlCols = @{}
                    for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                        if ($reader.GetDataTypeName($i) -eq 'xml') { $xmlCols[$i] = $true }
                    }

                    $csvPath = Join-Path $OutDir ("resultset{0:D2}.csv" -f $setNo)
                    $sw = New-Object System.IO.StreamWriter($csvPath, $false, (New-Object System.Text.UTF8Encoding($true)))
                    $rowNo   = 0
                    $spilled = 0
                    try {
                        $sw.WriteLine((($cols | ForEach-Object { ConvertTo-CsvField $_ }) -join ','))

                        while ($reader.Read()) {
                            $rowNo++
                            $fields = New-Object System.Collections.Generic.List[string]

                            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                                if ($reader.IsDBNull($i)) { $fields.Add(''); continue }

                                $val = Format-SqlValue $reader.GetValue($i)
                                $looksXml = $xmlCols.ContainsKey($i) -or $val.TrimStart().StartsWith('<')

                                # Fast path: short plain text never spills.
                                if (-not $looksXml -and $val.Length -le $InlineMaxChars) {
                                    $fields.Add((ConvertTo-CsvField $val))
                                    continue
                                }

                                $kind = Resolve-Field -Value $val -LooksXml $looksXml -ColumnName $cols[$i]

                                if ($kind.Always -or $kind.Text.Length -gt $InlineMaxChars) {
                                    # Dedupe by content hash: procs like sp_HealthParser repeat the
                                    # same deadlock graph on every process/frame row. Write each
                                    # distinct artifact once and point every cell at the shared file.
                                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($kind.Text)
                                    $key = [System.BitConverter]::ToString($sha.ComputeHash($bytes)) + $kind.Ext
                                    $rel = $spillIndex[$key]
                                    if (-not $rel) {
                                        $safe = ($cols[$i] -replace '[^\w]', '_')
                                        if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'col' }
                                        if ($safe.Length -gt 60) { $safe = $safe.Substring(0, 60) }
                                        # Ordinal in the name so duplicate column names can't collide.
                                        $name = "rs{0:D2}_r{1:D4}_c{2:D2}_{3}{4}" -f $setNo, $rowNo, $i, $safe, $kind.Ext
                                        [void][System.IO.Directory]::CreateDirectory($filesDir)
                                        [System.IO.File]::WriteAllBytes((Join-Path $filesDir $name), $bytes)
                                        $rel = "files\$name"
                                        $spillIndex[$key] = $rel
                                    }
                                    $fields.Add($rel)
                                    $spilled++
                                    $manifest.Add([pscustomobject]@{
                                        ResultSet = $setNo
                                        Row       = $rowNo
                                        Column    = $cols[$i]
                                        File      = $rel
                                        Bytes     = $bytes.Length
                                    })
                                }
                                else {
                                    $fields.Add((ConvertTo-CsvField $kind.Text))
                                }
                            }
                            $sw.WriteLine(($fields -join ','))
                        }
                    }
                    finally {
                        $sw.Dispose()
                    }

                    Write-Host ("  resultset{0:D2}.csv  {1,5} rows x {2,2} cols  ({3} spilled files)" -f $setNo, $rowNo, $cols.Count, $spilled)

                } while ($reader.NextResult())
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $cmd.Dispose()
        }
    }
}
finally {
    $conn.Dispose()
}

$sha.Dispose()

if ($manifest.Count -gt 0) {
    $manifest | Export-Csv (Join-Path $OutDir 'manifest.csv') -NoTypeInformation -Encoding UTF8
    $uniqueFiles = @($manifest | Group-Object File)
    $mb = [math]::Round((($uniqueFiles | ForEach-Object { $_.Group[0].Bytes }) | Measure-Object -Sum).Sum / 1MB, 1)
    Write-Host ""
    Write-Host "$($manifest.Count) values spilled into $($uniqueFiles.Count) files, ${mb}MB on disk" -ForegroundColor Yellow
    Write-Host "manifest: manifest.csv" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "output: $OutDir" -ForegroundColor Green
