# /relay — AI CLI Task Delegation

Analyze the user's task and delegate it to the configured AI CLI.

## Input
$ARGUMENTS — task description from the user

## Configuration

Read `.ai-relay.json` in the project root for CLI name, flags, and settings.
If the file doesn't exist, tell the user to run install.sh first.

## Workflow

### Step 1: Analyze and Prepare Prompt
1. Analyze the task — which files are affected, what kind of change
2. Read the relevant existing code
3. Prepare a detailed prompt for the target AI CLI. The prompt should include:
   - Project context (language, framework, test runner, style rules)
   - Clear task description
   - Files to be modified and their current contents
   - Existing pattern examples (test patterns, import style, etc.)
   - What NOT to do
   - Instruction to git commit when done

Use this prompt template:

```
## Task
[Clear, one-sentence task description]

## Project Info
- [Language/runtime details]
- [Test framework]
- [Style conventions]
- [Framework]

## Files to Modify
1. `path/to/file.js` — [what to do]
2. `path/to/file.test.js` — [what to do]

## Existing Code (Reference)
[Current contents or pattern examples from relevant files]

## Rules
- Only touch the specified files
- Minimal comments (1 line at file top is enough)
- Git add + git commit when done

## Do NOT
- Create other files
- Break existing tests
- Add unnecessary dependencies
```

### Step 2: Execute AI CLI
Read the config and run:
```bash
./relay-run.sh "PREPARED_PROMPT"
```

### Step 3: Wait for Completion
Check the status file (configured in `.ai-relay.json`, default `.relay_status`):
```bash
cat .relay_status
```

- RUNNING — wait 10 seconds, then check again. After 10 minutes total, abort and report timeout to user.
- DONE — proceed to Step 4
- FAILED — inform the user, check error logs

### Step 4: Review
```bash
git log --oneline -3
git diff HEAD~1 HEAD
git diff --name-only HEAD~1 HEAD
```

Review the changes:
- Is the code style correct?
- Are tests present and sensible?
- Any security issues?
- Any unnecessary file changes?

### Step 5: Report
Inform the user:
- What changed (file list + summary)
- Any errors or risks
- Whether approval or fixes are needed

### Error Correction (Max retries from config, default 3)
If issues are found during review:
1. Clearly describe the problem
2. Prepare a fix prompt (only the problematic part)
3. `./relay-run.sh "fix prompt" --continue` (continues the session)
4. Review again

If not fixed after max retries, give the user a status report.

### Step 6: Quality Gate (After All Tasks Complete)

Read `hooks.post_review` from `.ai-relay.json`. If it is set (non-empty):

1. Run the configured post-review hook (e.g., `/simplify`, security review)
2. Collect findings and prioritize (critical > high > medium)
3. If critical/high findings exist, delegate fixes:
   ```bash
   ./relay-run.sh "FIX_PROMPT" --continue
   ```
   - Include findings list and which files need fixing
   - Review again after fix (max 2 rounds)
4. If clean — inform user: "Quality gate passed, ready to push"

If `hooks.post_review` is empty or not set, skip this step.

## Session Strategy

| Scenario | Command | Description |
|----------|---------|-------------|
| New task | `./relay-run.sh "prompt"` | Start fresh session |
| Fix (same task) | `./relay-run.sh "fix" --continue` | Continue last session |
| Specific session | `./relay-run.sh "prompt" --continue session_id` | Resume by session ID |
