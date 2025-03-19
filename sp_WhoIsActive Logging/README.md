<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# sp_WhoIsActive Logging

This toolkit automates the collection and management of SQL Server activity data using Adam Machanic's popular sp_WhoIsActive stored procedure. It creates a comprehensive logging framework that captures server activity in daily tables and provides useful views for analysis.

## Overview

The sp_WhoIsActive Logging toolkit consists of several components:

1. **Daily Table Creation**: Automatically creates tables named WhoIsActive_YYYYMMDD to store server activity data
2. **Data Collection**: Executes sp_WhoIsActive and logs output to the daily tables
3. **Data Retention**: Automatically manages retention by removing tables older than a specified period
4. **Analysis Views**: Creates views for querying across all tables and analyzing blocking chains
5. **Automated Collection**: Includes an Agent job for scheduling regular collection (default: every minute)

## Prerequisites

- Adam Machanic's sp_WhoIsActive stored procedure must be installed
  - If you need to get or update: [https://github.com/amachanic/sp_whoisactive](https://github.com/amachanic/sp_whoisactive)
  - If you get an error about @get_memory_info parameter, you need to update sp_WhoIsActive

## Components

The toolkit includes four scripts that should be executed in order:

1. **01 sp_WhoIsActive Logging Views.sql**: Creates the stored procedure that manages the views
2. **02 sp_WhoIsActiveLogging Main.sql**: Creates the main logging procedure
3. **03 sp_WhoIsActiveLogging_Retention.sql**: Creates the data retention procedure
4. **04 sp_WhoIsActive Logging Agent Job.sql**: Creates the SQL Agent job for automated collection

## Stored Procedures

### sp_WhoIsActiveLogging_Main

The main procedure that handles data collection and table management.

| Parameter Name | Data Type | Default Value | Description |
|----------------|-----------|---------------|-------------|
| @RetentionPeriod | integer | 10 | Number of days to keep data |

### sp_WhoIsActiveLogging_Retention

Handles the removal of tables older than the specified retention period.

| Parameter Name | Data Type | Default Value | Description |
|----------------|-----------|---------------|-------------|
| @RetentionPeriod | integer | 10 | Number of days to keep data |

### sp_WhoIsActiveLogging_CreateViews

Creates two views for data analysis (no parameters):
- **dbo.WhoIsActive**: UNION ALL of all WhoIsActive_YYYYMMDD tables
- **dbo.WhoIsActive_blocking**: Recursive CTE that traverses blocking chains

## Usage Examples

```sql
-- Run the main logging procedure with default retention (10 days)
EXECUTE dbo.sp_WhoIsActiveLogging_Main;

-- Run the main logging procedure with custom retention (30 days)
EXECUTE dbo.sp_WhoIsActiveLogging_Main
    @RetentionPeriod = 30;

-- Manually run the retention procedure to clean up old tables
EXECUTE dbo.sp_WhoIsActiveLogging_Retention
    @RetentionPeriod = 15;

-- Recreate the views (useful after adding new tables)
EXECUTE dbo.sp_WhoIsActiveLogging_CreateViews;
```

## Notes

- The scripts use the master database by default
- New tables are created daily with the format WhoIsActive_YYYYMMDD
- The Agent job runs on a one-minute schedule by default
- Views are automatically refreshed when new tables are created
- Old tables are automatically dropped based on the retention period

Copyright 2025 Darling Data, LLC  
Released under MIT license