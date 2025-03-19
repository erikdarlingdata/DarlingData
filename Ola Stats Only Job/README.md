<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# Ola Stats Only Job

This directory contains a script to create a SQL Server Agent job for nightly statistics updates using Ola Hallengren's maintenance solution.

## Overview

Statistics in SQL Server are vital for query optimization but can become stale over time, leading to suboptimal query plans. This script sets up an automated job to update statistics on a regular schedule using Ola Hallengren's popular IndexOptimize stored procedure, focused specifically on statistics updates rather than the full index maintenance.

## Prerequisites

- Ola Hallengren's SQL Server Maintenance Solution must be installed
  - Download from: [https://ola.hallengren.com/downloads.html](https://ola.hallengren.com/downloads.html)
  - This script requires the version from 2018-06-16 or later, which includes the @StatisticsModificationLevel parameter

## Configuration Details

The script creates a SQL Agent job with the following default settings:
- Job name: "Nightly Stats Update Job via Ola"
- Database target: All user databases
- Job owner: sa
- Schedule: Every night at midnight
- Statistics modification level: 5% (only updates statistics that have changed by at least 5%)

## Customization Options

You may need to modify the script to:
- Change the target database (currently master)
- Change the job owner from sa
- Adjust the schedule from the default midnight run
- Set up failure emails and alerting
- Change the StatisticsModificationLevel from 5% to match your environment needs

## Usage

Simply run the script in SQL Server Management Studio after ensuring you have the prerequisites installed. The job will be created and scheduled automatically.

## Note

This script focuses exclusively on statistics updates. If you also need index reorganization or rebuilds, you should consider using Ola's full maintenance solution.

Copyright 2025 Darling Data, LLC  
Released under MIT license