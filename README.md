# Darling Data: SQL Server Troubleshooting Scripts
<a name="header1"></a>
![licence badge]

Navigatory

 - [Support](#support)
 
 - Scripts:
    - [sp_PressureDetector](#pressure-detector)
   - [sp_HumanEvents](#human-events)

## Who are these scripts for?
You need to troubleshoot problems with SQL Server, and you need to do it fast. 

You don't have time to track down a bunch of DMVs, figure out Extended Events, and you need to catch problems while they're happening. Finding out they happened later isn't cutting it anymore. 

These scripts aren't a replacement for a mature monitoring tool, but they do a pretty good job of capturing important issues. 


## Support
Right now, all support is handled on GitHub. Please be patient; it's just me over here answering questions. 

As far as compatibility goes, they only work on SQL Server 2012 and up. Older versions are either missing too much information, or simply aren't compatible (hello, Extended Events).

Questions about *how the scripts work* can be answered here. 

If you have questions about performance tuning, or SQL Server in general, you'll wanna hit a Q&A site:
 * [Top Answers](https://topanswers.xyz/databases)
 * [DBA Stack Exchange](https://dba.stackexchange.com/)

[*Back to top*](#header1)


## Pressure Detector
Is your client/server relationship on the rocks? A queries timing out, dragging along, or causing CPU fans to spin out of control?

All you need to do is hit F5 to get information about which queries are currently chewing up CPU, or eating through memory. 

You also get overall server CPU thread, and query memory utilization.

For a video walkthrough of the script and the results, [head over here](https://www.erikdarlingdata.com/sp_pressuredetector/).

There's only one parameter for this procedure: `@what_to_check`, so if you only want CPU or memory information, you can choose one or the other. 

Valid inputs for `@what_to_check`:
 * Both
 * CPU
 * Memory

[*Back to top*](#header1)


## Human Events

Extended Events are hard. You don't know which ones to use, when to use them, or how to get useful information out of them.

This procedure is designed to make them easier for you, by creating event sessions to help you troubleshoot common scenarios:
 * Blocking
 * Query performance
 * Compiles
 * Recompiles
 * Wait Stats

The default behavior is to run a session for a set period of time to capture information, but you can also set sessions up to data to permanent tables.

Misuse of this procedure can harm performance. Be very careful about introducing observer overhead, especially when gathering query plans. Be even more careful when setting up permanent sessions!

 * For a full, up-to-date description of the parameters and valid uses for this proc, use the `@help` parameter.
 * For a video walkthrough of the procedure, code, etc. there's a [YouTube playlist here](https://www.youtube.com/playlist?list=PLt4QZ-7lfQifgpvqsa21WLt-u2tZlyoC_).
 * For a text-based adventure, head to [my site here](https://www.erikdarlingdata.com/sp_humanevents/).

[*Back to top*](#header1)

[licence badge]:https://img.shields.io/badge/license-MIT-blue.svg
