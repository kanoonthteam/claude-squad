# Fizzy Setup on Fly.io

Deploy your own [Fizzy](https://fizzy.do) kanban board on Fly.io, then connect it to claude-squad's pipeline sync.

## Prerequisites

- [Fly.io account](https://fly.io/app/sign-up) (free tier works)
- [`flyctl` CLI](https://fly.io/docs/flyctl/install/) installed
- SMTP credentials for email (sign-up/sign-in requires email)

```bash
# Install flyctl (macOS)
brew install flyctl

# Login
fly auth login
```

## 1. Create the Project

```bash
mkdir fizzy-deploy && cd fizzy-deploy
```

Create `fly.toml`:

```toml
app = "your-fizzy-app"
primary_region = "sin"  # Singapore — change to your nearest region

[build]
  image = "ghcr.io/basecamp/fizzy:main"

[env]
  BASE_URL = "https://your-fizzy-app.fly.dev"
  DISABLE_SSL = "true"  # Fly.io terminates SSL at the proxy

[http_service]
  internal_port = 80
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0

[[vm]]
  size = "shared-cpu-1x"
  memory = "512mb"

[mounts]
  source = "fizzy_data"
  destination = "/rails/storage"
```

> **Region codes**: `sin` (Singapore), `nrt` (Tokyo), `hkg` (Hong Kong), `bkk` (Bangkok), `sea` (Seattle), `iad` (Virginia), `lhr` (London), `fra` (Frankfurt). Run `fly platform regions` for the full list.

## 2. Create the App + Volume

```bash
# Create the app (without deploying yet)
fly apps create your-fizzy-app

# Create a persistent volume for the SQLite database
fly volumes create fizzy_data --region sin --size 1 --app your-fizzy-app
```

## 3. Set Secrets

### Required: Secret Key Base

```bash
# Generate a secret key
SECRET=$(openssl rand -hex 64)

fly secrets set SECRET_KEY_BASE="$SECRET" --app your-fizzy-app
```

### Required: SMTP (for sign-up/sign-in emails)

Fizzy sends magic-link emails for authentication. You need an SMTP provider. Some options:

| Provider | Free Tier | SMTP Server |
|----------|-----------|-------------|
| [Resend](https://resend.com) | 3,000 emails/mo | `smtp.resend.com` |
| [Brevo](https://brevo.com) | 300 emails/day | `smtp-relay.brevo.com` |
| [Mailgun](https://mailgun.com) | 1,000 emails/mo | `smtp.mailgun.org` |
| Gmail | 500/day | `smtp.gmail.com` |

```bash
fly secrets set \
  MAILER_FROM_ADDRESS="fizzy@yourdomain.com" \
  SMTP_ADDRESS="smtp.resend.com" \
  SMTP_PORT="465" \
  SMTP_USERNAME="resend" \
  SMTP_PASSWORD="re_your_api_key" \
  SMTP_TLS="true" \
  --app your-fizzy-app
```

> **Gmail users**: Use an [App Password](https://myaccount.google.com/apppasswords), not your regular password. Set `SMTP_ADDRESS=smtp.gmail.com`, `SMTP_PORT=587`, `SMTP_USERNAME=you@gmail.com`.

### Optional: VAPID Keys (for push notifications)

Skip this if you don't need browser push notifications. You can add it later.

```bash
# Generate VAPID keys (requires Ruby or use an online generator)
# Option 1: Ruby (if installed)
ruby -e "require 'web_push'; k = WebPush.generate_key; puts \"PRIVATE=#{k.private_key}\nPUBLIC=#{k.public_key}\""

# Option 2: Use Node.js
npx web-push generate-vapid-keys

# Set them
fly secrets set \
  VAPID_PRIVATE_KEY="your_private_key" \
  VAPID_PUBLIC_KEY="your_public_key" \
  --app your-fizzy-app
```

## 4. Deploy

```bash
fly deploy --app your-fizzy-app
```

Wait for the deployment to complete. Then open your Fizzy instance:

```bash
fly apps open --app your-fizzy-app
```

Your Fizzy board is now live at `https://your-fizzy-app.fly.dev`.

## 5. Initial Fizzy Setup

1. **Open** `https://your-fizzy-app.fly.dev`
2. **Create your account** — enter your email, check for the magic-link email, click to sign in
3. **Create a board** — e.g. "My Project"
4. **Note the board ID** — visible in the URL: `https://your-fizzy-app.fly.dev/your-slug/boards/42` → board ID is `42`
5. **Note your account slug** — the path segment after the domain: `/your-slug/boards/...`

### Columns

The fizzy-sync script maps task statuses to Fizzy column names. Missing columns are **auto-created** on the board when you first sync:

| Task Status | Default Mapping |
|-------------|----------------|
| `todo` | Todo |
| `in_progress` | In Progress |
| `review` | Review |
| `done` | `__close__` (closes the card) |

The special value `__close__` closes the card instead of moving it to a column. Cards are automatically reopened if their status changes back to a non-done status. You can change `__close__` to a column name (e.g. `"Done"`) in `columnMap` if you prefer keeping done cards visible.

### Generate an API Token

1. Click your **profile icon** (top-right)
2. Go to **API** → **Personal access tokens**
3. Click **Generate new access token**
4. Give it a description (e.g. "claude-squad sync")
5. Select **Read + Write** permission
6. Copy the token — you'll need it for the next step

## 6. Connect to claude-squad

### Option A: During Setup (interactive)

```bash
./setup.sh /path/to/your/project
# When prompted "Configure Fizzy sync? (y/N):" → y
# Enter your Fizzy URL, account slug, token, and board ID
```

### Option B: During Setup (non-interactive)

```bash
./setup.sh /path/to/project \
  --agents dev-rails \
  --fizzy "https://your-fizzy-app.fly.dev,your-slug,\${FIZZY_TOKEN},42"
```

### Option C: Reconfigure Fizzy on existing project

```bash
# Interactive — prompts for each value (shows current values as defaults)
./setup.sh /path/to/project --fizzy

# Non-interactive
./setup.sh /path/to/project --fizzy "https://your-fizzy-app.fly.dev,your-slug,\${FIZZY_TOKEN},42"
```

### Option D: Manual Configuration

Edit `.claude/pipeline/config.json` in your project:

```json
{
  "fizzy": {
    "url": "https://your-fizzy-app.fly.dev",
    "accountSlug": "your-slug",
    "token": "${FIZZY_TOKEN}",
    "sync": true,
    "boardId": "42",
    "columnMap": {
      "todo": "Todo",
      "in_progress": "In Progress",
      "review": "Review",
      "done": "__close__"
    }
  }
}
```

### Set the Token

```bash
# Add to your shell profile (~/.zshrc or ~/.bashrc)
export FIZZY_TOKEN=your-personal-access-token

# Or set it per-session
export FIZZY_TOKEN=your-personal-access-token
```

## 7. Sync Tasks

After running `/pipeline` and generating tasks:

```bash
# Push tasks to your Fizzy board
bash .claude/scripts/fizzy-sync.sh
```

Output:

```
Fizzy sync: My Project
══════════════════════════════════════
Pushing 12 tasks to https://your-fizzy-app.fly.dev ...

  CREATE  #1   Set up database schema  [todo]
  CREATE  #2   Add user model          [todo]
  CREATE  #3   Build login endpoint    [in_progress]
  ...

Done: 12 created, 0 updated, 0 closed, 0 skipped
```

Re-running the script updates existing cards (moves them to the correct column based on current status) and creates new ones.

## Troubleshooting

### "Fizzy sync is disabled"

Set `fizzy.sync` to `true` in `.claude/pipeline/config.json`.

### "No Fizzy token"

```bash
export FIZZY_TOKEN=your-token
```

### Email not arriving

Check your SMTP config:
```bash
fly secrets list --app your-fizzy-app
fly logs --app your-fizzy-app
```

Common issues:
- Wrong SMTP port (use 465 with `SMTP_TLS=true`, or 587 without)
- Gmail requires App Passwords, not regular passwords
- Some providers require domain verification

### Volume / Database issues

```bash
# Check volume status
fly volumes list --app your-fizzy-app

# SSH into the machine
fly ssh console --app your-fizzy-app

# Check disk usage
df -h /rails/storage
```

### App not starting

```bash
# Check logs
fly logs --app your-fizzy-app

# Check machine status
fly status --app your-fizzy-app
```

### Column mapping mismatch

If your Fizzy columns don't match the defaults, update `fizzy.columnMap` in `config.json`:

```json
"columnMap": {
  "todo": "Backlog",
  "in_progress": "In Progress",
  "review": "Review",
  "done": "Completed"
}
```

Use `"__close__"` for the `done` value to close cards instead of moving them to a column. Use a column name (e.g. `"Done"`) to keep completed cards visible on the board.

## Cost

Fly.io pricing for a minimal Fizzy instance:
- **shared-cpu-1x, 512MB RAM**: ~$3.19/mo (prorated, billed per second)
- **1GB volume**: ~$0.15/mo
- **Auto-stop**: Machine stops when idle, reducing cost further
- **Free allowance**: Fly.io includes some free resources for new accounts

With `auto_stop_machines = "stop"`, your Fizzy instance sleeps when unused and wakes on the next request (cold start ~2-5 seconds).

## References

- [Fizzy](https://fizzy.do) — official site
- [Fizzy GitHub](https://github.com/basecamp/fizzy) — source code
- [Fizzy Docker Deployment](https://github.com/basecamp/fizzy/blob/main/docs/docker-deployment.md) — official Docker guide
- [Fizzy API](https://github.com/basecamp/fizzy/blob/main/docs/API.md) — API documentation
- [Fly.io Docs](https://fly.io/docs/) — platform documentation
- [Fly.io Volumes](https://fly.io/docs/volumes/overview/) — persistent storage
