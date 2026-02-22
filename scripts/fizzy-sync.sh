#!/bin/bash
# Fizzy sync — push tasks.json to a Fizzy kanban board
#
# Usage:
#   bash .claude/scripts/fizzy-sync.sh           # Push all tasks to Fizzy
#
# Like kanban.sh but pushes tasks to your Fizzy board instead of
# displaying them in the terminal. Creates new cards for unsynced
# tasks and updates existing ones.
#
# Configuration: .claude/pipeline/config.json → fizzy section
# Environment:   FIZZY_TOKEN (overrides config token)

set -e

CONFIG=".claude/pipeline/config.json"
TASKS_FILE="tasks.json"

# ─── Prerequisites ───────────────────────────────────────────────────────────

if [ ! -f "$CONFIG" ]; then
  echo "Error: $CONFIG not found. Run from project root."
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "Error: jq is required. Install with: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

if [ ! -f "$TASKS_FILE" ]; then
  echo "No $TASKS_FILE found. Run /pipeline first."
  exit 1
fi

# ─── Read Fizzy Config ───────────────────────────────────────────────────────

FIZZY_URL=$(jq -r '.fizzy.url // empty' "$CONFIG")
ACCOUNT_SLUG=$(jq -r '.fizzy.accountSlug // empty' "$CONFIG")
FIZZY_SYNC=$(jq -r '.fizzy.sync // false' "$CONFIG")
BOARD_ID=$(jq -r '.fizzy.boardId // empty' "$CONFIG")

# Token: env var takes precedence
CONFIG_TOKEN=$(jq -r '.fizzy.token // empty' "$CONFIG")
if [ -n "${FIZZY_TOKEN:-}" ]; then
  TOKEN="$FIZZY_TOKEN"
elif [ "$CONFIG_TOKEN" != '${FIZZY_TOKEN}' ] && [ -n "$CONFIG_TOKEN" ]; then
  TOKEN="$CONFIG_TOKEN"
else
  TOKEN=""
fi

# Column mapping (task status → Fizzy column name)
COL_TODO=$(jq -r '.fizzy.columnMap.todo // "Not now"' "$CONFIG")
COL_IN_PROGRESS=$(jq -r '.fizzy.columnMap.in_progress // "Now"' "$CONFIG")
COL_REVIEW=$(jq -r '.fizzy.columnMap.review // "Maybe"' "$CONFIG")
COL_DONE=$(jq -r '.fizzy.columnMap.done // "Done"' "$CONFIG")

# ─── Validate ────────────────────────────────────────────────────────────────

ERRORS=0

if [ "$FIZZY_SYNC" != "true" ]; then
  echo "Fizzy sync is disabled."
  echo "Enable it by setting fizzy.sync to true in $CONFIG"
  echo "  or configure Fizzy during setup: ./setup.sh /path/to/project"
  exit 0
fi

if [ -z "$FIZZY_URL" ]; then
  echo "Error: fizzy.url not set in $CONFIG"
  ERRORS=$((ERRORS + 1))
fi
if [ -z "$ACCOUNT_SLUG" ]; then
  echo "Error: fizzy.accountSlug not set in $CONFIG"
  ERRORS=$((ERRORS + 1))
fi
if [ -z "$TOKEN" ]; then
  echo "Error: No Fizzy token. Set FIZZY_TOKEN env var."
  ERRORS=$((ERRORS + 1))
fi
if [ -z "$BOARD_ID" ]; then
  echo "Error: fizzy.boardId not set in $CONFIG"
  ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi

# ─── API Helper ──────────────────────────────────────────────────────────────

HTTP_STATUS=""

fizzy_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local url="${FIZZY_URL}/${ACCOUNT_SLUG}${endpoint}"

  local tmp_file
  tmp_file=$(mktemp)

  local curl_args=(
    -s -w "%{http_code}"
    -H "Authorization: Bearer $TOKEN"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
    -o "$tmp_file"
  )

  if [ "$method" != "GET" ]; then
    curl_args+=(-X "$method")
    if [ -n "$data" ]; then
      curl_args+=(-d "$data")
    fi
  fi

  HTTP_STATUS=$(curl "${curl_args[@]}" "$url")
  cat "$tmp_file"
  rm -f "$tmp_file"
}

# ─── Resolve Columns ────────────────────────────────────────────────────────

COLUMN_CACHE=""

resolve_columns() {
  local response
  response=$(fizzy_api GET "/boards/$BOARD_ID")

  if [ "$HTTP_STATUS" != "200" ]; then
    echo "Error: Failed to fetch board $BOARD_ID (HTTP $HTTP_STATUS)"
    exit 1
  fi

  COLUMN_CACHE=$(echo "$response" | jq -r '.columns[] | "\(.name):\(.id)"')
}

