# Contributing to the Darling Data Repository

Welcome aboard! Thanks for taking the time to read this. I'll try to keep it short.

* [Reporting Bugs](#reporting-bugs)
* [Requesting Features](#requesting-features)
* [Working On Code](#working-on-code)
* [Code Standards](#code-standards)

If you're new to GitHub, here's an excellent guide on contributing by Rob Sewell: 
 * [How to fork a GitHub repository and contribute to an open source project](https://blog.robsewell.com/blog/how-to-fork-a-github-repository-and-contribute-to-an-open-source-project/)

## Reporting Bugs

Check out the [Github issues list], just in case someone already opened a similar issue. You should also check the [closed issues list], too, because I may have already fixed the issue.

You should use the template for reporting bugs, to provide as much detail as possible. All of my stored procedures should have a `@debug` parameter that can help you track down more detail, too.

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

Please make sure that you fork the **dev** branch, and all pull requests point to the **dev** branch, **not** the main branch.

## Code Standards

Your code needs to compile & run on all currently supported versions of SQL Server. 

I try to make things backwards compatible as far as I can, because I do run into client work on older versions, but I don't expect you to do that.

Your code should be set up to handle
* Case sensitivity
* Unicode object names

I have a particular formatting style that I stick to. You can code things however you are comfortable, but don't be surprised or angry if I format things my way.
* Trailing commas
* Spaces, not tabs
* Reasonable casing (not all upper, not all lower)
* Keywords on new lines (from, join, on, where, and, or, order by, group by)
* Indenting things appropriately
* Using AS in aliases
* Column aliases using the "column = expression" format
* Parentheses in TOP expressions, e.g. TOP (1000)
* Aligning parentheses 

Please make sure that you fork the **dev** branch, and all pull requests point to the **dev** branch, **not** the main branch.

[Github issues list]:https://github.com/erikdarlingdata/DarlingData/issues
[closed issues list]: https://github.com/erikdarlingdata/DarlingData/issues?q=is%3Aissue+is%3Aclosed
