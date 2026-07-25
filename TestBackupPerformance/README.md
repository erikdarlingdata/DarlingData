<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# TestBackupPerformance

Finding the fastest backup settings for your database shouldn't require guesswork. This procedure tests every combination of file count (striping), compression, buffer count, and max transfer size, then ranks the results so you can see what actually works best on your hardware.

Results are persisted to `dbo.backup_performance_results` so you can compare across runs, servers, and databases.

## Parameters

|       parameter_name        | data_type |                              description                               |                        valid_inputs                        |       defaults        |
|-----------------------------|-----------|------------------------------------------------------------------------|------------------------------------------------------------|-----------------------|
| @database_name              | sysname   | database to back up                                                    | a valid database name                                      | NULL (required)       |
| @backup_path                | nvarchar  | directory path, DEFAULT for instance default, or NUL to discard        | a valid directory path, DEFAULT, or NUL                    | NULL (required)       |
| @file_count_list            | varchar   | comma-separated list of file counts (backup stripes)                   | comma-separated integers                                   | 1,2,4                 |
| @compression_list           | varchar   | comma-separated list: 0 = no compression, 1 = compressed              | comma-separated 0s and 1s                                  | 0,1                   |
| @buffer_count_list          | varchar   | comma-separated list of buffer counts (0 = SQL Server default)         | comma-separated integers (0 for default)                   | 0,15,30,50            |
| @max_transfer_size_list     | varchar   | comma-separated list of max transfer sizes in bytes (0 = default 1MB)  | comma-separated integers, multiples of 65536, max 4194304  | 0,2097152,4194304     |
| @stats                      | tinyint   | backup completion percent to print progress at                         | 1-100                                                      | 1                     |
| @iterations                 | integer   | times to repeat each configuration for averaging                       | a positive integer                                         | 1                     |
| @help                       | bit       | how you got here                                                       | 0 or 1                                                     | 0                     |
| @debug                      | bit       | prints dynamic sql, displays parameter and variable values             | 0 or 1                                                     | 0                     |
| @version                    | varchar   | OUTPUT; for support                                                    | none                                                       | none; OUTPUT          |
| @version_date               | datetime  | OUTPUT; for support                                                    | none                                                       | none; OUTPUT          |

## Examples

```sql
-- Test with defaults (24 combinations: 3 file counts x 2 compression x 4 buffer counts x 3 transfer sizes)
EXECUTE dbo.TestBackupPerformance
    @database_name = N'YourDatabase',
    @backup_path = N'D:\Backups';

-- Test throughput without disk I/O (backup to NUL device)
EXECUTE dbo.TestBackupPerformance
    @database_name = N'YourDatabase',
    @backup_path = N'NUL';

-- Use the instance's default backup directory
EXECUTE dbo.TestBackupPerformance
    @database_name = N'YourDatabase',
    @backup_path = N'DEFAULT';

-- Run 3 iterations per combination for more stable averages
EXECUTE dbo.TestBackupPerformance
    @database_name = N'YourDatabase',
    @backup_path = N'D:\Backups',
    @iterations = 3;

-- Narrow the test to specific settings
EXECUTE dbo.TestBackupPerformance
    @database_name = N'YourDatabase',
    @backup_path = N'D:\Backups',
    @file_count_list = '1,4,8',
    @compression_list = '1',
    @buffer_count_list = '0,50',
    @max_transfer_size_list = '0,4194304',
    @iterations = 3;
```

## Result Sets

1. **All configurations ranked by throughput** -- every combination ranked best to worst
2. **Best config per compression setting** -- fastest compressed vs fastest uncompressed
3. **Parameter impact** -- which knob matters most (larger spread = bigger effect)
4. **Efficiency** -- best throughput per MB of buffer RAM (filtered to configs within 80% of peak)
5. **Consistency** -- min/max/stddev per config (only when `@iterations > 1`)

## Notes

* **BUFFERCOUNT** and **MAXTRANSFERSIZE** memory is allocated outside the buffer pool. The procedure warns when a combination will use more than 1 GB.
* Backup files are automatically cleaned up after each test. NUL backups skip cleanup.
* The `dbo.backup_performance_results` table is created automatically on first run.
