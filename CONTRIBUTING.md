# Contributing to the Darling Data Repository

Welcome aboard! Thanks for taking the time to read this. I'll try to keep it short.

* [Reporting Bugs](#reporting-bugs)
* [Requesting Features](#requesting-features)
* [Working On Code](#working-on-code)
* [Code Standards](#code-standards)
* [Optional Local Test Check](#optional-local-test-check)

If you're new to GitHub, here's an excellent guide on contributing by Rob Sewell: 
 * [How to fork a GitHub repository and contribute to an open source project](https://blog.robsewell.com/blog/how-to-fork-a-github-repository-and-contribute-to-an-open-source-project/)

## Reporting Bugs

Check out the [Github issues list], just in case someone already opened a similar issue. You should also check the [closed issues list], too, because I may have already fixed the issue.

You should use the template for reporting bugs, to provide as much detail as possible. All of my stored procedures should have a `@debug` parameter that can help you track down more detail, too.

The [monthly releases](https://github.com/erikdarlingdata/DarlingData/releases) are the stable way to install. To try a fix before the next release, use the [dev-latest pre-release](https://github.com/erikdarlingdata/DarlingData/releases/tag/dev-latest). It holds the current dev build.

Please make sure that you fork the **dev** branch, and all pull requests point to the **dev** branch, **not** the main branch.

## Requesting Features

I fully encourage anyone who is interested in adding features or fixing bugs to do so. 

I also understand that working on someone else's code can be intimidating, so if you've got cold feet, just say so. I won't make fun of you, or your feet.

Likewise, please don't be disappointed if I don't want to spend time building a feature you suggest. 

As much as I'd like everyone to be happy with my tools, I work on them in my spare time, and can't do free development for everything and everyone.

Please make sure that you fork the **dev** branch, and all pull requests point to the **dev** branch, **not** the main branch.

## Working On Code

Please open an issue for any pull request that you're making. I do welcome all contributions, but I don't want you to do a bunch of work until we've hashed out the details.

There is a template for feature requests that asks some important questions, and it's usually a good idea to follow it.

I am guilty of not doing that at times, but it's my repo, and I abuse the issues feature a bit to make notes for myself.

Do not change `Install-All/DarlingData.sql` in a pull request, and do not run `Install-All/Merge-All.ps1` to update it. A GitHub Action rebuilds that file from the procedure files on **main** after each merge. The copy on **dev** is out of date on purpose. Change the procedure file in its own folder, and the build picks it up.

Please make sure that you fork the **dev** branch, and all pull requests point to the **dev** branch, **not** the main branch.

## Code Standards

Your code needs to compile & run on all currently supported versions of SQL Server. 

I try to make things backwards compatible as far as I can, because I do run into client work on older versions, but I don't expect you to do that.

Your code should be set up to handle
* Case sensitivity
* Unicode object names

I have a particular formatting style that I stick to. You can code things however you are comfortable, but don't be surprised or angry if I format things my way.

The full T-SQL style guide is in [CLAUDE.md](CLAUDE.md). Please read it. These are three of its rules:
* All SQL keywords in UPPERCASE (SELECT, FROM, WHERE, JOIN)
* All data types lowercase and never abbreviated (integer, not int)
* 4 spaces for each level of indentation (NEVER use tabs)

Please make sure that you fork the **dev** branch, and all pull requests point to the **dev** branch, **not** the main branch.

[Github issues list]:https://github.com/erikdarlingdata/DarlingData/issues
[closed issues list]: https://github.com/erikdarlingdata/DarlingData/issues?q=is%3Aissue+is%3Aclosed

## Optional Local Test Check

The repo has an optional pre-push hook. Before a push, it runs the test harness for each stored procedure folder that the push changes. It is off by default. If you do not turn it on, nothing changes for you.

Use a throwaway SQL Server for this check. The harnesses create and drop scratch databases, and some change server settings.

To turn it on, follow these steps:

1. Install Python 3 and the go-based `sqlcmd`, and put both on your `PATH`.
2. Set `DARLINGDATA_TEST_SERVER` to the host name of your test server. The hook logs in as `sa`.
3. Set `DARLINGDATA_TEST_PASSWORD` to the `sa` password. Do not put the password in a file in the repo.
4. In your clone, run `git config core.hooksPath .githooks`.

If either variable is not set, the hook prints one line and the push goes ahead. If you need extra `sqlcmd` options, such as `-C -N disable`, set `SQLCMD_CONN_ARGS`. To use a different `sqlcmd` binary, set `SQLCMD_BIN`.

On each push, the hook installs the changed procedure files into `master` on the test server. Then it runs the harness for each changed folder. A change to a Markdown file does not start a harness. A folder with no harness is skipped. If a harness fails, the push stops.

Only one hook run can use a given server at a time. If another run holds the server, the hook waits. After 15 minutes, it skips the check. To change the wait, set `DARLINGDATA_LOCK_WAIT` to a number of seconds.

To skip the check for one push, run `git push --no-verify`.
