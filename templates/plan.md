# <task id or title>

> Contract between the planner and the implementing model. The implementer has
> no prior context for this repo: everything needed is written here.

## Task
<one sentence>

## Read first
- `path/a` — why it matters
- `path/b` — why it matters

## Steps

### 1. <step name>
- File: `path/to/file`
- Signature: `function foo(a: A, b: B): C`
- Behaviour: <what it does; what it returns in each case>
- Test vectors:

  | input | expected |
  |---|---|
  | ... | ... |

## Acceptance criteria
- [ ] <verifiable by a command's output or by a single look at the diff>
- [ ] <verifiable by a command's output or by a single look at the diff>

## Quality gates
<copied from .ai-relay.json `gates` — the reviewer runs these, not you>

## Do NOT
- Touch files not listed above
- Add dependencies
- Modify existing tests
