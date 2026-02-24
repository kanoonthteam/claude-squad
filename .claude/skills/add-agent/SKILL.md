---
name: add-agent
description: Scaffold a new agent — generates agent definition, pipeline config, skills, and updates setup.sh/README
invocation: /add-agent
---

# Add Agent

Scaffold a new agent interactively. Generates the agent definition, pipeline config, and optionally new skills — then registers the agent in setup.sh, test-setup.sh, and README.

## Usage

```
/add-agent
```

Follow the prompts to provide agent details, select skills, and generate all required files.

---

## Step 1: Gather Agent Information

Ask the user four groups of questions using AskUserQuestion.

### Group 1 — Identity

Ask:

| Question | Options | Example |
|----------|---------|---------|
| Category | `dev` or `devops` | `dev` |
| Technology name (lowercase, no spaces) | free text | `python` |
| One-line description | free text | `Python developer — Django, FastAPI, SQLAlchemy, pytest` |

The agent file will be named:
- `dev` category: `dev-{name}.md` (e.g. `dev-python.md`)
- `devops` category: `devop-{name}.md` (e.g. `devop-vercel.md`)

### Group 2 — Stack

**For dev agents, ask:**

| Question | Example |
|----------|---------|
| Language and version | `Python 3.12+` |
| Framework(s) | `Django 5.x, FastAPI` |
| ORM / database layer | `SQLAlchemy + PostgreSQL` |
| Testing framework | `pytest + pytest-cov` |
| Linting tool | `Ruff + mypy` |

**For devops agents, ask:**

| Question | Example |
|----------|---------|
| IaC tool | `Terraform + Pulumi` |
| Compute / platform | `AWS Lambda, ECS Fargate` |
| Database | `RDS PostgreSQL, DynamoDB` |
| Networking | `VPC, ALB, Route53` |
| Monitoring tool | `Datadog + PagerDuty` |

### Group 3 — Skills

Present the existing skills catalog (below) grouped by category. Ask the user:

1. Which existing skills should this agent reuse?
2. Which new skills should be created?

**Auto-included shared skills (do not ask — always add):**

For `dev` agents:
- `git-workflow`
- `code-review-practices`

For `devops` agents:
- `devops-cicd`
- `devops-containers`
- `devops-monitoring`
- `terraform-patterns`
- `kubernetes-patterns`
- `observability-practices`
- `incident-management`

**New skill naming convention:** `<tech>-<domain>` (e.g. `python-web`, `python-testing`, `vercel-deploy`)

### Group 4 — Infrastructure

Ask:

| Question | Options |
|----------|---------|
| MCP servers needed? | `postgres`, `github`, `firebase`, or `none` |
| Task filter tags (2 tags) | Category tag (`backend`, `frontend`, `mobile`, `devops`) + technology name |

---

## Step 2: Generate Agent Files

Create two files using the templates below, substituting all `{PLACEHOLDER}` values.

### Template: `agents/{AGENT_FILENAME}.md`

```markdown
---
name: {AGENT_FILENAME}
description: {DESCRIPTION}
tools: Read, Write, Edit, Bash, Grep, Glob
model: sonnet
maxTurns: 100
skills: {SKILLS_CSV}
---

# {TITLE}

You are a senior {TECHNOLOGY} {ROLE_LABEL}. You {ROLE_VERB} using {FRAMEWORK} best practices.

## Your Stack

- **Language**: {LANGUAGE}
- **Framework**: {FRAMEWORK}
- **ORM**: {ORM}
- **Testing**: {TESTING}
- **Linting**: {LINTING}
- **Database**: {DATABASE}

## Your Process

1. **Read the task**: Understand requirements and acceptance criteria from tasks.json
2. **Explore the codebase**: Understand existing patterns and conventions
3. **Implement**: Write clean, conventional {TECHNOLOGY} code
4. **Test**: Write tests that cover acceptance criteria
5. **Verify**: Run the test suite to ensure no regressions
6. **Report**: Mark task as done and report what was implemented

## {TECHNOLOGY} Conventions

{Generate 8-10 bullet points specific to the technology. Base these on established community conventions, official style guides, and best practices for the given framework/language.}

## Code Standards

{Generate 6-8 bullet points including:}
- Never auto-generate mocks (e.g. dart mockito @GenerateMocks, python unittest.mock.patch auto-spec). Write manual mock/fake classes instead

## Definition of Done

{Use the DEV or DEVOPS variant below}

### Output Report
After completing a task, report:
- Files created/modified
- Tests added and their results
- Documentation updated
- E2E scenarios affected
- Decisions made and why
- Any remaining concerns or risks
```

