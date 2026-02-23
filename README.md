# Claude Squad (claude-squad)

A portable agent team configuration for Claude Code. Drop it into any project's `.claude/` directory to get a full software development team — PM, BA, Architect, specialized developers, DevOps engineers, and QA.

## Quick Start

```bash
# Clone the repo
git clone https://github.com/kanoonth/claude-squad.git

# Interactive install — pick your stack
./setup.sh /path/to/your/project

# Or specify agents directly (for CI/scripting)
./setup.sh /path/to/your/project --agents dev-rails,devop-flyio

# Update an existing installation after git pull
./setup.sh /path/to/your/project --update

# Customize your BA's domain knowledge
# Edit /path/to/your/project/.claude/agents/ba-agent.md

# Start building
# In Claude Code, run:
/pipeline Add user authentication with email and Google OAuth
```

### Interactive Picker

Running `./setup.sh /path/to/project` launches an interactive menu:

```
╔══════════════════════════════════════════════════╗
║  claude-squad installer                          ║
╚══════════════════════════════════════════════════╝

Core team (always installed):
  + pipeline-agent
  + pm-agent
  + ba-agent
  + designer-agent
  + architect-agent
  + integration-agent
  + qa-agent

Select dev stack(s) — at least one:
  [1]   dev-rails          Ruby on Rails developer — models, controllers, migrations, RSpec
  [2]   dev-react          React developer — components, hooks, Next.js, testing with RTL
  [3]   dev-flutter        Flutter developer — widgets, state management, platform channels
  [4]   dev-node           Node.js developer — Express/NestJS, TypeScript, Prisma
  [5]   dev-odoo           Odoo developer — modules, ORM, views, QWeb templates
  [6]   dev-salesforce     Salesforce developer — Apex, LWC, SOQL, triggers
  [7]   dev-webflow        Webflow developer — site structure, CMS, interactions, custom code
  [8]   dev-astro          Astro developer — islands architecture, content collections, SSR/SSG
  [9]   dev-payload-cms    Payload CMS developer — collections, admin UI, REST/GraphQL API

Enter numbers (comma-separated, e.g. 1,4): 1,4

Select infrastructure (optional — press Enter to skip):
  [1]   devop-aws          AWS — Terraform, CDK, CloudFormation
  [2]   devop-azure        Azure — Terraform, Bicep, AKS
  [3]   devop-gcloud       GCloud — Terraform, Cloud Run, GKE
  [4]   devop-firebase     Firebase — Firestore, Auth, Cloud Functions
  [5]   devop-flyio        Fly.io — machines, volumes, regions

Enter numbers (comma-separated, press Enter to skip): 5

Configure Fizzy sync? (y/N): n

Agent count (press Enter to keep default):
  dev-rails [1]: 2
  dev-node [1]:
  devop-flyio [1]:

Summary:
  Agents: 10 (7 core + dev-rails dev-node devop-flyio)
  Skills: 44 (deduped)
  Counts:
    dev-rails            x2
    dev-node             x1
    devop-flyio          x1

Install to /path/to/project/.claude? [Y/n]:
```

Only the agents you select (plus the core team) get installed. Skills are automatically resolved from each agent's frontmatter and deduped.

### Non-interactive Mode

Use `--agents` for scripting or CI:

```bash
./setup.sh /path/to/project --agents dev-rails
./setup.sh /path/to/project --agents dev-rails,dev-node,devop-flyio
```

### Agent Count

In interactive mode, after selecting agents you're prompted for the count of each one individually. The default shown in brackets is the existing count (or `1` for new agents):

```
Agent count (press Enter to keep default):
  dev-rails [1]: 2
  devop-flyio [1]:
```

This lets you run 2 Rails devs in parallel while keeping 1 Fly.io devop.

For non-interactive mode, `--count` sets a blanket count for all newly selected agents:

```bash
./setup.sh /path/to/project --agents dev-rails,devop-flyio --count 2
```

Core agents (Pipeline, PM, BA, Designer, Architect, Integration, QA) always stay at count 1.

### List Available Agents

```bash
./setup.sh --list
```

Shows all agents with their skill counts and total knowledge-base line counts.

### Adding More Agents Later

Re-run `setup.sh` to add agents on top of an existing installation. Previously installed agents and their counts are detected and preserved — new selections are merged in:

