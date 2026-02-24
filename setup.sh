#!/bin/bash
# claude-squad installer with interactive agent picker
#
# Usage:
#   ./setup.sh /path/to/project                              # Interactive picker
#   ./setup.sh /path/to/project --agents dev-rails,dev-node  # Non-interactive
#   ./setup.sh /path/to/project --agents dev-rails --count 2 # Set agent count
#   ./setup.sh --list                                        # Show available agents
#
# Safe to re-run — adds new agents on top of existing installation.

set -e

# ─── Constants ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/agents"
SKILLS_DIR="$SCRIPT_DIR/skills"
PIPELINE_DIR="$SCRIPT_DIR/pipeline"

# Core agents (always installed)
CORE_AGENTS="pipeline-agent pm-agent ba-agent designer-agent architect-agent integration-agent qa-agent"

# Utility skills (always installed)
UTILITY_SKILLS="pipeline pipeline-status review"

# Core pipeline configs (filename without .json)
CORE_PIPELINE_CONFIGS="pm ba designer architect integration qa"

# Selectable agents grouped by category
DEV_AGENTS="dev-rails dev-react dev-flutter dev-node dev-odoo dev-salesforce dev-webflow dev-astro dev-payload-cms dev-ml"
DEVOP_AGENTS="devop-aws devop-azure devop-gcloud devop-firebase devop-flyio"

# Global: space-separated "agent:count" pairs, e.g. "dev-rails:2 devop-flyio:1"
AGENT_COUNTS=""

# Global: Fizzy config (empty = skip)
FIZZY_URL_VAL=""
FIZZY_SLUG_VAL=""
FIZZY_TOKEN_VAL=""
FIZZY_BOARD_VAL=""

# ─── Functions ────────────────────────────────────────────────────────────────

# Look up per-agent count from AGENT_COUNTS global
get_agent_count() {
  local agent="$1"
  local pair
  for pair in $AGENT_COUNTS; do
    if [ "${pair%%:*}" = "$agent" ]; then
      echo "${pair##*:}"
      return
    fi
  done
  echo "1"
}

# Parse skills from agent .md frontmatter
# Usage: parse_skills agent-name
parse_skills() {
  local agent_file="$AGENTS_DIR/$1.md"
  if [ ! -f "$agent_file" ]; then
    return
  fi
  # Extract skills: line from YAML frontmatter (between --- markers)
  sed -n '/^---$/,/^---$/p' "$agent_file" | grep '^skills:' | sed 's/^skills: *//' | tr ',' '\n' | tr -d ' '
}

# Get description from agent .md frontmatter
parse_description() {
  local agent_file="$AGENTS_DIR/$1.md"
  if [ ! -f "$agent_file" ]; then
    return
  fi
  sed -n '/^---$/,/^---$/p' "$agent_file" | grep '^description:' | sed 's/^description: *//'
}

# Count total lines in an agent's skill files
count_skill_lines() {
  local agent="$1"
  local total=0
  for skill in $(parse_skills "$agent"); do
    local skill_file="$SKILLS_DIR/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      total=$((total + $(wc -l < "$skill_file")))
    fi
  done
  echo "$total"
}