**Placeholder reference:**

| Placeholder | Source |
|-------------|--------|
| `{AGENT_FILENAME}` | `dev-{name}` or `devop-{name}` |
| `{DESCRIPTION}` | One-line description from Group 1 |
| `{SKILLS_CSV}` | Comma-separated skill names (new + shared) |
| `{TITLE}` | e.g. "Python Developer" or "Vercel DevOps Engineer" |
| `{TECHNOLOGY}` | Technology name capitalized (e.g. "Python") |
| `{ROLE_LABEL}` | "developer" for dev, "DevOps engineer" for devops |
| `{ROLE_VERB}` | "implement features" for dev, "design and implement cloud infrastructure" for devops |
| `{LANGUAGE}` | Language and version from Group 2 |
| `{FRAMEWORK}` | Framework(s) from Group 2 |
| `{ORM}` | ORM / database from Group 2 |
| `{TESTING}` | Testing framework from Group 2 |
| `{LINTING}` | Linting tool from Group 2 |
| `{DATABASE}` | Database from Group 2 |

**For devops agents**, replace the "Your Stack" section keys:

```markdown
## Your Stack

- **IaC**: {IAC_TOOL}
- **Compute**: {COMPUTE}
- **Database**: {DATABASE}
- **Networking**: {NETWORKING}
- **Monitoring**: {MONITORING}
- **CI/CD**: {CICD}
```

### Definition of Done — Dev Variant

```markdown
## Definition of Done

A task is "done" when ALL of the following are true:

### Code & Tests
- [ ] Implementation complete — all acceptance criteria addressed
- [ ] Unit/integration tests added and passing
- [ ] Existing test suite passes (no regressions)
- [ ] Code follows project conventions and linting passes
- [ ] {STACK_SPECIFIC_LINE}

### Documentation
- [ ] API documentation updated if endpoints added/changed
- [ ] Migration instructions documented if schema changed
- [ ] Inline code comments added for non-obvious logic
- [ ] README updated if setup steps, env vars, or dependencies changed

### Handoff Notes
- [ ] E2E scenarios affected listed (for integration agent)
- [ ] Breaking changes flagged with migration path
- [ ] Dependencies on other tasks verified complete
```

`{STACK_SPECIFIC_LINE}` examples:
- Rails: `Migration reversible and tested`
- Flutter: `Platform-specific considerations documented`
- Node: `TypeScript strict mode passes`
- Python: `Type hints added for public functions`

### Definition of Done — DevOps Variant

```markdown
## Definition of Done

A task is "done" when ALL of the following are true:

### Infrastructure & Config
- [ ] Infrastructure code complete and validated (lint/plan)
- [ ] Security review: IAM least-privilege, no secrets in code
- [ ] Cost estimate documented

### Documentation
- [ ] Deployment runbook updated with new commands/steps
- [ ] Environment variables documented
- [ ] Architecture diagram updated if topology changed
- [ ] README updated if setup or deployment process changed

### Handoff Notes
- [ ] E2E scenarios affected listed (e.g., "deploy pipeline", "scaling behavior")
- [ ] Rollback procedure documented
- [ ] Dependencies on other tasks verified complete
```

### Template: `pipeline/agents/{AGENT_FILENAME}.json`

