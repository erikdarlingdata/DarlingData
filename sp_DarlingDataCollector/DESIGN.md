# DarlingDataCollector Design Document

## System Architecture

### Core Components

1. **Repository Database (DarlingData)**
   - Central storage for all collected metrics
   - Organized schemas for different data types
   - Efficient storage with columnstore indexes
   - Automatic retention management

2. **Collection Framework**
   - Modular collection procedures for different DMVs
   - Environment-aware (on-prem, Azure, AWS)
   - Version-compatible (SQL Server 2016+)
   - Minimal overhead design

3. **Analysis Framework**
   - Pattern recognition for common issues
   - Trend analysis over time
   - Correlation between different metrics
   - Root cause identification

4. **Diagnostics Framework**
   - Recommendation generation
   - Environment-specific suggestions
   - Actionable improvement steps
   - Impact assessment

### Data Flow

```
[SQL Server] --> [Collection Procedures] --> [Repository Database] --> [Analysis] --> [Diagnostics] --> [Recommendations]
```

## Database Schema

### Schemas

- **collection**: Raw collected metrics tables
- **analysis**: Derived analysis and pattern recognition tables
- **system**: Configuration, metadata, and control tables
- **maintenance**: Retention and cleanup related tables
- **reporting**: Views and functions for reporting

### Key Tables

**System Tables:**
- `system.dmv_coverage`: Tracks implementation of DMVs
- `system.server_info`: Information about the monitored server
- `system.settings`: Global system settings
- `system.version_history`: Component versions and updates

**Collection Tables:**
- `collection.wait_stats`: Raw wait statistics
- `collection.wait_stats_delta`: Calculated wait stat changes
- `collection.memory_clerks`: Memory clerk usage
- `collection.memory_summary`: Overall memory metrics
- `collection.schedulers`: CPU scheduler information
- `collection.io_file_stats`: File I/O statistics
- `collection.io_file_stats_delta`: I/O statistic changes
- `collection.query_stats`: Query performance metrics

*See schema definitions for complete table list*

## Collection Procedures

### Design Principles

1. **Modular**: One procedure per DMV collection
2. **Environment-aware**: Conditional logic for different environments
3. **Version-compatible**: Dynamic SQL to handle version differences
4. **Lightweight**: Minimal impact on production systems
5. **Robust**: Comprehensive error handling

### Core Collection Procedures

- `collection.collect_wait_stats`: Wait statistics collection
- `collection.collect_memory_clerks`: Memory usage collection
- `collection.collect_schedulers`: CPU/scheduler information
- `collection.collect_io_stats`: I/O performance metrics

### Collection Frequency

- **High Frequency (1-5 min)**: Wait stats, memory, CPU
- **Medium Frequency (15-30 min)**: I/O stats, query performance
- **Low Frequency (daily)**: Configuration, database properties

## SQL Agent Jobs

- **DarlingData - Wait Stats Collection**: Every 5 minutes
- **DarlingData - Memory Collection**: Every 5 minutes
- **DarlingData - CPU Collection**: Every 5 minutes
- **DarlingData - I/O Collection**: Every 15 minutes
- **DarlingData - Query Stats Collection**: Every 30 minutes
- **DarlingData - Maintenance**: Daily

## Implementation Phases

1. **Phase 1: Foundation**
   - Database creation script
   - Table schema implementation
   - Core collection framework
   - Basic maintenance procedures

2. **Phase 2: Core Metrics**
   - Wait stats collection
   - Memory collection
   - CPU collection
   - I/O collection

3. **Phase 3: Extended Metrics**
   - Query performance collection
   - Index usage collection
   - Blocking/Deadlock collection
   - Configuration collection

4. **Phase 4: Automation**
   - SQL Agent job setup
   - Scheduling framework
   - Monitoring and alerting

5. **Phase 5: Analysis Layer**
   - Standard reports
   - Performance dashboards
   - Trending and analysis procedures

## Environment-Specific Considerations

### SQL Server (On-premises/VM)
- Full access to all DMVs
- No special handling required

### Azure SQL Database
- Limited DMV access
- Special handling for `sys.dm_os_schedulers`
- Azure-specific DMVs: `sys.dm_exec_requests_history`, `sys.dm_user_db_resource_governance`

### Azure SQL Managed Instance
- Most DMVs available
- Some limitations similar to SQL DB

### AWS RDS
- Similar to on-premises for DMV access
- Limited system procedure access