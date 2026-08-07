# Adding a New AI CLI Preset

## Step 1: Create the Preset File

Create `presets/your-cli.json`:

```json
{
  "cli": "your-cli-binary",
  "flags": {
    "pre": "<subcommand or flags that must come first, e.g. 'run'>",
    "model": "<flag that selects the model, e.g. '-m', or empty>",
    "prompt": "<flags immediately before the prompt text>",
    "continue": "<flag to continue the last session, or empty>",
    "session": "<flag to specify a session id, or empty>",
    "workdir": "<flag to set the working directory, or empty>"
  }
}
```

All six `flags` keys are required — use an empty string for the ones your CLI
does not have. A schema test in `test/run-tests.sh` enforces this.

### Flag Guidelines

- `flags.pre`: words that must precede everything else. Use it for CLIs where the
  prompt is a subcommand — opencode needs `run` here. Leave empty otherwise.
- `flags.model`: the model-selection flag. The runner emits it only when the
  target defines a `model`. Leave empty for CLIs with no model switch.
- `flags.prompt`: flags that go immediately before the prompt string. For
  `kimi --print --final-message-only -p "prompt"`, use
  `"--print --final-message-only -p"`. If your CLI's prompt flag takes the text
  as its own argument (`-p <query>`), it must be the last word here.
- `flags.continue`: flag telling the CLI to continue the last session. Leave
  empty if not supported.
- `flags.session`: flag to specify a session id. Leave empty if not supported.
- `flags.workdir`: flag to set the working directory. Leave empty if the CLI
  uses `cwd` by default — the runner already `cd`s into the worktree.

Build order:

```
cli → pre → model <value> → prompt → prompt text → workdir <cwd> → continue → session <id>
```

Worked examples:

```bash
# commandcode: pre="", prompt ends with -p, no workdir flag
commandcode -m <model> --skip-onboarding --max-turns 100 --yolo -p "PROMPT"

# opencode: pre="run" (a subcommand), workdir="--dir"
opencode run -m <model> --auto "PROMPT" --dir /path/to/worktree

# kimi: no pre, no model flag
kimi --print --final-message-only -p "PROMPT" -w /path/to/worktree
```

### Non-interactive execution

The runner is invoked in the background with no TTY attached. If your CLI stops
to ask for permission, the run hangs forever instead of failing. Put whatever
flag skips that prompt into `flags.prompt` (`--yolo` for commandcode, `--auto`
for opencode). Isolation comes from the git worktree and the merge gate, not
from the CLI's own prompts.

## Step 2: Test It

Assert the command line without calling a real model:

```bash
./test/run-tests.sh
```

Then verify your flags actually exist:

```bash
your-cli --help
```

Do not leave a flag in a preset that does not appear in `--help`.

Finally, a live round:

```bash
./install.sh your-cli
# then, in Claude Code
/relay --quick "create a hello world script"
```

Verify:
- The CLI receives the prompt correctly
- `.relay_status` transitions: RUNNING -> DONE
- Changes appear in git log

## Step 3: Submit a PR

- Add your preset file to `presets/`
- Update the Presets table in `README.md`
- Include a brief description of the CLI and any quirks