```json
{
  "agent": "{AGENT_FILENAME}",
  "role": "{ROLE}",
  "count": 1,
  "model": "sonnet",
  "skills": [{SKILLS_JSON_ARRAY}],
  "mcp": {MCP_CONFIG},
  "taskFilter": {
    "tags": ["{TAG1}", "{TAG2}"]
  }
}
```

**`{ROLE}`**: `"dev"` or `"devops"`

**MCP config examples:**

No MCP:
```json
"mcp": {}
```

Postgres:
```json
"mcp": {
  "postgres": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-postgres"],
    "env": {
      "DATABASE_URL": "${DATABASE_URL}"
    }
  }
}
```

GitHub:
```json
"mcp": {
  "github": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-github"],
    "env": {
      "GITHUB_TOKEN": "${GITHUB_TOKEN}"
    }
  }
}
```

Firebase:
```json
"mcp": {
  "firebase": {
    "command": "npx",
    "args": ["-y", "firebase-mcp-server"],
    "env": {
      "FIREBASE_PROJECT_ID": "${FIREBASE_PROJECT_ID}"
    }
  }
}
```

---

## Step 3: Create New Skills

For **each** new skill the user requested in Group 3, ask these questions:

### Skill Prompts (per skill)

1. **What is this skill about?** — One-line description for the frontmatter.

2. **What are the 8-12 main topics it should cover?** — These become the Table of Contents sections. Suggest defaults based on the skill domain:

   | Skill pattern | Suggested sections |
   |---------------|-------------------|
   | `<tech>-architecture` | Project Structure, Module Organization, Dependency Injection, Configuration, Error Handling, Logging, Security, Performance, Deployment, Best Practices, Anti-Patterns |
   | `<tech>-testing` | Test Structure, Unit Testing, Integration Testing, Fixtures & Factories, Mocking, Coverage, CI Integration, Performance Testing, Best Practices, Anti-Patterns |
   | `<tech>-api` | Route Structure, Request Handling, Response Formats, Authentication, Authorization, Validation, Error Handling, Rate Limiting, Versioning, Documentation, Best Practices, Anti-Patterns |
   | `<tech>-performance` | Profiling, Caching, Query Optimization, Connection Pooling, Async/Concurrency, Memory Management, CDN, Load Testing, Best Practices, Anti-Patterns |
   | `<platform>-core` | Architecture, Configuration, Authentication, Networking, Storage, Scaling, Monitoring, CLI Commands, Best Practices, Anti-Patterns |
   | `<platform>-deploy` | Deployment Strategies, Dockerfiles, CI/CD, Blue-Green, Rollbacks, Secrets, Health Checks, Best Practices, Anti-Patterns |
   | `<platform>-operations` | Monitoring, Alerting, Log Management, Scaling, Backup, Disaster Recovery, Cost Optimization, Best Practices, Anti-Patterns |

3. **Any specific patterns, libraries, or conventions to emphasize?** — e.g. "Use Pydantic v2 for validation", "Include Alembic migration patterns"

### Skill Template

For each skill, create `skills/{SKILL_NAME}/SKILL.md`:

```markdown
---
name: {SKILL_NAME}
description: {SKILL_DESCRIPTION}
---

# {Skill Title}

{Intro paragraph — what this skill covers and for what tech stack}

## Table of Contents

{Numbered list of 8-12 sections based on user's answers}

---

## 1. {First Section}

{Production-quality content with code blocks, patterns, conventions}
{Each section: 30-50 lines with at least 1 code block}

...

## {N-1}. Best Practices

{10-15 bullet points of do's}

## {N}. Anti-Patterns

{8-10 bullet points of don'ts with explanations}

## Sources & References

{5+ URLs to official docs, guides, blog posts}
```

### Skill Requirements

Each generated skill MUST meet these minimums:

- Minimum **300 lines**
- At least **3 code blocks** (with proper language tags)
- At least **5 URLs** in Sources & References section
- Must include **Best Practices** and **Anti-Patterns** sections (for dev/devops categories)
- Use **web search** to gather current (2025-2026) best practices before writing content

After creating each skill, validate it:

```bash
bash scripts/skill-test.sh {SKILL_NAME}
```

