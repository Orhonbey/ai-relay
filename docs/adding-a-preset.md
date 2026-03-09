# Adding a New AI CLI Preset

## Step 1: Create the Preset File

Create `presets/your-cli.json`:

```json
{
  "cli": "your-cli-binary",
  "flags": {
    "prompt": "<flags before prompt text>",
    "continue": "<flag to continue session, or empty>",
    "session": "<flag to specify session ID, or empty>",
    "workdir": "<flag to set working directory, or empty>"
  },
  "max_retries": 3,
  "status_file": ".relay_status",
  "hooks": {
    "post_review": ""
  }
}
```

### Flag Guidelines

- `flags.prompt`: Flags that go between the CLI name and the prompt string. Example: for `kimi --print --final-message-only -p "prompt"`, use `"--print --final-message-only -p"`.
- `flags.continue`: Flag to tell the CLI to continue the last session. Leave empty (`""`) if not supported.
- `flags.session`: Flag to specify a session ID. Leave empty if not supported.
- `flags.workdir`: Flag to set the working directory. Leave empty if the CLI uses `cwd` by default.

## Step 2: Test It

```bash
# Install with your preset
./install.sh your-cli

# Test in Claude Code
/relay "create a hello world script"
```

Verify:
- The CLI receives the prompt correctly
- `.relay_status` transitions: RUNNING -> DONE
- Changes appear in git log

## Step 3: Submit a PR

- Add your preset file to `presets/`
- Update the Presets table in `README.md`
- Include a brief description of the CLI and any quirks
