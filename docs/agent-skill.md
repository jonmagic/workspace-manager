# Workspace Manager Agent Skill

This document proposes an [AgentSkills.io](https://agentskills.io) skill definition to enable AI coding assistants (like GitHub Copilot or Claude Code) to manage VS Code workspaces and git worktrees using `workspace-manager`.

## Skill Definition

### Skill Name
`workspace-manager`

### Description
Manage VS Code workspaces and git worktrees for software development projects. This skill enables creating feature-based workspaces, rotating between branches, and managing workspace lifecycle.

### Capabilities

The workspace-manager skill provides the following capabilities:

1. **Initialize workspaces** – Create new workspace sessions with git worktrees for one or more repositories
2. **Rotate branches** – Switch all repositories in a workspace to a different branch while maintaining the same session
3. **Open workspaces** – Launch existing workspace sessions in VS Code
4. **List sessions** – View active and recent workspace sessions
5. **Extend workspaces** – Add repositories or folders to existing sessions
6. **Clean up** – Archive or permanently delete workspace sessions

## Example Prompts

### Creating a new workspace

**User:** "Create a workspace for the checkout flow feature using the frontend and backend repos"

**Agent should:**
1. Determine appropriate session name from "checkout flow"
2. Execute: `wm init --feature "Checkout Flow" frontend backend`
3. Confirm workspace was created and opened

### Rotating to a different branch

**User:** "Switch this workspace to work on the bugfix for issue 123"

**Agent should:**
1. Identify current workspace session (from VS Code context or recent history)
2. Execute: `wm rotate --session <current-session-id> --branch bugfix/issue-123 --create --base main`
3. Confirm rotation completed successfully

**User:** "Start working on the user authentication feature across api-server and web-client"

**Agent should:**
1. Execute: `wm rotate --session <current-session-id> --branch feature/user-auth --create`
2. If session doesn't exist, use `wm init` instead

### Opening an existing workspace

**User:** "Open my most recent workspace"

**Agent should:**
Execute: `wm open --recent 1`

**User:** "Open the workspace for the checkout flow"

**Agent should:**
1. List sessions to find matching name: `wm list --json`
2. Execute: `wm open --session <matched-session-id>`

### Managing workspace lifecycle

**User:** "I'm done with the checkout flow feature, clean it up"

**Agent should:**
1. Identify the session for "checkout flow"
2. Ask for confirmation about archiving vs. deleting
3. If archiving: `wm prune <session-id>`
4. If deleting: `wm remove <session-id>`

### Adding repositories to workspace

**User:** "Add the database-migrations repo to my current workspace"

**Agent should:**
1. Identify current session
2. Execute: `wm extend <session-id> database-migrations`

### Listing workspaces

**User:** "What workspaces do I have active?"

**Agent should:**
Execute: `wm list --active` and present results in a readable format

## Command Reference

### Core Commands

#### `wm init`
Create a new workspace session with worktrees.

**Required:**
- `--feature NAME` – Feature or story name

**Common options:**
- `--primary NAME` – Primary repository anchor
- `--base BRANCH` – Base branch (default: main)
- `--folder PATH` – Add standalone folder
- `--notes TEXT` – Prefill notes
- `--no-open` – Don't launch VS Code

**Example:**
```bash
wm init --feature "User Authentication" --base develop api-server web-client
```

#### `wm rotate`
Rotate workspace to a different branch across all repositories.

**Required:**
- `--session ID` – Session identifier
- `--branch NAME` – Target branch name

**Common options:**
- `--create` – Create the branch if it doesn't exist
- `--base BRANCH` – Base branch for new branches
- `--no-open` – Don't reopen VS Code

**Example:**
```bash
wm rotate --session checkout-flow--frontend --branch bugfix/issue-123 --create --base main
```

#### `wm open`
Launch an existing workspace session.

**Options:**
- `--session ID` – Session identifier
- `--recent N` – Open Nth most recent session (1 = latest)
- `--print` – Print path without launching

**Example:**
```bash
wm open --recent 1
```

#### `wm list`
Display workspace sessions.

**Options:**
- `--active` – Show only active sessions
- `--limit N` – Limit results
- `--json` – JSON output
- `--reverse` – Reverse chronological order

**Example:**
```bash
wm list --active --limit 5
```

#### `wm extend`
Add repositories or folders to an existing session.

**Required:**
- Session identifier (positional or `--session`)
- Repository names or `--folder` paths

**Example:**
```bash
wm extend checkout-flow--frontend database-migrations --folder ~/docs/specs
```

#### `wm prune`
Archive workspace session and remove worktrees.

**Required:**
- Session identifier

**Example:**
```bash
wm prune checkout-flow--frontend
```

#### `wm remove`
Permanently delete workspace session and all traces.

**Required:**
- Session identifier

**Example:**
```bash
wm remove old-experiment--backend
```

## Safety Checks and Confirmations

### When to prompt for confirmation:

1. **Destructive operations** – Always confirm before `wm remove`
   - Show what will be deleted
   - Ask "Are you sure you want to permanently delete this workspace?"

2. **Session conflicts** – When rotating to a branch that already has active work
   - Inform user about existing branch state
   - Suggest using `--create` if needed

3. **Workspace ambiguity** – When feature name matches multiple sessions
   - List matching sessions
   - Ask which one to use

### When to proceed automatically:

1. **Creating new workspaces** – `wm init` can proceed if feature name is clear
2. **Opening workspaces** – `wm open` is safe to run
3. **Listing sessions** – `wm list` is always safe
4. **Archiving** – `wm prune` is safe as it preserves data in archive

### Error handling:

1. **Missing configuration** – If `wm` errors about missing config:
   - Inform user they need to run `wm setup` first
   - Don't try to fix configuration automatically

2. **Repository not found** – If workspace-manager can't locate a repository:
   - Suggest checking the repository name
   - Recommend verifying search patterns in config

3. **Command failures** – If any command fails:
   - Show the error message
   - Suggest using `--dry-run` to preview changes
   - Recommend checking `--help` for command options

## Advanced Patterns

### Serial branch work (rotating branches)

For developers working on multiple features serially in the same workspace:

1. Create initial workspace: `wm init --feature "Sprint Planning" repo-a repo-b`
2. Work on feature, then rotate: `wm rotate --session sprint-planning--repo-a --branch feature/user-story-1 --create`
3. Complete feature, rotate to next: `wm rotate --session sprint-planning--repo-a --branch feature/user-story-2 --create`
4. Continue rotating through stories without creating new workspace sessions

This pattern maintains one workspace session with rotation history tracked in the manifest.

### Multi-repository coordination

When features span multiple repositories:

1. Start with primary repos: `wm init --feature "Payment Integration" api-server web-client`
2. Add supporting repo later: `wm extend payment-integration--api-server payment-gateway`
3. All repos can be rotated together: `wm rotate --session payment-integration--api-server --branch hotfix/payment-bug --create`

### Workspace cleanup workflow

Help users maintain clean workspace environments:

1. List active sessions: `wm list --active`
2. Identify completed work
3. Archive old sessions: `wm prune <session-id>` for each completed item
4. Delete experiments: `wm remove <session-id>` for abandoned work

## Integration Tips

### VS Code context awareness

When possible, detect the current VS Code workspace:
- Check environment variable `WORKSPACE_FOLDER` or similar
- Parse `.code-workspace` file to extract session ID
- Use this to infer session ID for rotate/extend commands

### Repository name resolution

workspace-manager uses configured search patterns to locate repositories. Suggest:
- Using exact repository names from user's file system
- Checking `wm list --json` output for active repo names
- Referring to common repository naming patterns

### Dry-run preview

For complex operations, suggest using `--dry-run` first:
```bash
wm rotate --session my-session --branch new-feature --create --dry-run
```
Then execute without `--dry-run` if the user confirms.

## Worktrunk Support

workspace-manager integrates with [Worktrunk](https://github.com/Danie1/worktrunk) when available:
- Automatically uses `wt` commands if installed
- Falls back to `git worktree` if not available
- No special flags needed – integration is automatic

Benefits when Worktrunk is available:
- Simplified branch switching
- Better worktree path management
- Cleaner branch lifecycle

## Future Enhancements

Potential areas for workspace-manager to expand:

1. **Template support** – Predefined workspace templates for common project types
2. **Cloud sync** – Sync workspace configurations across machines
3. **Team sharing** – Share workspace definitions with team members
4. **Branch strategy integration** – Integrate with git flow, GitHub flow patterns
5. **CI/CD awareness** – Track deployment status per workspace branch

## References

- [workspace-manager repository](https://github.com/jonmagic/workspace-manager)
- [VS Code Multi-root Workspaces](https://code.visualstudio.com/docs/editor/multi-root-workspaces)
- [Git Worktrees documentation](https://git-scm.com/docs/git-worktree)
- [Worktrunk](https://github.com/Danie1/worktrunk)
- [AgentSkills.io](https://agentskills.io)
