# Tekton Vision

Tekton is a self-hosted platform for running background AI coding agents at scale. The goal is to make it the default way engineering teams interact with AI for code — not a chatbot you talk to, but infrastructure that builds things for you.

## Roadmap

### P0 — Core platform (build next)

**Multi-Model Support** — Claude is the default agent, but the platform should support multiple AI providers. Each user connects their own API accounts (Claude, ChatGPT, Gemini, etc.), and Tekton auto-detects access based on their email. For overflow or users without their own keys, a shared pool routes through OpenRouter with model selection. Configuration is per-org: which models are available, which is the default, and spending limits per user/team.

**Elastic Infrastructure** — Hetzner and OVH bare metal servers are the primary compute backend. You configure a base fleet (e.g., 3 bare metal machines) and Tekton manages them as a pool. When demand exceeds capacity, it elastically provisions VPS instances (AWS, GCP, Hetzner Cloud, OVH Cloud) and runs NixOS VMs inside them. When demand drops, the elastic nodes are torn down. All of this is declarative in a config file: base fleet size, max elastic nodes, provider credentials, and scaling thresholds.

**Conversational Threads on PRs** — Every task has a conversation thread, similar to GitHub PR discussions. Anyone on the team can jump into a running task, add follow-up prompts, see the full history of every prompt and response, and see every preview URL that was generated along the way. The thread is the source of truth for what was asked, what was done, and what the result was.

**Real-Time Collaboration** — Everything happens in real-time via WebSockets. When one person sends a follow-up prompt, everyone watching sees it. When the agent writes code, everyone sees the logs stream. Use Operational Transformation for shared state — a central server determines ordering, which is fine since Tekton is the server. Multiple users can be active in the same task simultaneously.

**Draft / Plan Mode** — Before an agent starts coding, it can run in draft mode: it reads the codebase, proposes a plan (files to change, approach, tradeoffs), and publishes it as a draft. Team members can comment, suggest changes, or approve — just like a PR review, but for the plan itself. Only after approval does the agent start writing code. This prevents wasted compute, catches bad approaches early, and gives the team visibility into what's about to happen. Configurable per task: skip straight to coding for simple fixes, require plan approval for larger changes.

**Duplicate Work Detection** — An AI watcher monitors all active and recent prompts across the org in real-time. When someone submits a task that overlaps with something already in progress or recently completed, Tekton flags it: "Alice is already working on something similar in task X" or "This was addressed 2 days ago in PR #123." This prevents two people from unknowingly asking agents to do the same thing, saves compute, and surfaces opportunities to collaborate. The watcher uses embeddings over prompt + repo + file paths to detect semantic similarity, not just keyword matching.

### P1 — Multiplier features (high leverage)

**GitHub App Integration** — Beyond webhooks, Tekton becomes a GitHub App. Comment `/tekton fix this` on an issue and it picks up the task. Comment `/tekton address this feedback` on a PR review and it iterates. The conversational threads live both in Tekton and in GitHub — comments sync bidirectionally. This is what turns Tekton from a tool you go to into a tool that meets you where you already work.

**Agent Memory** — Each task currently starts from scratch. Instead, maintain a per-repo knowledge base that persists across tasks: architecture notes, conventions, past mistakes, debugging insights. When an agent starts a new task on a repo it's seen before, it gets this context injected automatically. The knowledge base grows with every task.

**Queue Management & Priority** — A proper job queue with priority levels (urgent, normal, background), fair scheduling across users, and preemption — high-priority tasks can bump low-priority ones when capacity is constrained. Visibility into queue depth and wait times.

**Task Scope Guardrails** — Not everything should be requestable as a task. Define per-org and per-repo policies that restrict what agents are allowed to do: for example, prevent agents from pushing directly to protected branches, running destructive commands, or performing operations outside the repo scope. Admins configure allowlists and denylists for agent capabilities (push, deploy, delete, etc.), and users see clear feedback when a request is blocked and why. This prevents accidental damage and gives teams confidence to grant broader access without fear of unintended side effects.

**Cost Tracking & Budgets** — With multiple API providers and elastic infrastructure, cost visibility is essential. Track token usage per task, compute time per container, and aggregate by user and team. Org admins set spending limits and get alerts. The dashboard shows burn rate, cost per merged PR, and trends over time.

### P2 — Polish & workflow (quality of life)