```bash
# Initial install with 2 Rails devs
./setup.sh /path/to/project --agents dev-rails --count 2

# Later, add Node.js — Rails stays installed with count 2
./setup.sh /path/to/project --agents dev-node
```

In interactive mode, already-installed agents are marked with `*` and the count prompt shows existing values as defaults.

### Updating Installed Configs

After updating claude-squad (e.g., `git pull`), sync changes into your project:

```bash
# Shorthand via setup.sh
./setup.sh /path/to/project --update
./setup.sh /path/to/project --update --dry-run

# Or call the update script directly
./scripts/update.sh /path/to/project

# Show what changed (safe — no modifications)
./scripts/update.sh /path/to/project --dry-run

# Update a specific category
./scripts/update.sh /path/to/project agents
./scripts/update.sh /path/to/project skills
./scripts/update.sh /path/to/project pipeline
./scripts/update.sh /path/to/project hooks
./scripts/update.sh /path/to/project scripts

# Sync all files including ones not yet installed
./scripts/update.sh /path/to/project --all
```

The update script only touches files that already exist in your project (unless `--all` is used). For each changed file it shows a colored diff and asks for confirmation:

```
.claude/agents/pm-agent.md has local changes:
--- current
+++ claude-squad
@@ -3,4 +3,6 @@
+### 3. Epic Grouping Rules
+Group related tasks into named **epics**...

Apply update? [y/N/v] (y=yes, N=no, v=view full file)
```

## What's Included

### Agents (22 in catalog, 21 installable)

| Agent | Role | Skills | Description |
|-------|------|--------|-------------|
| `pipeline-agent` | Orchestrator | — | Coordinates the full PM → BA → Designer → Architect → Dev → Integration → QA pipeline |
| `pm-agent` | Planning | 4 | Drafts phase plans and task breakdowns |
| `ba-agent` | Planning | 4 | Adds domain detail, scope, acceptance criteria (customizable) |
| `designer-agent` | Planning | 1 | Creates ASCII wireframes and UI layout annotations for frontend tasks |
| `architect-agent` | Planning | 6 | Technical feasibility, system design, API design, integration review |
| `integration-agent` | Integration | 5 | Writes E2E tests, syncs docs, validates cross-feature integration |
| `dev-rails` | Dev | 6 | Ruby on Rails (ActiveRecord, RSpec, Rubocop) |
| `dev-react` | Dev | 6 | React (components, hooks, Next.js, RTL) |
| `dev-flutter` | Dev | 10 | Flutter (widgets, Riverpod, Firebase, maps, platform channels) |
| `dev-node` | Dev | 6 | Node.js (Express/NestJS, TypeScript, Prisma) |
| `dev-odoo` | Dev | 6 | Odoo (modules, ORM, views, QWeb) |
| `dev-salesforce` | Dev | 6 | Salesforce (Apex, LWC, SOQL, triggers) |
| `dev-webflow` | Dev | 6 | Webflow (Designer, CMS, IX2 Interactions, custom code) |
| `dev-astro` | Dev | 6 | Astro (islands architecture, content collections, SSR/SSG) |
| `dev-payload-cms` | Dev | 6 | Payload CMS (collections, admin UI, REST/GraphQL API) |
| `devop-aws` | DevOps | 11 | AWS (Terraform, CDK, CloudFormation) |
| `devop-azure` | DevOps | 11 | Azure (Terraform, Bicep, AKS) |
| `devop-gcloud` | DevOps | 11 | Google Cloud (Terraform, Cloud Run, GKE) |
| `devop-firebase` | DevOps | 9 | Firebase + Terraform for GCP resources |
| `devop-flyio` | DevOps | 9 | Fly.io + Terraform for supporting infrastructure |
| `qa-agent` | QA | 8 | Verifies implementations against acceptance criteria |
| `skill-tester-agent` | Testing | — | Evaluates skill quality (dev-only, not installed by setup.sh) |

The 7 core agents (pipeline, pm, ba, designer, architect, integration, qa) are always installed. You select which dev and devop agents to include.

### Skills (93)

Each agent loads only its relevant skills, keeping context windows lean. Skills are organized by domain:

**Pipeline Skills (3):**
- `/pipeline` — Launch the development pipeline
- `/pipeline-status` — Show kanban board and progress
- `/review` — Code review for quality, security, correctness

