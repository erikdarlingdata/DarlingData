<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# Clear Token Perm

This directory contains scripts for monitoring and managing SQL Server's security token cache. The security token cache (TokenAndPermUserStore) can grow to a significant size in certain scenarios, potentially causing high memory usage and performance issues.

## Overview

SQL Server caches security tokens in memory, and in specific environments (particularly with frequent application role usage, or high numbers of users), this cache can grow to consume gigabytes of memory. These scripts provide solutions to monitor the cache size and automatically clear it when it exceeds a defined threshold.

## Components

The directory includes three files:

1. **ClearTokenPerm.sql**: Creates a stored procedure to monitor and clear the security token cache
2. **ClearTokenPerm Agent Job.sql**: Creates a SQL Agent job to run the ClearTokenPerm procedure on a schedule
3. **Inflate Security Cache Demo And Analysis Script.sql**: Demonstrates how to artificially inflate the security cache for testing and provides analysis queries

## ClearTokenPerm Stored Procedure

The main stored procedure monitors the size of the TokenAndPermUserStore cache and clears it when it exceeds a specified threshold.

| Parameter Name | Data Type | Default Value | Description |
|----------------|-----------|---------------|-------------|
| @CacheSizeGB | decimal(38,2) | None (required) | The threshold size in GB that triggers cache clearing |

The procedure:
- Creates a logging table (ClearTokenPermLogging) if it doesn't exist
- Checks the current size of the TokenAndPermUserStore cache
- Clears the cache using DBCC FREESYSTEMCACHE if the threshold is exceeded
- Logs all checks with timestamp, cache size, and whether clearing was triggered

## SQL Agent Job

The Agent job script:
- Creates a job named "Clear Security Cache Every 30 Minutes"
- Runs the ClearTokenPerm procedure with a 1GB threshold
- Schedules execution every 30 minutes
- Includes error handling and transaction support

## Demo and Analysis Script

The demo script:
- Creates an application role and executes a loop to inflate the cache
- Provides detailed analysis queries to examine:
  - Token distribution in the cache
  - Logins and tokens per login
  - Users and tokens per user
  - Cache invalidations per database
- Includes cleanup steps

## Usage Examples

```sql
-- Check and potentially clear the cache if it's over 2GB
EXECUTE dbo.ClearTokenPerm
    @CacheSizeGB = 2;

-- Query the logging table to see history
SELECT
    cl.* 
FROM dbo.ClearTokenPermLogging AS cl
ORDER BY
    cl.log_date DESC;

-- Clear the logging table
TRUNCATE TABLE dbo.ClearTokenPermLogging;
```

## Warning

The DBCC FREESYSTEMCACHE command used in these scripts will clear the security cache, which may cause a temporary performance impact as the cache is rebuilt. Test thoroughly in non-production environments before deploying to production.

Copyright 2025 Darling Data, LLC  
Released under MIT license
