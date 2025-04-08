# DarlingDataCollector Installation Steps

The following steps should be added to the `collector_installation.sql` file to complete the installation:

## 1. Add System Procedures

After creating the system schema, add the following system procedure creation code:

```sql
/*
Create utility system procedures
*/

-- Create system.data_retention procedure
IF @debug = 1
BEGIN
    RAISERROR(N'Creating system.data_retention procedure...', 0, 1) WITH NOWAIT;
END;

-- Include system.data_retention.sql here

-- Create system.manage_databases procedure
IF @debug = 1
BEGIN
    RAISERROR(N'Creating system.manage_databases procedure...', 0, 1) WITH NOWAIT;
END;

-- Include system.manage_databases.sql here
```

## 2. Add Query Store Collection

After creating system procedures, add the Query Store collection procedure:

```sql
/*
Create collection procedures
*/

-- Create collection.collect_query_store procedure
IF @debug = 1
BEGIN
    RAISERROR(N'Creating collection.collect_query_store procedure...', 0, 1) WITH NOWAIT;
END;

-- Include collection.collect_query_store.sql here
```

## 3. Update Job Creation

Make sure the job creation procedure includes the new collection procedures:

```sql
-- Add to system.create_collection_jobs
-- Inside the creation of @query_sql variable:

SET @query_sql += N'
-- Add Query Store collection
EXECUTE collection.collect_query_store
    @debug = 0,
    @use_database_list = 1,
    @include_query_text = 1,
    @include_query_plans = 0,
    @include_runtime_stats = 1,
    @include_wait_stats = 1,
    @min_cpu_time_ms = 1000,
    @min_logical_io_reads = 1000;
';
```

## 4. Add Data Retention Job

Ensure the data retention job is created:

```sql
-- Add to system.create_collection_jobs
-- Include in the job creation section:

-- Create data retention job
IF @debug = 1
BEGIN
    RAISERROR(N'Creating data retention job...', 0, 1) WITH NOWAIT;
END;

SET @data_retention_sql = N'
EXECUTE system.data_retention
    @retention_days = ' + CONVERT(NVARCHAR(10), @retention_days) + N',
    @debug = 0;
';

EXECUTE @sp_executesql
    @data_retention_sql = N'USE ' + QUOTENAME(@default_database_name) + N';
' + @data_retention_sql;

EXECUTE @sp_add_job
    @job_name = @job_prefix + N'_DataRetention',
    @description = N'Removes old data from the collector tables based on the configured retention period',
    @category_name = N'Data Collector',
    @owner_login_name = N'sa',
    @enabled = 1;

EXECUTE @sp_add_jobstep
    @job_name = @job_prefix + N'_DataRetention',
    @step_name = N'Run data retention procedure',
    @subsystem = N'TSQL',
    @command = @data_retention_sql,
    @database_name = @default_database_name,
    @retry_attempts = 3,
    @retry_interval = 5;

EXECUTE @sp_add_jobschedule
    @job_name = @job_prefix + N'_DataRetention',
    @name = N'Daily schedule',
    @freq_type = 4, -- Daily
    @freq_interval = 1,
    @freq_subday_type = 1, -- At specified time
    @active_start_time = 010000; -- 1:00 AM
```

## 5. Initial Database Configuration

After creating all the procedures and jobs, set up the initial database configuration:

```sql
/*
Initial database configuration
*/
IF @debug = 1
BEGIN
    RAISERROR(N'Setting up initial database configuration...', 0, 1) WITH NOWAIT;
END;

-- Add current database to collection
DECLARE @current_db NVARCHAR(128) = DB_NAME();

IF @debug = 1
BEGIN
    RAISERROR(N'Adding current database (%s) to collection configuration...', 0, 1, @current_db) WITH NOWAIT;
END;

-- Add current database to all collection types
EXECUTE system.manage_databases
    @action = 'ADD',
    @database_name = @current_db,
    @collection_type = 'ALL',
    @debug = @debug;
```

Add these code blocks to the appropriate sections of the `collector_installation.sql` file to complete the installation process.