**Dev Skills (42)** — 4-8 per stack + 2 cross-cutting:
- Rails: `rails-models`, `rails-controllers`, `rails-performance`, `rails-testing`
- React: `react-architecture`, `react-state`, `react-testing`, `react-ui`
- Flutter: `flutter-architecture`, `flutter-networking`, `flutter-testing`, `flutter-ui`, `flutter-firebase`, `flutter-platform`, `flutter-localization`, `flutter-maps`
- Node.js: `node-architecture`, `node-api`, `node-testing`, `node-performance`
- Odoo: `odoo-models`, `odoo-views`, `odoo-backend`, `odoo-testing`
- Salesforce: `salesforce-apex`, `salesforce-lwc`, `salesforce-integration`, `salesforce-testing`
- Webflow: `webflow-structure`, `webflow-cms`, `webflow-interactions`, `webflow-testing`
- Astro: `astro-architecture`, `astro-content`, `astro-components`, `astro-testing`
- Payload CMS: `payload-collections`, `payload-admin`, `payload-api`, `payload-testing`
- Cross-cutting: `git-workflow`, `code-review-practices`

**Infrastructure Skills (18)** — 3-4 per cloud:
- AWS: `aws-compute`, `aws-data`, `aws-security`, `aws-operations`
- Azure: `azure-compute`, `azure-data`, `azure-networking`, `azure-operations`
- GCloud: `gcloud-compute`, `gcloud-data`, `gcloud-security`, `gcloud-operations`
- Firebase: `firebase-backend`, `firebase-security`, `firebase-operations`
- Fly.io: `flyio-core`, `flyio-deploy`, `flyio-operations`

**Shared DevOps Skills (7):**
- CI/CD: `devops-cicd`, `devops-containers`, `devops-monitoring`
- IaC: `terraform-patterns`, `kubernetes-patterns`
- Operations: `observability-practices`, `incident-management`

**QA Skills (8):**
- Core: `testing-verification`, `testing-specialized`, `testing-fundamentals`, `testing-strategies`
- Specialized: `playwright-testing`, `performance-testing`, `accessibility-testing`, `chaos-engineering`

**Planning Skills (15):**
- PM: `task-planning`, `task-estimation`, `agile-frameworks`, `stakeholder-communication`
- BA: `domain-modeling`, `domain-requirements`, `requirements-elicitation`, `process-modeling`
- Designer: `ui-wireframing`
- Architect: `design-patterns`, `design-review`, `architecture-documentation`, `security-architecture`, `api-design`, `api-security`

## Pipeline Flow

```
Feature Request / BRD
  │
  ▼
┌─────────────────────────────────────┐
│  PLANNING PHASE                      │
│                                      │
│  PM → drafts phases + tasks          │
│   ↓                                  │
│  BA → reviews, adds domain detail    │
│   ↓                                  │
│  Designer → ASCII wireframes for UI  │
│   ↓                                  │
│  PM → revises based on feedback      │
│   ↓                                  │
│  Architect → technical review        │
│   ↓                                  │
│  BA → updates from architect input   │
│   ↓                                  │
│  User → approves final plan          │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  IMPLEMENTATION PHASE                │
│                                      │
│  Tasks routed by tags:               │
│    [backend, rails]  → dev-rails     │
│    [frontend, react] → dev-react     │
│    [devops, aws]     → devop-aws     │
│                                      │
│  Parallel execution where possible   │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  INTEGRATION PHASE                   │
│                                      │
│  Integration agent:                  │
│    • Writes/updates E2E tests        │
│    • Syncs CHANGELOG, README, docs   │
│    • Validates cross-feature links   │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  VERIFICATION PHASE                  │
│                                      │
│  QA verifies each task against AC    │
│  Bugs routed back to dev agents      │
│  Phase complete when all tasks pass  │
└─────────────────────────────────────┘
```

## Customization

### Customize the BA

Edit `.claude/agents/ba-agent.md` and fill in the "Domain Context" section:

```markdown
## Domain Context

You are an expert in **insurance technology**. You understand:
- Policy lifecycle: quote → bind → issue → renew → cancel
- Claims processing: FNOL → investigation → adjudication → settlement
- Underwriting rules and risk assessment
- Regulatory compliance (state-specific regulations)
- Integration with rating engines and payment processors
```

### Adjust Pipeline Settings

Edit `.claude/pipeline/config.json`:

```json
{
  "planning": {
    "maxIterations": 3,        // Max planning loop iterations
    "requireUserApproval": true // Always ask before implementing
  },
  "implementation": {
    "parallel": true,           // Run dev tasks in parallel
    "maxConcurrent": 3          // Max concurrent agents
  }
}
```