---

## Step 4: Register the Agent

Edit these files to register the new agent in the system.

### 4a. `setup.sh`

Append the agent name to the appropriate list (line 30 or 31):

- **Dev agent**: Add to `DEV_AGENTS` (line 30)
- **DevOps agent**: Add to `DEVOP_AGENTS` (line 31)

Example — adding `dev-python`:

```bash
# Before:
DEV_AGENTS="dev-rails dev-react dev-flutter dev-node dev-odoo dev-salesforce dev-webflow dev-astro dev-payload-cms"

# After:
DEV_AGENTS="dev-rails dev-react dev-flutter dev-node dev-odoo dev-salesforce dev-webflow dev-astro dev-payload-cms dev-python"
```

### 4b. `scripts/test-setup.sh`

Add the agent name to the appropriate test loop in Test 1:

- **Dev agent**: Add to the dev agents loop (line 83)
- **DevOps agent**: Add to the devops agents loop (line 93)

Example — adding `dev-python` to the dev loop:

```bash
# Before:
for agent in dev-rails dev-react dev-flutter dev-node dev-odoo dev-salesforce dev-webflow dev-astro dev-payload-cms; do

# After:
for agent in dev-rails dev-react dev-flutter dev-node dev-odoo dev-salesforce dev-webflow dev-astro dev-payload-cms dev-python; do
```

### 4c. `scripts/skill-test.sh`

If the new skills follow a `<tech>-*` pattern not already in `categorize_skill()`, add the pattern.

Example — adding `python-*` to the dev case:

```bash
# Before:
rails-*|react-*|flutter-*|node-*|odoo-*|salesforce-*|git-workflow|code-review-practices)

# After:
rails-*|react-*|flutter-*|node-*|odoo-*|salesforce-*|python-*|git-workflow|code-review-practices)
```

Existing patterns that do NOT need adding (already covered):
- `rails-*`, `react-*`, `flutter-*`, `node-*`, `odoo-*`, `salesforce-*`
- `aws-*`, `azure-*`, `gcloud-*`, `firebase-*`, `flyio-*`, `devops-*`
- `astro-*`, `webflow-*`, `payload-*`

### 4d. `README.md`

Update these sections:

1. **Agent table** — Add a new row in the appropriate position:

   ```markdown
   | `dev-python` | Dev | {SKILL_COUNT} | {DESCRIPTION} |
   ```

2. **Agent count** — Update the heading count (e.g. "22 in catalog" -> "23 in catalog")

3. **Skills section** — If new skills were created:
   - Add a new line under the appropriate skills group
   - Update the total skills count (e.g. "Skills (93)" -> "Skills (97)")

---

## Step 5: Validate

Run all of these to verify the agent was scaffolded correctly:

```bash
# Full setup test suite — all tests must pass
bash scripts/test-setup.sh

# Structural checks for each new skill
bash scripts/skill-test.sh {SKILL_NAME}

# Verify agent appears in the list
./setup.sh --list
```

Fix any failures before considering the scaffold complete.

---

## Existing Skills Catalog

Use this catalog when asking the user which skills to reuse (Step 1, Group 3).

### Dev Skills (42)

**Rails:** `rails-models`, `rails-controllers`, `rails-performance`, `rails-testing`
**React:** `react-architecture`, `react-state`, `react-testing`, `react-ui`
**Flutter:** `flutter-architecture`, `flutter-networking`, `flutter-testing`, `flutter-ui`, `flutter-firebase`, `flutter-platform`, `flutter-localization`, `flutter-maps`
**Node.js:** `node-architecture`, `node-api`, `node-testing`, `node-performance`
**Odoo:** `odoo-models`, `odoo-views`, `odoo-backend`, `odoo-testing`
**Salesforce:** `salesforce-apex`, `salesforce-lwc`, `salesforce-integration`, `salesforce-testing`
**Webflow:** `webflow-structure`, `webflow-cms`, `webflow-interactions`, `webflow-testing`
**Astro:** `astro-architecture`, `astro-content`, `astro-components`, `astro-testing`
**Payload CMS:** `payload-collections`, `payload-admin`, `payload-api`, `payload-testing`
**Cross-cutting:** `git-workflow`, `code-review-practices`

