<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# sp_LogHunter

The SQL Server error log can have a lot of good information in it about what's going on, whether it's right or wrong.

The problem is that it's hard to know *what* to look for, and what else was going on once you filter it.

It's another notoriously bad Microsoft GUI, just like Query Store and Extended Events.

I created sp_LogHunter to search through your error logs for the important stuff, with some configurability for you, and return everything ordered by log entry time.

It helps you give you a fuller, better picture of any bad stuff happening.

## Parameters

|    parameter_name    | data_type |                  description                   |                                 valid_inputs                                 |   defaults   |
|----------------------|-----------|------------------------------------------------|------------------------------------------------------------------------------|--------------|
| @days_back           | integer   | how many days back you want to search the logs | an integer; will be converted to a negative number automatically             | -7           |
| @start_date          | datetime  | if you want to search a specific time frame    | a datetime value                                                             | NULL         |
| @end_date            | datetime  | if you want to search a specific time frame    | a datetime value                                                             | NULL         |
| @custom_message      | nvarchar  | if you want to search for a custom string      | something specific you want to search for. no wildcards or substitions.      | NULL         |
| @custom_message_only | bit       | only search for the custom string              | NULL, 0, 1                                                                   | 0            |
| @first_log_only      | bit       | only search through the first error log        | NULL, 0, 1                                                                   | 0            |
| @language_id         | integer   | to use something other than English            | SELECT DISTINCT m.language_id FROM sys.messages AS m ORDER BY m.language_id; | 1033         |
| @help                | bit       | how you got here                               | NULL, 0, 1                                                                   | 0            |
| @debug               | bit       | dumps raw temp table contents                  | NULL, 0, 1                                                                   | 0            |
| @version             | varchar   | OUTPUT; for support                            | OUTPUT; for support                                                          | none; OUTPUT |
| @version_date        | datetime  | OUTPUT; for support                            | OUTPUT; for support                                                          | none; OUTPUT |

## Examples

```sql
-- Basic execution to search the last 7 days of error logs
EXECUTE dbo.sp_LogHunter;

-- Search logs for the last 30 days
EXECUTE dbo.sp_LogHunter
    @days_back = -30;

-- Search a specific time period
EXECUTE dbo.sp_LogHunter
    @start_date = '2025-01-01 00:00:00',
    @end_date = '2025-01-02 00:00:00';

-- Search for a specific custom message
EXECUTE dbo.sp_LogHunter
    @custom_message = 'login failed';

-- Only search for the custom message, ignore other errors
EXECUTE dbo.sp_LogHunter
    @custom_message = 'login failed',
    @custom_message_only = 1;

-- Only search the current error log
EXECUTE dbo.sp_LogHunter
    @first_log_only = 1;
```

## Resources
* [YouTube introduction](https://youtu.be/L_yJ6zPjHfs)