### Fizzy Sync

Optionally sync your task board to a [Fizzy](https://fizzy.do) kanban board. See [docs/fizzy-setup.md](docs/fizzy-setup.md) for a full deployment guide (Fly.io). Configure during setup or reconfigure anytime with `--fizzy`:

```bash
# During install:
./setup.sh /path/to/project --agents dev-rails --fizzy "https://fizzy.example.com,my-team,\${FIZZY_TOKEN},42"

# Reconfigure Fizzy on an existing project (interactive):
./setup.sh /path/to/project --fizzy

# Reconfigure Fizzy (non-interactive):
./setup.sh /path/to/project --fizzy "https://fizzy.example.com,my-team,\${FIZZY_TOKEN},42"
```

The `--fizzy` flag takes `url,slug,token,boardId` (comma-separated). Once configured, push tasks:

```bash
export FIZZY_TOKEN=your-personal-access-token
bash .claude/scripts/fizzy-sync.sh
```

The script reads `tasks.json`, creates/updates Fizzy cards, and maps statuses to columns:
- `todo` → "Not now" | `in_progress` → "Now" | `review` → "Maybe" | `done` → "Done"

Column mapping is configurable in `.claude/pipeline/config.json` under `fizzy.columnMap`.

## Task Board

The pipeline uses `tasks.json` as a kanban-style task board:

```bash
# View the board locally
bash .claude/scripts/kanban.sh

# Push to Fizzy (if configured)
bash .claude/scripts/fizzy-sync.sh

# Or use the skill
/pipeline-status
```

## Templates

A CLAUDE.md template is provided at `templates/CLAUDE.md.template`. Copy it to your project root and customize it.

## Requirements

- Claude Code CLI
- `jq` (for kanban.sh and fizzy-sync.sh)
- `curl` (for fizzy-sync.sh, if using Fizzy)
- `python3` (for skill-agent-test.sh JSON parsing)
- Project-specific tools (pnpm, bundle, flutter, etc.)

## Development

### Repository Structure

```
claude-squad/
├── agents/                # Agent definitions (22 .md files)
├── skills/                # Skill knowledge bases (93 directories)
│   └── [skill-name]/
│       └── SKILL.md
├── pipeline/
│   ├── config.json        # Pipeline orchestration settings + Fizzy config
│   └── agents/            # Per-agent pipeline configs (20 .json)
├── hooks/
│   ├── test-before-commit.sh   # Pre-commit test hook
│   └── protect-definitions.sh  # Agent/skill edit warning
├── scripts/
│   ├── kanban.sh               # Terminal kanban board viewer
│   ├── fizzy-sync.sh           # Push tasks to Fizzy kanban board
│   ├── skill-test.sh           # Structural skill quality tests
│   ├── skill-agent-test.sh     # Agent-based skill quality tests
│   ├── update.sh               # Config updater (diff + prompt before overwrite)
│   ├── test-setup.sh           # Installer test suite (not copied to projects)
│   └── skill-prompts/          # Test prompts for skill evaluation
├── settings/
│   └── settings.json      # Claude Code settings template
├── templates/
│   └── CLAUDE.md.template # Project config template
├── setup.sh               # Interactive installer
└── README.md
```

### Setup Script

The installer (`setup.sh`) supports three modes:

```bash
./setup.sh /path/to/project                                      # Interactive picker
./setup.sh /path/to/project --agents dev-rails,dev-node           # Non-interactive
./setup.sh /path/to/project --agents dev-rails --count 2          # With agent count
./setup.sh /path/to/project --agents dev-rails --fizzy "url,slug" # With Fizzy
./setup.sh --list                                                 # Show available agents
```

#### Example: `./setup.sh --list`

```
claude-squad — available agents

Core team (always installed):
  pipeline-agent          —              Orchestrates the full software development pipeline
  pm-agent                4 skills   1765 lines  Project Manager — drafts phase plans
  ba-agent                4 skills   2045 lines  Business Analyst — adds domain detail
  designer-agent          1 skills    500 lines  UI Designer — creates ASCII wireframes
  architect-agent         6 skills   3668 lines  Solution Architect — reviews technical feasibility
  integration-agent       5 skills              Integration Engineer — E2E tests, doc sync
  qa-agent                8 skills   4711 lines  QA Engineer — verifies implementations

Dev stacks (select at least one):
  [1] dev-rails             6 skills   3825 lines  Ruby on Rails
  [2] dev-react             6 skills   2928 lines  React
  [3] dev-flutter           6 skills   3637 lines  Flutter
  [4] dev-node              6 skills   3412 lines  Node.js
  [5] dev-odoo              6 skills   3296 lines  Odoo
  [6] dev-salesforce        6 skills   3112 lines  Salesforce
  [7] dev-webflow           6 skills   5138 lines  Webflow
  [8] dev-astro             6 skills   4691 lines  Astro
  [9] dev-payload-cms       6 skills   5516 lines  Payload CMS

Infrastructure (optional):
  [1] devop-aws            11 skills   6934 lines  AWS
  [2] devop-azure          11 skills   6899 lines  Azure
  [3] devop-gcloud         11 skills   6833 lines  Google Cloud
  [4] devop-firebase        9 skills   5355 lines  Firebase
  [5] devop-flyio           9 skills   4963 lines  Fly.io
```

#### Example: Non-interactive Install

```
$ ./setup.sh ~/myproject --agents dev-rails,dev-node,devop-flyio --count 2

Installing claude-squad to /Users/you/myproject/.claude ...

  Copying agents...
  Copying pipeline configuration...
  Setting agent counts...
  Copying skills...
  Copying hooks...
  Copying scripts...
  Copying settings...
  Copying templates...

============================================
  claude-squad installed successfully!
============================================

  Agents:           10
  Skills:           44
  Pipeline configs: 9
  Hooks:            2
  Scripts:          4

Installed agents:
  Core:  pipeline-agent pm-agent ba-agent designer-agent architect-agent integration-agent qa-agent
  Stack: dev-rails dev-node devop-flyio
  Counts:
    dev-rails            x2
    dev-node             x2
    devop-flyio          x2
```

### Skill Quality Testing

Two-layer testing ensures skill quality:

**Layer 1: Structural Tests** (fast, free, deterministic)

```bash
bash scripts/skill-test.sh                    # Test all skills
bash scripts/skill-test.sh rails-models       # Test one skill
bash scripts/skill-test.sh --category dev     # Test by category
```

Checks: YAML frontmatter, line count (>=300), Sources section, source URLs (>=5), code blocks (>=3), agent cross-references, pipeline config consistency, required sections.

**Layer 2: Agent-Based Tests** (deep quality, uses Claude API)

```bash
bash scripts/skill-agent-test.sh                    # Test all skills
bash scripts/skill-agent-test.sh rails-models       # Test one skill
bash scripts/skill-agent-test.sh --category dev     # Test by category
```

Creates a temporary agent with a single skill loaded, sends a realistic prompt, and scores the response on 4 dimensions (1-5): Relevance, Depth, Accuracy, Completeness.

Pass criteria: Dev/DevOps/QA/Architect skills need avg >= 4.5. PM/BA skills need avg >= 3.5.

### Installer Tests

```bash
bash scripts/test-setup.sh
```

| # | Test | Assertions | What it verifies |
|---|------|------------|------------------|
| 1 | `--list` output | 1 | All 21 installable agents shown with skill counts and line counts |
| 2 | `--agents dev-rails` | 6 | Correct agent files (8), pipeline configs (7), skills, hooks, settings |
| 3 | `dev-rails,dev-node` | 3 | Shared skills (`git-workflow`, `code-review-practices`) deduped, both skill sets present |
| 4 | `dev-rails,devop-flyio` | 1 | Cross-category install: rails + flyio + shared devops skills |
| 5 | Repeatable install | 3 | Run with rails, re-run with node — both agents, configs, and skills present |
| 6 | Core agents | 1 | `pipeline-agent`, `pm-agent`, `ba-agent`, `designer-agent`, `architect-agent`, `integration-agent`, `qa-agent` always present |
| 7 | No stale skills | 1 | Skills directory rebuilt from scratch — no leftovers from prior installs |
| 8 | Pipeline config match | 1 | Only selected agents get `.json` configs |
| 9 | Source validation | 1 | Every installed skill directory exists in source repo |
| 10 | Scripts & settings | 1 | Scripts copied (excluding `test-setup.sh`), settings, templates, executability |
| 11 | `--count` flag | 2 | Count applied to selected agents only, core agents stay at 1 |
| 12 | Count preservation | 4 | Re-run preserves existing counts; `--count` only affects newly selected agents |
| 13 | `--fizzy` flag | 2 | Fizzy config written to pipeline config; defaults to disabled without flag |
| | **Total** | **27** | |

```
$ bash scripts/test-setup.sh

claude-squad setup.sh test suite
=================================

Test 1: --list shows all agents with skills
  PASS Test 1: --list shows all agents with skills and line counts
Test 2: --agents dev-rails copies correct subset
  PASS Test 2a: 8 agent .md files
  PASS Test 2b: 7 pipeline configs
  PASS Test 2c: all expected agent files present
  PASS Test 2e: hooks copied
  PASS Test 2f: settings copied
  PASS Test 2: dev-rails install verified
Test 3: --agents dev-rails,dev-node deduplicates shared skills
  PASS Test 3a: shared skills exist exactly once
  PASS Test 3b: both rails and node skills present
  PASS Test 3c: 9 agent files
Test 4: --agents dev-rails,devop-flyio copies correct cross-category skills
  PASS Test 4: cross-category install correct (8 pipeline configs, both skill sets)
Test 5: Repeatable install — run with dev-rails, then add dev-node
  PASS Test 5a: both agent .md files present after re-run
  PASS Test 5b: both pipeline configs present after re-run
  PASS Test 5c: both skill sets present after re-run
Test 6: Core agents always present even if not explicitly selected
  PASS Test 6: all core agents and pipeline configs always present
Test 7: No stale skill directories after re-run
  PASS Test 7: no stale skills — kubernetes-patterns absent in rails-only install
Test 8: Pipeline configs match selected agents
  PASS Test 8: pipeline configs match exactly
Test 9: All copied skills exist as source directories
  PASS Test 9: all installed skills have matching source directories
Test 10: Scripts, settings, and templates copied correctly
  PASS Test 10: scripts, settings, and templates all correct
Test 11: --count sets agent count for selected agents only
  PASS Test 11a: --count 3 applied to selected agents, core agents unchanged
  PASS Test 11b: default count is 1 when --count not specified
Test 12: Re-run preserves existing agent counts
  PASS Test 12a: dev-rails count preserved as 3 after re-run
  PASS Test 12b: dev-node count defaults to 1
  PASS Test 12c: all counts correct after 3 runs (rails=3, node=1, flyio=5)
  PASS Test 12d: core agents still count 1
Test 13: --fizzy configures Fizzy sync in pipeline config
  PASS Test 13a: --fizzy flag sets all Fizzy config fields correctly
  PASS Test 13b: fizzy.sync defaults to false without --fizzy flag

=================================
Results: 27/27 passed
All tests passed!
```

## Contributing

### Adding a New Agent

1. Create the agent definition in `agents/<name>.md` with YAML frontmatter:

```yaml
---
name: dev-python
description: Python developer — Django, FastAPI, SQLAlchemy, pytest
tools: Read, Write, Edit, Bash, Grep, Glob
model: sonnet
maxTurns: 100
skills: python-web, python-data, python-testing, python-performance, git-workflow, code-review-practices
---
```

2. Create skill directories under `skills/` for each new skill (see existing skills for format)
3. Create the pipeline config in `pipeline/agents/<name>.json`
4. Add the agent name to the appropriate list in `setup.sh` (`DEV_AGENTS` or `DEVOP_AGENTS`)
5. Run `bash scripts/test-setup.sh` to verify the installer still works

### Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md` with:
   - YAML frontmatter (`name`, `description`, `sources`)
   - Minimum 300 lines of staff-engineer-level guidance
   - At least 5 source URLs and 3 code blocks
   - A "Sources & References" section
2. Reference the skill in the appropriate agent's `skills:` frontmatter
3. Run structural tests: `bash scripts/skill-test.sh <skill-name>`
4. Run agent-based tests: `bash scripts/skill-agent-test.sh <skill-name>`

### Modifying the Installer

1. Edit `setup.sh`
2. Update or add tests in `scripts/test-setup.sh`
3. Run: `bash scripts/test-setup.sh` — all tests must pass
4. Update this README if behavior changes

## Sources & Attribution

Each domain skill includes a "Sources & References" section citing the official documentation, blog posts, and expert articles used to compile its content. These skills are curated from publicly available resources to provide staff-engineer-level knowledge for each stack.

## License

MIT License. See [LICENSE](LICENSE) for details.