# ─── list_agents ──────────────────────────────────────────────────────────────
list_agents() {
  echo "claude-squad — available agents"
  echo ""
  echo "Core team (always installed):"
  for agent in $CORE_AGENTS; do
    local desc
    desc=$(parse_description "$agent")
    local skills
    skills=$(parse_skills "$agent" | tr '\n' ',' | sed 's/,$//')
    local skill_count
    skill_count=$(parse_skills "$agent" | grep -c . || echo 0)
    local lines
    lines=$(count_skill_lines "$agent")
    if [ -n "$skills" ]; then
      printf "  %-22s %2s skills  %5s lines  %s\n" "$agent" "$skill_count" "$lines" "$desc"
    else
      printf "  %-22s  —              %s\n" "$agent" "$desc"
    fi
  done
  echo ""

  echo "Dev stacks (select at least one):"
  local i=1
  for agent in $DEV_AGENTS; do
    local desc
    desc=$(parse_description "$agent")
    local skill_count
    skill_count=$(parse_skills "$agent" | grep -c . || echo 0)
    local lines
    lines=$(count_skill_lines "$agent")
    printf "  [%d] %-20s %2s skills  %5s lines  %s\n" "$i" "$agent" "$skill_count" "$lines" "$desc"
    i=$((i + 1))
  done
  echo ""

  echo "Infrastructure (optional):"
  local j=1
  for agent in $DEVOP_AGENTS; do
    local desc
    desc=$(parse_description "$agent")
    local skill_count
    skill_count=$(parse_skills "$agent" | grep -c . || echo 0)
    local lines
    lines=$(count_skill_lines "$agent")
    printf "  [%d] %-20s %2s skills  %5s lines  %s\n" "$j" "$agent" "$skill_count" "$lines" "$desc"
    j=$((j + 1))
  done
  echo ""
}