### Infrastructure Skills (18)

**AWS:** `aws-compute`, `aws-data`, `aws-security`, `aws-operations`
**Azure:** `azure-compute`, `azure-data`, `azure-networking`, `azure-operations`
**GCloud:** `gcloud-compute`, `gcloud-data`, `gcloud-security`, `gcloud-operations`
**Firebase:** `firebase-backend`, `firebase-security`, `firebase-operations`
**Fly.io:** `flyio-core`, `flyio-deploy`, `flyio-operations`

### Shared DevOps Skills (7)

`devops-cicd`, `devops-containers`, `devops-monitoring`, `terraform-patterns`, `kubernetes-patterns`, `observability-practices`, `incident-management`

### QA Skills (8)

`testing-verification`, `testing-specialized`, `testing-fundamentals`, `testing-strategies`, `playwright-testing`, `performance-testing`, `accessibility-testing`, `chaos-engineering`

### Planning Skills (15)

**PM:** `task-planning`, `task-estimation`, `agile-frameworks`, `stakeholder-communication`
**BA:** `domain-modeling`, `domain-requirements`, `requirements-elicitation`, `process-modeling`
**Designer:** `ui-wireframing`
**Architect:** `design-patterns`, `design-review`, `architecture-documentation`, `security-architecture`, `api-design`, `api-security`

---

## Example Session

Here is a complete walkthrough of `/add-agent` creating a Python developer agent.

### Group 1 answers:
- Category: `dev`
- Technology: `python`
- Description: `Python developer — Django, FastAPI, SQLAlchemy, pytest`

### Group 2 answers:
- Language: `Python 3.12+`
- Framework: `Django 5.x, FastAPI`
- ORM: `SQLAlchemy 2.x + Alembic`
- Testing: `pytest + pytest-cov + factory_boy`
- Linting: `Ruff + mypy`

### Group 3 answers:
- Reuse: (none beyond auto-included)
- New skills: `python-web`, `python-testing`, `python-architecture`, `python-performance`
- Auto-included: `git-workflow`, `code-review-practices`

### Group 4 answers:
- MCP: `postgres`
- Tags: `backend`, `python`

### Generated files:

**`agents/dev-python.md`** — Agent definition with Python/Django/FastAPI conventions

**`pipeline/agents/dev-python.json`**:
```json
{
  "agent": "dev-python",
  "role": "dev",
  "count": 1,
  "model": "sonnet",
  "skills": ["python-web", "python-testing", "python-architecture", "python-performance", "git-workflow", "code-review-practices"],
  "mcp": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "DATABASE_URL": "${DATABASE_URL}"
      }
    }
  },
  "taskFilter": {
    "tags": ["backend", "python"]
  }
}
```

**`skills/python-web/SKILL.md`** — Django + FastAPI patterns (300+ lines)
**`skills/python-testing/SKILL.md`** — pytest patterns (300+ lines)
**`skills/python-architecture/SKILL.md`** — Project structure (300+ lines)
**`skills/python-performance/SKILL.md`** — Profiling, caching, async (300+ lines)

### Registration edits:

**`setup.sh`** line 30 — `dev-python` appended to `DEV_AGENTS`
**`scripts/test-setup.sh`** line 83 — `dev-python` added to dev agents loop
**`scripts/skill-test.sh`** line 43 — `python-*` added to dev pattern
**`README.md`** — Agent table row added, counts updated

### Validation:

```bash
bash scripts/test-setup.sh             # All tests pass
bash scripts/skill-test.sh python-web  # 9/9 checks pass
bash scripts/skill-test.sh python-testing       # 9/9 checks pass
bash scripts/skill-test.sh python-architecture  # 9/9 checks pass
bash scripts/skill-test.sh python-performance   # 9/9 checks pass
./setup.sh --list                      # dev-python appears with 6 skills
```
