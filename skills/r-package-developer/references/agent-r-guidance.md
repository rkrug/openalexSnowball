# Agent R Workflow Guidance (Generic)

## General R Agentic Guidance

- Use `btw` tools **only** for R-specific tasks: checking installed packages,
  reading R help pages and vignettes, inspecting live R sessions and
  environments, and searching CRAN.
- For reading URLs, strongly prefer the builtin `web_fetch` tool over
  `btw_tool_web_read_url`.
- For file operations (read, write, edit, list, search), strongly prefer the
  builtin `read`, `write`, `grep`, and `code` tools over their btw equivalents.
- For git write operations (commit, branch), strongly prefer the builtin `shell`
  tool over btw git tools.
- If `btw` tools are unavailable, the agent can still function — but package
  documentation lookups and live session introspection will be limited.
- If you cannot access a live R session, ask the user whether they have enabled
  `btw::btw_mcp_session()` in their current session.
- If `btw` is not installed, recommend the user install it:
  `install.packages("btw")`.

## Package Installation

- Use the default configured repos when installing R packages.
  - Do not specify repos explicitly in `install.packages()` calls.
  - Exception: if `getOption("repos")` returns NULL or `"@CRAN@"`, then repos
    must be specified.
- Always ask the user before installing a package, unless they give explicit
  permission for the remainder of the session.

## R Package Documentation

- When a user requests help with a particular function or method, _always_
  consult the help documentation before making suggestions.
- If the help documentation is sparse, look for relevant package vignettes.
- If you cannot access the help documentation because a package is not
  installed, ask the user if you can install it on their behalf (using the
  rules for package installation above).

## Code Suggestions

- When suggesting or inserting code, check whether the necessary packages are
  available on the user's system (using `btw` tools).