get_column_id() {
  echo "$COLUMN_CACHE" | grep "^${1}:" | head -1 | cut -d: -f2
}

status_to_column_id() {
  case "$1" in
    todo)        get_column_id "$COL_TODO" ;;
    in_progress) get_column_id "$COL_IN_PROGRESS" ;;
    review)      get_column_id "$COL_REVIEW" ;;
    done)        get_column_id "$COL_DONE" ;;
    *)           get_column_id "$COL_TODO" ;;
  esac
}

# ─── Push Tasks ──────────────────────────────────────────────────────────────

resolve_columns

PROJECT=$(jq -r '.project // "Untitled"' "$TASKS_FILE")
TASK_COUNT=$(jq '[.phases[].tasks[]] | length' "$TASKS_FILE")

echo ""
echo "Fizzy sync: $PROJECT"
echo "════════════════════════════════════"
echo "Pushing $TASK_COUNT tasks to $FIZZY_URL ..."
echo ""

CREATED=0
UPDATED=0
SKIPPED=0

PHASES=$(jq -r '.phases | length' "$TASKS_FILE")

for ((p=0; p<PHASES; p++)); do
  PHASE_NAME=$(jq -r ".phases[$p].name // \"Phase $((p+1))\"" "$TASKS_FILE")
  TASKS=$(jq -r ".phases[$p].tasks | length" "$TASKS_FILE")

  for ((t=0; t<TASKS; t++)); do
    TASK_ID=$(jq -r ".phases[$p].tasks[$t].id" "$TASKS_FILE")
    TASK_TITLE=$(jq -r ".phases[$p].tasks[$t].title" "$TASKS_FILE")
    TASK_STATUS=$(jq -r ".phases[$p].tasks[$t].status" "$TASKS_FILE")
    TASK_TAGS=$(jq -r ".phases[$p].tasks[$t].tags // [] | join(\", \")" "$TASKS_FILE")
    FIZZY_CARD=$(jq -r ".phases[$p].tasks[$t].fizzyCard // empty" "$TASKS_FILE")

    COLUMN_ID=$(status_to_column_id "$TASK_STATUS")

    if [ -z "$COLUMN_ID" ]; then
      echo "  SKIP  $TASK_ID: $TASK_TITLE (no column for '$TASK_STATUS')"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    BODY="**Task:** $TASK_ID | **Phase:** $PHASE_NAME | **Tags:** $TASK_TAGS"

    if [ -n "$FIZZY_CARD" ]; then
      # Update existing card
      UPDATE_DATA=$(jq -n \
        --arg title "$TASK_TITLE" \
        --arg body "$BODY" \
        --arg col "$COLUMN_ID" \
        '{"title": $title, "body": $body, "column_id": ($col | tonumber)}')

      fizzy_api PATCH "/cards/$FIZZY_CARD" "$UPDATE_DATA" > /dev/null

      if [ "$HTTP_STATUS" = "200" ]; then
        echo "  UPDATE  #$FIZZY_CARD  $TASK_TITLE  [$TASK_STATUS]"
        UPDATED=$((UPDATED + 1))
      else
        echo "  ERROR   #$FIZZY_CARD  $TASK_TITLE  (HTTP $HTTP_STATUS)"
        SKIPPED=$((SKIPPED + 1))
      fi
    else
      # Create new card
      CREATE_DATA=$(jq -n \
        --arg title "$TASK_TITLE" \
        --arg body "$BODY" \
        --arg bid "$BOARD_ID" \
        --arg col "$COLUMN_ID" \
        '{"title": $title, "body": $body, "board_id": ($bid | tonumber), "column_id": ($col | tonumber)}')

      RESPONSE=$(fizzy_api POST "/cards" "$CREATE_DATA")

      if [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "200" ]; then
        CARD_NUM=$(echo "$RESPONSE" | jq -r '.number')

        # Save card number back to tasks.json
        TMP=$(mktemp)
        jq ".phases[$p].tasks[$t].fizzyCard = $CARD_NUM" "$TASKS_FILE" > "$TMP"
        mv "$TMP" "$TASKS_FILE"

        echo "  CREATE  #$CARD_NUM  $TASK_TITLE  [$TASK_STATUS]"
        CREATED=$((CREATED + 1))
      else
        echo "  ERROR   $TASK_TITLE  (HTTP $HTTP_STATUS)"
        SKIPPED=$((SKIPPED + 1))
      fi
    fi
  done
done

echo ""
echo "Done: $CREATED created, $UPDATED updated, $SKIPPED skipped"
echo ""
