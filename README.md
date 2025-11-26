# Workspace Manager

This is a CLI I'm building to help me manage [VS Code workspaces](https://code.visualstudio.com/docs/editing/workspaces/workspaces) and [git worktrees](https://git-scm.com/docs/git-worktree). An agent will be calling this CLI to setup these workspaces for me during the normal course of my work. Typically once a workspace is created I'll task the agent in that space to start working on something.

## Usage guide

### Quick setup

1. Make sure Ruby 3.2 or newer is available (`ruby -v`).
2. Optionally create a convenience alias so you can type `wm` anywhere:
	```bash
	alias wm="/path/to/workspace-manager/bin/workspace-manager"
	```
	Replace `/path/to/wm` with the location of this repository and add the alias to your shell profile to persist it.
3. Verify the CLI is reachable:
	```bash
	wm help
	```
4. Run the interactive setup wizard (once per machine) to create your config files:
	```bash
	wm setup
	```
	The wizard saves your answers to `~/.config/workspace-manager/config.json` and initializes `repos.json` for repository metadata.
	When prompted for *Search patterns*, you can supply combined glob entries such as `/Users/jonmagic/work/*, /Users/jonmagic/code/**/*, /Users/jonmagic/Dropbox/brain`.

### Typical workflow

1. **Initialize a session** – create a feature workspace, matching Git worktrees, and optional context folders:
	```bash
	wm init --feature "Checkout Flow" --folder brain repo-one repo-two
	```
2. **Inspect active work** – list recent sessions (limit or show active only as needed):
	```bash
	wm list --active --limit 5
	```
3. **Jump back into a session** – reopen the most recent workspace without re-entering the ID:
	```bash
	wm open --recent 1
	```
4. **Attach more repositories** – add extra worktrees or bring in standalone folders:
	```bash
	wm extend slug--repo-one --folder brain repo-three
	```
5. **Clean up when finished** – archive manifests/workspaces and remove worktrees:
	```bash
	wm prune slug--repo-one
	```
	Or, to permanently delete a session and all traces:
	```bash
	wm remove slug--repo-one
	```

### Command reference

| Command | Summary | Frequently used options |
| ------- | ------- | ----------------------- |
| `init` | Create a workspace for one or more repositories and prep matching worktrees. | `--feature NAME` *(required)*, `--primary NAME`, `--base main` or `repo:branch`, `--folder TOKEN` *(repeatable)*, `--notes TEXT`, `--checkout-existing`, `--dry-run`, `--no-open`, `--verbose` |
| `list` | Show recent sessions with optional filters and JSON output. | `--limit N`, `--active`, `--json`, `--reverse` |
| `open` | Resolve a session and launch VS Code or just print the workspace path. | `--session ID`, `--recent N`, `--print`, `--no-open` |
| `extend` | Attach additional repositories or folders to a session and create new worktrees as needed. | `--session ID`, repeatable `--base` overrides, `--folder TOKEN`, `--checkout-existing`, `--dry-run`, `--no-open`, `--verbose` |
| `prune` | Remove worktrees and archive session artifacts. | `--session ID`, `--dry-run` |
| `remove` | Permanently delete a workspace session, worktrees, and all traces. | `--session ID`, `--dry-run` |
| `config` | Print the current configuration JSON. | `--help` |
| `version` | Display the CLI version string. | — |
| `help` | Print the usage summary shown above. | — |

> 💡 `--folder` accepts either a direct path or any lookup token you already use for `wm init` repositories. We'll run it through your configured search patterns and add the resolved directory using its basename.

### Configuration

Configuration now lives entirely in JSON under `~/.config/workspace-manager/`:

| File | Purpose |
| ---- | ------- |
| `config.json` | Primary CLI settings (paths and search patterns). Created via `wm setup`. |
| `repos.json` | Optional repository metadata that other tools can populate. Created (empty) by `wm setup` if missing. |

`wm setup` walks you through the following questions and saves your answers to `config.json`:

```json
{
	"worktrees_root": "~/code/worktrees",
	"workspaces_root": "~/code/workspaces",
	"history_file": "~/.config/workspace-manager/history.json",
	"repo_config": "~/.config/workspace-manager/repos.json",
	"search": {
		"patterns": ["~/code/**/*"]
	}
}
```

Environment variables still override the same settings if needed:

| Setting | Environment variable |
| ------- | -------------------- |
| Worktrees root | `WORKSPACE_MANAGER_WORKTREES_ROOT` |
| Workspaces root | `WORKSPACE_MANAGER_WORKSPACES_ROOT` |
| History file | `WORKSPACE_MANAGER_HISTORY_FILE` |
| Repo registry file | `WORKSPACE_MANAGER_REPO_CONFIG` |
| Search patterns | `WORKSPACE_MANAGER_SEARCH_PATTERNS` |

If a required value is missing, commands will instruct you to run `wm setup` again.

Use `--dry-run` with any mutating command to see what would happen without touching the filesystem. Combine `--verbose` for detailed logging, including shell commands.

### Testing

Run the full test suite with:

```bash
bin/test
```

## Contributors

- [jonmagic](https://github.com/jonmagic)

## License

This project is licensed under the [ISC License](LICENSE).
