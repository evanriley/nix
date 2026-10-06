---
description: Full workflow - scout gathers context, planner plans, worker implements, reviewer reviews
---
Use the subagent tool with the chain parameter to execute this workflow:

1. First, use the "scout" agent to find all code relevant to: $@
2. Then, use the "planner" agent to create an implementation plan for "$@" using the context from the previous step (use {previous} placeholder)
3. Then, use the "worker" agent to implement the plan from the previous step (use {previous} placeholder)
4. Finally, use the "reviewer" agent to review the uncommitted changes for: $@. Worker report: {previous}

Execute this as a chain, passing output between steps via {previous}. Report the reviewer's findings. Do not apply fixes until I say so.
