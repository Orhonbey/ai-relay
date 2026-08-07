---
name: ai-relay
description: Use when a coding task should be planned with the user and then implemented by another AI CLI (CommandCode, Opencode, Kimi, Codex, Aider) instead of by Claude directly - plans the work, dispatches it to a chosen model in an isolated worktree, verifies the result against objective quality gates, feeds corrections back, and escalates to another model when the gates cannot be met.
---

# ai-relay

Plan-driven task delegation across AI CLIs.

Read `relay.md` in this skill directory and follow it. It defines the six-phase
loop: plan with the user, dispatch to a target model, run the quality gates
yourself, feed structured corrections back, escalate to another model on
repeated failure, and merge only after the user approves.

The plan template is `templates/plan.md`.

**The two rules that matter most:**

1. Never accept a model's claim that a gate passed. Run the gate command
   yourself and read the output.
2. Never write the plan alone. Every real technical choice goes to the user as a
   multiple-choice question first.