# ─── detect_existing ──────────────────────────────────────────────────────────
# Returns space-separated list of already-installed selectable agents
detect_existing() {
  local target="$1"
  local existing=""

  # Check pipeline/agents/*.json for installed agents
  if [ -d "$target/pipeline/agents" ]; then
    for json_file in "$target/pipeline/agents"/*.json; do
      [ -f "$json_file" ] || continue
      local basename
      basename=$(basename "$json_file" .json)
      # Only track selectable agents (dev-* and devop-*)
      case "$basename" in
        dev-*|devop-*) existing="$existing $basename" ;;
      esac
    done
  fi

  echo "$existing" | xargs  # trim whitespace
}

# Read existing count for an agent from installed pipeline config
# Usage: detect_existing_count target agent
detect_existing_count() {
  local target="$1"
  local agent="$2"
  local config="$target/pipeline/agents/$agent.json"
  if [ -f "$config" ]; then
    grep '"count"' "$config" | tr -d ' ,"' | cut -d: -f2
  else
    echo "1"
  fi
}

# ─── resolve_skills ───────────────────────────────────────────────────────────
# Given a list of selected agents, returns deduped set of all skills to install
resolve_skills() {
  local agents="$*"
  local all_skills=""

  # Utility skills (always)
  all_skills="$UTILITY_SKILLS"

  # Core agent skills
  for agent in $CORE_AGENTS; do
    local skills
    skills=$(parse_skills "$agent")
    if [ -n "$skills" ]; then
      all_skills="$all_skills $skills"
    fi
  done

  # Selected agent skills
  for agent in $agents; do
    local skills
    skills=$(parse_skills "$agent")
    if [ -n "$skills" ]; then
      all_skills="$all_skills $skills"
    fi
  done

  # Dedupe
  echo "$all_skills" | tr ' ' '\n' | sort -u | grep -v '^$'
}

# ─── interactive_picker ──────────────────────────────────────────────────────
# Sets global variables: PICKED_AGENTS, PICKED_COUNT
interactive_picker() {
  local target="$1"
  local existing
  existing=$(detect_existing "$target")

  echo "╔══════════════════════════════════════════════════╗"
  echo "║  claude-squad installer                          ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""
  echo "Core team (always installed):"

  for agent in $CORE_AGENTS; do
    echo "  + $agent"
  done
  echo ""

  # ── Dev stacks ──
  echo "Select dev stack(s) — at least one:"
  local i=1
  local dev_array=()
  for agent in $DEV_AGENTS; do
    dev_array+=("$agent")
    local desc
    desc=$(parse_description "$agent")
    local marker=" "
    # Mark existing with *
    if echo " $existing " | grep -q " $agent "; then
      marker="*"
    fi
    printf "  [%d] %s %-18s %s\n" "$i" "$marker" "$agent" "$desc"
    i=$((i + 1))
  done
  echo ""

  if [ -n "$existing" ]; then
    echo "  (* = already installed)"
    echo ""
  fi

  local dev_input
  read -r -p "Enter numbers (comma-separated, e.g. 1,4): " dev_input

  if [ -z "$dev_input" ]; then
    # If there are existing dev agents, allow skipping
    local has_existing_dev=false
    for agent in $DEV_AGENTS; do
      if echo " $existing " | grep -q " $agent "; then
        has_existing_dev=true
        break
      fi
    done
    if [ "$has_existing_dev" = false ]; then
      echo "Error: At least one dev stack is required."
      exit 1
    fi
  fi

  local selected_devs=""
  if [ -n "$dev_input" ]; then
    IFS=',' read -ra nums <<< "$dev_input"
    for num in "${nums[@]}"; do
      num=$(echo "$num" | tr -d ' ')
      if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le ${#dev_array[@]} ]; then
        selected_devs="$selected_devs ${dev_array[$((num - 1))]}"
      fi
    done
  fi

  # ── DevOps (optional) ──
  echo ""
  echo "Select infrastructure (optional — press Enter to skip):"
  local j=1
  local devop_array=()
  for agent in $DEVOP_AGENTS; do
    devop_array+=("$agent")
    local desc
    desc=$(parse_description "$agent")
    local marker=" "
    if echo " $existing " | grep -q " $agent "; then
      marker="*"
    fi
    printf "  [%d] %s %-18s %s\n" "$j" "$marker" "$agent" "$desc"
    j=$((j + 1))
  done
  echo ""

  local devop_input
  read -r -p "Enter numbers (comma-separated, press Enter to skip): " devop_input

  local selected_devops=""
  if [ -n "$devop_input" ]; then
    IFS=',' read -ra nums <<< "$devop_input"
    for num in "${nums[@]}"; do
      num=$(echo "$num" | tr -d ' ')
      if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le ${#devop_array[@]} ]; then
        selected_devops="$selected_devops ${devop_array[$((num - 1))]}"
      fi
    done
  fi

  # Merge with existing
  local all_selected=""
  for agent in $existing $selected_devs $selected_devops; do
    if ! echo " $all_selected " | grep -q " $agent "; then
      all_selected="$all_selected $agent"
    fi
  done
  all_selected=$(echo "$all_selected" | xargs)

  # Per-agent count (show existing count as default)
  echo ""
  echo "Agent count (press Enter to keep default):"
  local counts=""
  for agent in $all_selected; do
    local existing_count
    existing_count=$(detect_existing_count "$target" "$agent")
    local c
    read -r -p "  $agent [$existing_count]: " c
    c="${c:-$existing_count}"
    counts="$counts $agent:$c"
  done

  # ── Fizzy integration (optional) ──
  echo ""
  local fizzy_input
  read -r -p "Configure Fizzy sync? (y/N): " fizzy_input

  if [ "$fizzy_input" = "y" ] || [ "$fizzy_input" = "Y" ]; then
    # Detect existing fizzy config
    local existing_url existing_slug existing_board
    existing_url=""
    existing_slug=""
    existing_board=""
    if [ -f "$target/pipeline/config.json" ]; then
      existing_url=$(jq -r '.fizzy.url // empty' "$target/pipeline/config.json" 2>/dev/null)
      existing_slug=$(jq -r '.fizzy.accountSlug // empty' "$target/pipeline/config.json" 2>/dev/null)
      existing_board=$(jq -r '.fizzy.boardId // empty' "$target/pipeline/config.json" 2>/dev/null)
    fi

    echo ""
    echo "  Fizzy setup (press Enter to keep existing value):"

    local f_url
    if [ -n "$existing_url" ] && [ "$existing_url" != "https://your-fizzy.fly.dev" ]; then
      read -r -p "  Fizzy URL [$existing_url]: " f_url
      f_url="${f_url:-$existing_url}"
    else
      read -r -p "  Fizzy URL (e.g. https://fizzy.example.com): " f_url
    fi

    local f_slug
    if [ -n "$existing_slug" ] && [ "$existing_slug" != "your-account" ]; then
      read -r -p "  Account slug [$existing_slug]: " f_slug
      f_slug="${f_slug:-$existing_slug}"
    else
      read -r -p "  Account slug: " f_slug
    fi

    local f_token
    read -r -p "  API token (or \${FIZZY_TOKEN} for env var) [\${FIZZY_TOKEN}]: " f_token
    if [ -z "$f_token" ]; then
      f_token='${FIZZY_TOKEN}'
    fi

    local f_board
    if [ -n "$existing_board" ]; then
      read -r -p "  Board ID [$existing_board]: " f_board
      f_board="${f_board:-$existing_board}"
    else
      read -r -p "  Board ID (optional, press Enter to skip): " f_board
    fi

    if [ -n "$f_url" ] && [ -n "$f_slug" ]; then
      FIZZY_URL_VAL="$f_url"
      FIZZY_SLUG_VAL="$f_slug"
      FIZZY_TOKEN_VAL="$f_token"
      FIZZY_BOARD_VAL="${f_board:-}"
    else
      echo "  Skipped (URL and slug are required)."
    fi
  fi

  # Summary
  local skill_list
  skill_list=$(resolve_skills $all_selected)
  local skill_count
  skill_count=$(echo "$skill_list" | wc -l | tr -d ' ')
  local agent_count
  agent_count=$(echo "$all_selected" | wc -w | tr -d ' ')
  local total_agents=$((7 + agent_count))

  echo ""
  echo "Summary:"
  echo "  Agents: $total_agents (7 core + $all_selected)"
  echo "  Skills: $skill_count (deduped)"
  local has_custom_count=false
  for pair in $counts; do
    local name="${pair%%:*}"
    local cnt="${pair##*:}"
    if [ "$cnt" != "1" ]; then
      has_custom_count=true
      break
    fi
  done
  if [ "$has_custom_count" = true ]; then
    echo "  Counts:"
    for pair in $counts; do
      local name="${pair%%:*}"
      local cnt="${pair##*:}"
      printf "    %-20s x%s\n" "$name" "$cnt"
    done
  fi
  if [ -n "$FIZZY_URL_VAL" ]; then
    echo "  Fizzy:  $FIZZY_URL_VAL ($FIZZY_SLUG_VAL)"
  fi
  echo ""

  local confirm
  read -r -p "Install to $target? [Y/n]: " confirm
  if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
    echo "Aborted."
    exit 0
  fi

  # Set globals
  PICKED_AGENTS="$all_selected"
  AGENT_COUNTS="$(echo "$counts" | xargs)"
}

# ─── install ──────────────────────────────────────────────────────────────────
# Reads AGENT_COUNTS global for per-agent count patching
install() {
  local target="$1"
  shift
  local selected_agents="$*"

  echo ""
  echo "Installing claude-squad to $target ..."
  echo ""

  # Create directory structure
  mkdir -p "$target/agents"
  mkdir -p "$target/pipeline/agents"
  mkdir -p "$target/hooks"
  mkdir -p "$target/scripts"
  mkdir -p "$target/skills"

  # ── Copy core agents ──
  echo "  Copying agents..."
  for agent in $CORE_AGENTS; do
    cp "$AGENTS_DIR/$agent.md" "$target/agents/"
  done

  # ── Copy selected agents ──
  for agent in $selected_agents; do
    cp "$AGENTS_DIR/$agent.md" "$target/agents/"
  done

  local total_agent_files
  total_agent_files=$(ls "$target/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')

  # ── Copy pipeline config ──
  echo "  Copying pipeline configuration..."
  cp "$PIPELINE_DIR/config.json" "$target/pipeline/"

  # Core pipeline configs
  for config in $CORE_PIPELINE_CONFIGS; do
    cp "$PIPELINE_DIR/agents/$config.json" "$target/pipeline/agents/"
  done

  # Selected agent pipeline configs
  for agent in $selected_agents; do
    local config_file="$PIPELINE_DIR/agents/$agent.json"
    if [ -f "$config_file" ]; then
      cp "$config_file" "$target/pipeline/agents/"
    fi
  done

  # ── Patch Fizzy config ──
  if [ -n "$FIZZY_URL_VAL" ]; then
    echo "  Configuring Fizzy..."
    local tmp_cfg
    tmp_cfg=$(mktemp)
    jq --arg url "$FIZZY_URL_VAL" \
       --arg slug "$FIZZY_SLUG_VAL" \
       --arg ftoken "$FIZZY_TOKEN_VAL" \
       --arg bid "$FIZZY_BOARD_VAL" \
       '.fizzy.url = $url | .fizzy.accountSlug = $slug | .fizzy.token = $ftoken | .fizzy.sync = true | .fizzy.boardId = $bid' \
       "$target/pipeline/config.json" > "$tmp_cfg"
    mv "$tmp_cfg" "$target/pipeline/config.json"
  fi

  # ── Patch per-agent counts ──
  if [ -n "$AGENT_COUNTS" ]; then
    local patched=false
    for agent in $selected_agents; do
      local count
      count=$(get_agent_count "$agent")
      local target_config="$target/pipeline/agents/$agent.json"
      if [ -f "$target_config" ]; then
        # Always patch — source JSON defaults to 1, so we must restore any custom count
        if [ "$patched" = false ]; then
          echo "  Setting agent counts..."
          patched=true
        fi
        sed -i '' "s/\"count\": *[0-9]*/\"count\": $count/" "$target_config"
      fi
    done
  fi

  # ── Resolve and copy skills ──
  echo "  Copying skills..."
  local skill_list
  skill_list=$(resolve_skills $selected_agents)

  # Clean existing skills directory first (remove stale skills from prior installs)
  if [ -d "$target/skills" ]; then
    rm -rf "$target/skills"
    mkdir -p "$target/skills"
  fi

  local skill_count=0
  for skill in $skill_list; do
    local skill_src="$SKILLS_DIR/$skill"
    if [ -d "$skill_src" ]; then
      mkdir -p "$target/skills/$skill"
      cp "$skill_src"/* "$target/skills/$skill/" 2>/dev/null || true
      skill_count=$((skill_count + 1))
    fi
  done

  # ── Copy hooks ──
  echo "  Copying hooks..."
  cp "$SCRIPT_DIR"/hooks/*.sh "$target/hooks/"

  # ── Copy scripts ──
  echo "  Copying scripts..."
  for f in "$SCRIPT_DIR"/scripts/*.sh; do
    [ -f "$f" ] || continue
    local fname
    fname=$(basename "$f")
    # Skip test-setup.sh — it's for testing the installer itself
    if [ "$fname" = "test-setup.sh" ]; then
      continue
    fi
    cp "$f" "$target/scripts/"
  done

  # Copy script subdirectories (skill-prompts, etc.)
  for subdir in "$SCRIPT_DIR"/scripts/*/; do
    [ -d "$subdir" ] || continue
    local dirname
    dirname=$(basename "$subdir")
    # Skip result directories
    case "$dirname" in
      *-results) continue ;;
    esac
    mkdir -p "$target/scripts/$dirname"
    cp "$subdir"* "$target/scripts/$dirname/" 2>/dev/null || true
  done

  # ── Copy settings ──
  echo "  Copying settings..."
  cp "$SCRIPT_DIR/settings/settings.json" "$target/"

  # ── Copy templates ──
  if [ -d "$SCRIPT_DIR/templates" ]; then
    echo "  Copying templates..."
    mkdir -p "$target/templates"
    cp "$SCRIPT_DIR"/templates/* "$target/templates/" 2>/dev/null || true
  fi

  # ── Make executable ──
  chmod +x "$target"/hooks/*.sh 2>/dev/null || true
  chmod +x "$target"/scripts/*.sh 2>/dev/null || true

  # ── Summary ──
  local pipeline_count
  pipeline_count=$(ls "$target/pipeline/agents/"*.json 2>/dev/null | wc -l | tr -d ' ')

  echo ""
  echo "============================================"
  echo "  claude-squad installed successfully!"
  echo "============================================"
  echo ""
  echo "  Agents:           $total_agent_files"
  echo "  Skills:           $skill_count"
  echo "  Pipeline configs: $pipeline_count"
  echo "  Hooks:            $(ls "$target/hooks/"*.sh 2>/dev/null | wc -l | tr -d ' ')"
  echo "  Scripts:          $(ls "$target/scripts/"*.sh 2>/dev/null | wc -l | tr -d ' ')"
  echo ""
  echo "Installed agents:"
  echo "  Core:  $CORE_AGENTS"
  echo "  Stack: $selected_agents"
  if [ -n "$AGENT_COUNTS" ]; then
    local show_counts=false
    for agent in $selected_agents; do
      local cnt
      cnt=$(get_agent_count "$agent")
      if [ "$cnt" != "1" ]; then
        show_counts=true
        break
      fi
    done
    if [ "$show_counts" = true ]; then
      echo "  Counts:"
      for agent in $selected_agents; do
        local cnt
        cnt=$(get_agent_count "$agent")
        printf "    %-20s x%s\n" "$agent" "$cnt"
      done
    fi
  fi
  if [ -n "$FIZZY_URL_VAL" ]; then
    echo "  Fizzy:  enabled ($FIZZY_URL_VAL)"
  fi
  echo ""
  echo "Next steps:"
  echo "  1. Edit $target/agents/ba-agent.md to add your domain context"
  if [ -n "$FIZZY_URL_VAL" ]; then
    echo "  2. Set FIZZY_TOKEN env var if using \${FIZZY_TOKEN}"
    echo "  3. Run /pipeline <feature-description> to start"
    echo "  4. Run bash .claude/scripts/fizzy-sync.sh to push tasks to Fizzy"
  else
    echo "  2. Run /pipeline <feature-description> to start"
  fi
  echo ""
  echo "To add more agents later, just re-run setup.sh."
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

# Handle --list anywhere in args
for arg in "$@"; do
  if [ "$arg" = "--list" ]; then
    list_agents
    exit 0
  fi
done

# Handle --update: delegate to scripts/update.sh
UPDATE_MODE=false
UPDATE_ARGS=""
for arg in "$@"; do
  if [ "$arg" = "--update" ]; then
    UPDATE_MODE=true
  fi
done
if [ "$UPDATE_MODE" = true ]; then
  # Collect all args except --update
  UPDATE_TARGET=""
  for arg in "$@"; do
    if [ "$arg" = "--update" ]; then
      continue
    fi
    if [ -z "$UPDATE_TARGET" ]; then
      UPDATE_TARGET="$arg"
    else
      UPDATE_ARGS="$UPDATE_ARGS $arg"
    fi
  done
  if [ -z "$UPDATE_TARGET" ]; then
    echo "Usage: ./setup.sh /path/to/project --update [--dry-run] [--all]"
    exit 1
  fi
  exec bash "$SCRIPT_DIR/scripts/update.sh" "$UPDATE_TARGET" $UPDATE_ARGS
fi

# Need at least a target path
if [ -z "$1" ] || [[ "$1" == --* ]]; then
  echo "Usage:"
  echo "  ./setup.sh /path/to/project                              # Interactive picker"
  echo "  ./setup.sh /path/to/project --agents dev-rails,dev-node  # Non-interactive"
  echo "  ./setup.sh /path/to/project --agents dev-rails --count 2 # Set agent count"
  echo "  ./setup.sh /path/to/project --update                     # Update installed configs"
  echo "  ./setup.sh /path/to/project --fizzy                      # Configure Fizzy sync"
  echo "  ./setup.sh --list                                        # Show available agents"
  echo ""
  echo "This installs claude-squad into your project's .claude/ directory."
  exit 1
fi

TARGET_PROJECT="$1"
TARGET="$TARGET_PROJECT/.claude"
shift

# Parse remaining flags
AGENTS_FLAG=""
COUNT_FLAG=""
FIZZY_FLAG=""
FIZZY_ONLY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --agents)
      shift
      AGENTS_FLAG="$1"
      ;;
    --agents=*)
      AGENTS_FLAG="${1#--agents=}"
      ;;
    --count)
      shift
      COUNT_FLAG="$1"
      ;;
    --count=*)
      COUNT_FLAG="${1#--count=}"
      ;;
    --fizzy)
      if [ -z "$AGENTS_FLAG" ]; then
        FIZZY_ONLY=true
      fi
      # Consume next arg as value only if it exists and isn't a flag
      if [ $# -gt 1 ] && [[ "$2" != --* ]]; then
        shift
        FIZZY_FLAG="$1"
      fi
      ;;
    --fizzy=*)
      if [ -z "$AGENTS_FLAG" ]; then
        FIZZY_ONLY=true
      fi
      FIZZY_FLAG="${1#--fizzy=}"
      ;;
  esac
  shift
done

# ── Standalone --fizzy mode (no --agents) ──
if [ "$FIZZY_ONLY" = true ]; then
  CONFIG_FILE="$TARGET/pipeline/config.json"
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found. Run setup.sh first to install."
    exit 1
  fi
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for Fizzy configuration."
    exit 1
  fi

  if [ -n "$FIZZY_FLAG" ]; then
    # Non-interactive: parse url,slug,token,boardId
    IFS=',' read -r f_url f_slug f_token f_board <<< "$FIZZY_FLAG"
    if [ -z "$f_token" ]; then
      f_token='${FIZZY_TOKEN}'
    fi
  else
    # Interactive: prompt with existing values as defaults
    existing_url=$(jq -r '.fizzy.url // empty' "$CONFIG_FILE" 2>/dev/null)
    existing_slug=$(jq -r '.fizzy.accountSlug // empty' "$CONFIG_FILE" 2>/dev/null)
    existing_board=$(jq -r '.fizzy.boardId // empty' "$CONFIG_FILE" 2>/dev/null)

    echo "Fizzy sync configuration"
    echo ""

    if [ -n "$existing_url" ] && [ "$existing_url" != "https://your-fizzy.fly.dev" ]; then
      read -r -p "  Fizzy URL [$existing_url]: " f_url
      f_url="${f_url:-$existing_url}"
    else
      read -r -p "  Fizzy URL (e.g. https://fizzy.example.com): " f_url
    fi

    if [ -n "$existing_slug" ] && [ "$existing_slug" != "your-account" ]; then
      read -r -p "  Account slug [$existing_slug]: " f_slug
      f_slug="${f_slug:-$existing_slug}"
    else
      read -r -p "  Account slug: " f_slug
    fi

    read -r -p "  API token (or \${FIZZY_TOKEN} for env var) [\${FIZZY_TOKEN}]: " f_token
    if [ -z "$f_token" ]; then
      f_token='${FIZZY_TOKEN}'
    fi

    if [ -n "$existing_board" ]; then
      read -r -p "  Board ID [$existing_board]: " f_board
      f_board="${f_board:-$existing_board}"
    else
      read -r -p "  Board ID (optional, press Enter to skip): " f_board
    fi
  fi

  if [ -z "$f_url" ] || [ -z "$f_slug" ]; then
    echo "Error: Fizzy URL and account slug are required."
    exit 1
  fi

  tmp_cfg=$(mktemp)
  jq --arg url "$f_url" \
     --arg slug "$f_slug" \
     --arg ftoken "$f_token" \
     --arg bid "${f_board:-}" \
     '.fizzy.url = $url | .fizzy.accountSlug = $slug | .fizzy.token = $ftoken | .fizzy.sync = true | .fizzy.boardId = $bid' \
     "$CONFIG_FILE" > "$tmp_cfg"
  mv "$tmp_cfg" "$CONFIG_FILE"

  # Also sync fizzy-sync.sh to ensure the script is up to date
  FIZZY_SCRIPT_SRC="$SCRIPT_DIR/scripts/fizzy-sync.sh"
  FIZZY_SCRIPT_DST="$TARGET/scripts/fizzy-sync.sh"
  if [ -f "$FIZZY_SCRIPT_SRC" ]; then
    mkdir -p "$TARGET/scripts"
    cp "$FIZZY_SCRIPT_SRC" "$FIZZY_SCRIPT_DST"
    chmod +x "$FIZZY_SCRIPT_DST"
  fi

  echo ""
  echo "Fizzy configured:"
  echo "  URL:     $f_url"
  echo "  Slug:    $f_slug"
  echo "  Token:   $f_token"
  echo "  Board:   ${f_board:-(not set)}"
  echo ""
  echo "To sync tasks: bash .claude/scripts/fizzy-sync.sh"
  exit 0
fi

if [ -n "$AGENTS_FLAG" ]; then
  # ── Non-interactive mode ──
  # Parse comma-separated agent names
  SELECTED=$(echo "$AGENTS_FLAG" | tr ',' ' ')

  # Validate agent names
  for agent in $SELECTED; do
    if [ ! -f "$AGENTS_DIR/$agent.md" ]; then
      echo "Error: Unknown agent '$agent'"
      echo ""
      echo "Available agents:"
      for a in $DEV_AGENTS $DEVOP_AGENTS; do
        echo "  $a"
      done
      exit 1
    fi
  done

  # Merge with existing
  EXISTING=$(detect_existing "$TARGET")
  ALL_SELECTED=""
  for agent in $EXISTING $SELECTED; do
    if ! echo " $ALL_SELECTED " | grep -q " $agent "; then
      ALL_SELECTED="$ALL_SELECTED $agent"
    fi
  done
  ALL_SELECTED=$(echo "$ALL_SELECTED" | xargs)

  # Build AGENT_COUNTS: --count overrides new agents, existing agents keep their counts
  AGENT_COUNTS=""
  for agent in $ALL_SELECTED; do
    EXISTING_COUNT=$(detect_existing_count "$TARGET" "$agent")
    if [ -n "$COUNT_FLAG" ] && echo " $SELECTED " | grep -q " $agent "; then
      # Explicitly selected this run — use --count flag
      AGENT_COUNTS="$AGENT_COUNTS $agent:$COUNT_FLAG"
    else
      # Existing agent from prior install — preserve its count
      AGENT_COUNTS="$AGENT_COUNTS $agent:$EXISTING_COUNT"
    fi
  done
  AGENT_COUNTS=$(echo "$AGENT_COUNTS" | xargs)

  # Parse --fizzy url,slug,token,boardId
  if [ -n "$FIZZY_FLAG" ]; then
    IFS=',' read -r FIZZY_URL_VAL FIZZY_SLUG_VAL FIZZY_TOKEN_VAL FIZZY_BOARD_VAL <<< "$FIZZY_FLAG"
    if [ -z "$FIZZY_TOKEN_VAL" ]; then
      FIZZY_TOKEN_VAL='${FIZZY_TOKEN}'
    fi
  fi

  install "$TARGET" $ALL_SELECTED
else
  # ── Interactive mode ──
  # interactive_picker sets PICKED_AGENTS and AGENT_COUNTS globals
  interactive_picker "$TARGET"

  install "$TARGET" $PICKED_AGENTS
fi