**Approval Gates** — Before an agent pushes or creates a PR, optionally pause and present the diff for human review. Configurable per repo or per team — some want full autonomy, others want a checkpoint. The approval can happen in the dashboard, in Slack, or via a GitHub review.

**Rollback / Undo** — One-click revert of everything an agent did: close the PR, delete the branch, destroy the preview, undo the commits. Clean, total undo. No manual cleanup.

**Notifications & Integrations** — Slack, Discord, and email notifications when tasks complete, fail, or need follow-up. Outgoing webhook events (task.completed, preview.ready, task.failed) that other systems can subscribe to for custom workflows.

**Task Templates & Playbooks** — Recurring patterns become reusable templates: "upgrade dependency X across all repos", "add an endpoint with tests", "fix this Sentry error". Users save prompt templates with variable slots. Repos can ship a `.tekton/playbooks/` directory with predefined tasks that show up in the UI, making common operations one-click.

### P3 — Intelligence & compliance

**Repo Onboarding & Scoring** — When Tekton first encounters a repo, run an automated analysis: language, framework, test coverage, CI setup, build system. Store this as metadata to give future agents better context and to estimate task complexity before it starts.

**Audit Log** — Every action, every prompt, every API call — who did what, when, and what happened. Essential for teams with compliance requirements, but also useful for debugging and understanding how the platform is being used.

### Backlog — Community feature requests

**Prompt Attribution** — Show which person submitted each prompt in the conversation thread. Every message in a task should display the author, so the full history reads like a real conversation with clear accountability.

**Image & Log Attachments in Prompts** — Allow pasting images and log files directly into prompts and follow-up messages. Agents should be able to consume these as context — e.g., paste a screenshot of a bug, paste error logs, and the agent uses them to debug.

**Persistent Task Logs** — Task logs in preview mode currently rely on a WebSocket connection that can die, and reloading the page loses the logs. Logs should be cached server-side and served from cache when the WebSocket reconnects or the page reloads, so you never lose visibility into what happened.

**Multiplayer Plan Mode** — Extend draft/plan mode into a full collaborative workflow. The agent publishes a plan with properly rendered Markdown. Team members can comment, request changes, and individually approve or reject the plan. Comments are fed back to the agent, which can regenerate the plan taking them into account (or not). Once approved, the agent executes the plan.

**In-Preview Console** — Add a terminal/console inside the preview environment so users can interact with the running deployment directly. Use case: spin up a service with a new feature, run `iex -S mix phx.server`, and manually test commands against it without leaving Tekton.

**Per-Project Environment Variables** — Allow configuring a set of environment variables per project, with the ability to add task-specific overrides. These env vars are available both to the AI agent while coding and in the preview console for manual testing.

**Task Name Reflects Current Work** — The task name/title should dynamically update to reflect what the agent is currently working on, so the task list gives an at-a-glance view of active work without needing to open each task.

**One-Click PR Creation** — Add a button to create a GitHub PR directly from a completed task. Pre-fill the PR title and description from the task context and conversation history, so shipping the result is one click away.

**Remove Update Button** — Remove the update button from the UI to simplify the interface and avoid accidental or confusing state changes.

**Branch Selector Dropdown** — Replace the plain text branch input with a proper dropdown that filters branches as you type and defaults to `main`. Makes it easier to target the right base branch when creating a task.

**Custom Task Naming** — Let users set a custom name for a task at creation time, instead of auto-generating one from the prompt. The task list should show meaningful names that the user chose.

**Show Originating Task on PR Push** — After the agent pushes a branch and shows the GitHub PR link, also display a link back to the Tekton task that originated the work, so there's full traceability between tasks and PRs.

**Fix Screenshot Capture** — Screenshots currently fail inside the Nix VM because the browser runs as root without `--no-sandbox`. Fix the sandboxing setup so automated screenshots work reliably in the VM environment.

**VM Startup Logs** — Surface Nix VM boot and startup logs in the UI so users can debug startup failures. When a VM fails to come up, the logs should be accessible from the task view rather than requiring SSH access to the host.

**Mark Task as Failed** — Add the ability to explicitly mark a task as failed. This gives a clear terminal state for tasks that didn't succeed, separate from "completed" or just abandoned, and helps with tracking success rates and debugging.

**Run Real-World Apps (Escolaria etc.)** — Support running full production-like applications (e.g., Escolaria) inside the preview environment. This means handling complex app setups with databases, dependencies, and services beyond simple dev servers.
