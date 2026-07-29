<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# Export-SqlResults

A PowerShell script that runs a query or stored procedure and exports every result set to CSV, spilling execution plans, deadlock graphs, blocked process reports, and oversized query text or scripts to individual files that open in the right tool.

SSMS grid results are a dead end for this stuff: plans get truncated, XML columns are unreadable, and nothing survives being pasted into a ticket. This script gets proc output onto disk in a shape you can actually send to someone.

Built for the scripts in this repo — sp_QuickieStore, sp_QuickieCache, sp_PressureDetector, sp_HealthParser, sp_HumanEvents, sp_HumanEventsBlockViewer, sp_QueryReproBuilder, sp_IndexCleanup, sp_PerfCheck, sp_LogHunter — plus sp_BlitzLock and anything else that returns result sets with XML scattered through them.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 — no modules to install; it uses System.Data.SqlClient directly, so it runs on locked-down servers
- Windows auth by default, or pass `-Credential` for SQL auth (sent as a SqlCredential, never embedded in the connection string)

## Usage

```powershell
.\Export-SqlResults.ps1 -ServerInstance . -Database master -Query "EXEC dbo.sp_QuickieStore @get_all_databases = 1;" -OutDir C:\temp\quickiestore
```

```powershell
.\Export-SqlResults.ps1 -ServerInstance PROD01 -Database master -InputFile .\healthparser.sql -OutDir C:\temp\prod01-healthparser -CommandTimeout 600
```

```powershell
.\Export-SqlResults.ps1 -ServerInstance PROD01 -Database master -Query "EXEC dbo.sp_HumanEventsBlockViewer @session_name = N'blocked_process_report';" -OutDir C:\temp\prod01-blocking -Credential (Get-Credential)
```

## Parameters

| Parameter Name | Data Type | Default Value | Description |
|----------------|-----------|---------------|-------------|
| @ServerInstance | string | required | Server or instance to connect to |
| @Database | string | master | Database context for the query |
| @Query | string | | T-SQL to run (this or -InputFile) |
| @InputFile | string | | Path to a .sql file to run (GO batches are honored) |
| @OutDir | string | required | Output folder; created if missing |
| @InlineMaxChars | int | 8000 | Values longer than this spill to their own file; artifact XML (plans, deadlock graphs, blocked process reports) always spills |
| @CommandTimeout | int | 600 | Command timeout in seconds |
| @Credential | pscredential | | SQL auth; omit for Windows auth |
| @FlattenNewlines | switch | off | Collapse newlines in CSV cells to spaces (quoted CSV carries newlines fine without it) |
| @ExcelSafe | switch | off | Prefix cells starting with = + - @ so Excel does not evaluate them as formulas |

## How values are classified

Every value is classified by its first XML node, not by substring sniffing:

| Content | Extension | Spills |
|---------|-----------|--------|
| root ShowPlanXML | .sqlplan | always |
| root deadlock / deadlock-list | .xdl | always |
| root blocked-process-report / blocked-process / blocking-process | .xml | always |
| root event (raw Extended Events wrapper) | .xml | always |
| other XML | .xml | over -InlineMaxChars |
| plain text | .sql or .txt | over -InlineMaxChars |

The scripts in this repo wrap query text, repro scripts, and plans that fail casting to xml in processing instructions (`<?query ...?>`, `<?statement_text ...?>`, `<?_ ...?>`, `<?query_plan ...?>`) to make them clickable in SSMS. Those wrappers are stripped on export: wrapped plans land as openable .sqlplan files, and query text and repro scripts land as runnable .sql files.

## Output layout

```
OutDir\
    resultset01.csv        one CSV per result set, in output order
    resultset02.csv
    files\                 spilled artifacts; CSV cells hold the relative path
        rs02_r0001_c05_query_plan.sqlplan
        rs02_r0001_c06_deadlock_graph.xdl
    manifest.csv           result set / row / column -> file correlation
    messages.log           RAISERROR WITH NOWAIT progress and PRINT output
```

Spilled files are deduplicated by content hash. Procs like sp_HealthParser repeat the same deadlock graph on every process and frame row — identical values share one file on disk, and the manifest maps every referencing cell to it.

## Warning

Exports are only as small as what you ask for. sp_HealthParser against a server with a deep system_health backlog can produce tens of thousands of distinct deadlock graphs and hundreds of megabytes of files. Aim it somewhere with disk space.

Copyright 2026 Darling Data, LLC  
Released under MIT license
