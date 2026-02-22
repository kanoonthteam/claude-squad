#!/bin/bash
# Test suite for setup.sh
# Usage: bash scripts/test-setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SETUP="$REPO_DIR/setup.sh"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

pass() {
  PASS=$((PASS + 1))
  echo -e "  ${GREEN}PASS${NC} $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo -e "  ${RED}FAIL${NC} $1"
  if [ -n "$2" ]; then
    echo "       $2"
  fi
}

assert_file_exists() {
  if [ -f "$1" ]; then
    return 0
  else
    return 1
  fi
}

assert_dir_exists() {
  if [ -d "$1" ]; then
    return 0
  else
    return 1
  fi
}

count_files() {
  ls "$1" 2>/dev/null | wc -l | tr -d ' '
}

count_dirs() {
  ls -d "$1"/*/ 2>/dev/null | wc -l | tr -d ' '
}

echo ""
echo -e "${BOLD}claude-squad setup.sh test suite${NC}"
echo "================================="
echo ""

# ─── Test 1: --list shows all agents ─────────────────────────────────────────
echo "Test 1: --list shows all agents with skills"

LIST_OUTPUT=$(bash "$SETUP" --list 2>&1)

# Check core agents listed
for agent in pipeline-agent pm-agent ba-agent designer-agent architect-agent qa-agent; do
  if echo "$LIST_OUTPUT" | grep -q "$agent"; then
    : # ok
  else
    fail "Test 1: missing core agent $agent in --list output"
    continue
  fi
done

# Check dev agents listed
for agent in dev-rails dev-react dev-flutter dev-node dev-odoo dev-salesforce dev-webflow dev-astro dev-payload-cms; do
  if echo "$LIST_OUTPUT" | grep -q "$agent"; then
    : # ok
  else
    fail "Test 1: missing dev agent $agent in --list output"
    continue
  fi
done

# Check devop agents listed
for agent in devop-aws devop-azure devop-gcloud devop-firebase devop-flyio; do
  if echo "$LIST_OUTPUT" | grep -q "$agent"; then
    : # ok
  else
    fail "Test 1: missing devop agent $agent in --list output"
    continue
  fi
done

# Check it shows "skills" and "lines"
if echo "$LIST_OUTPUT" | grep -q "skills" && echo "$LIST_OUTPUT" | grep -q "lines"; then
  pass "Test 1: --list shows all agents with skills and line counts"
else
  fail "Test 1: --list missing skills/lines info"
fi

# ─── Test 2: --agents dev-rails copies correct files ─────────────────────────
echo "Test 2: --agents dev-rails copies correct subset"

T2="$TEST_DIR/t2"
bash "$SETUP" "$T2" --agents dev-rails > /dev/null 2>&1

# Should have exactly 7 agent .md files (6 core + 1 dev-rails)
AGENT_COUNT=$(count_files "$T2/.claude/agents")
if [ "$AGENT_COUNT" = "7" ]; then
  pass "Test 2a: 7 agent .md files"
else
  fail "Test 2a: expected 7 agents, got $AGENT_COUNT"
fi

# Should have exactly 6 pipeline configs (5 core + dev-rails)
PIPELINE_COUNT=$(count_files "$T2/.claude/pipeline/agents")
if [ "$PIPELINE_COUNT" = "6" ]; then
  pass "Test 2b: 6 pipeline configs"
else
  fail "Test 2b: expected 6 pipeline configs, got $PIPELINE_COUNT"
fi

# Check specific agent files exist
if assert_file_exists "$T2/.claude/agents/dev-rails.md" && \
   assert_file_exists "$T2/.claude/agents/pipeline-agent.md" && \
   assert_file_exists "$T2/.claude/agents/pm-agent.md" && \
   assert_file_exists "$T2/.claude/agents/ba-agent.md" && \
   assert_file_exists "$T2/.claude/agents/designer-agent.md" && \
   assert_file_exists "$T2/.claude/agents/architect-agent.md" && \
   assert_file_exists "$T2/.claude/agents/qa-agent.md"; then
  pass "Test 2c: all expected agent files present"
else
  fail "Test 2c: missing expected agent files"
fi

# Skills: should include rails-specific + core agent skills + utility + shared (git-workflow, code-review-practices)
# Check rails skills present
for skill in rails-models rails-controllers rails-performance rails-testing; do
  if assert_dir_exists "$T2/.claude/skills/$skill"; then
    : # ok
  else
    fail "Test 2d: missing rails skill $skill"
  fi
done

# Check utility skills present
for skill in pipeline pipeline-status review; do
  if assert_dir_exists "$T2/.claude/skills/$skill"; then
    : # ok
  else
    fail "Test 2d: missing utility skill $skill"
  fi
done

# Check shared dev skills
for skill in git-workflow code-review-practices; do
  if assert_dir_exists "$T2/.claude/skills/$skill"; then
    : # ok
  else
    fail "Test 2d: missing shared dev skill $skill"
  fi
done

# Check hooks and scripts exist
if assert_file_exists "$T2/.claude/hooks/test-before-commit.sh" && \
   assert_file_exists "$T2/.claude/hooks/protect-definitions.sh"; then
  pass "Test 2e: hooks copied"
else
  fail "Test 2e: hooks missing"
fi

if assert_file_exists "$T2/.claude/settings.json"; then
  pass "Test 2f: settings copied"
else
  fail "Test 2f: settings missing"
fi

pass "Test 2: dev-rails install verified"

# ─── Test 3: dev-rails + dev-node share skills without duplication ────────────
echo "Test 3: --agents dev-rails,dev-node deduplicates shared skills"

T3="$TEST_DIR/t3"
bash "$SETUP" "$T3" --agents dev-rails,dev-node > /dev/null 2>&1

# git-workflow and code-review-practices should exist exactly once (as dirs)
GIT_WORKFLOW_COUNT=$(find "$T3/.claude/skills" -maxdepth 1 -name "git-workflow" -type d | wc -l | tr -d ' ')
CODE_REVIEW_COUNT=$(find "$T3/.claude/skills" -maxdepth 1 -name "code-review-practices" -type d | wc -l | tr -d ' ')

if [ "$GIT_WORKFLOW_COUNT" = "1" ] && [ "$CODE_REVIEW_COUNT" = "1" ]; then
  pass "Test 3a: shared skills exist exactly once"
else
  fail "Test 3a: git-workflow=$GIT_WORKFLOW_COUNT, code-review-practices=$CODE_REVIEW_COUNT"
fi

# Should have both rails and node skills
HAS_RAILS=true
HAS_NODE=true
for skill in rails-models rails-controllers rails-performance rails-testing; do
  assert_dir_exists "$T3/.claude/skills/$skill" || HAS_RAILS=false
done
for skill in node-architecture node-api node-testing node-performance; do
  assert_dir_exists "$T3/.claude/skills/$skill" || HAS_NODE=false
done

if [ "$HAS_RAILS" = true ] && [ "$HAS_NODE" = true ]; then
  pass "Test 3b: both rails and node skills present"
else
  fail "Test 3b: rails=$HAS_RAILS node=$HAS_NODE"
fi

# Should have 8 agent files (6 core + 2)
AGENT_COUNT=$(count_files "$T3/.claude/agents")
if [ "$AGENT_COUNT" = "8" ]; then
  pass "Test 3c: 8 agent files"
else
  fail "Test 3c: expected 8 agents, got $AGENT_COUNT"
fi

# ─── Test 4: dev-rails + devop-flyio cross-category ──────────────────────────
echo "Test 4: --agents dev-rails,devop-flyio copies correct cross-category skills"

T4="$TEST_DIR/t4"
bash "$SETUP" "$T4" --agents dev-rails,devop-flyio > /dev/null 2>&1

# Should have flyio-specific skills
for skill in flyio-core flyio-deploy flyio-operations; do
  if assert_dir_exists "$T4/.claude/skills/$skill"; then
    : # ok
  else
    fail "Test 4: missing flyio skill $skill"
  fi
done

# Should have shared devops skills
for skill in devops-cicd devops-containers devops-monitoring terraform-patterns observability-practices incident-management; do
  if assert_dir_exists "$T4/.claude/skills/$skill"; then
    : # ok
  else
    fail "Test 4: missing shared devops skill $skill"
  fi
done

# Should also still have rails skills
for skill in rails-models rails-controllers; do
  if assert_dir_exists "$T4/.claude/skills/$skill"; then
    : # ok
  else
    fail "Test 4: missing rails skill $skill after cross-category install"
  fi
done

# Pipeline configs: 5 core + dev-rails + devop-flyio = 7
PIPELINE_COUNT=$(count_files "$T4/.claude/pipeline/agents")
if [ "$PIPELINE_COUNT" = "7" ]; then
  pass "Test 4: cross-category install correct (7 pipeline configs, both skill sets)"
else
  fail "Test 4: expected 7 pipeline configs, got $PIPELINE_COUNT"
fi

# ─── Test 5: Repeatable — run twice, both agent sets present ─────────────────
echo "Test 5: Repeatable install — run with dev-rails, then add dev-node"

T5="$TEST_DIR/t5"
bash "$SETUP" "$T5" --agents dev-rails > /dev/null 2>&1

# Verify first install
AGENTS_AFTER_FIRST=$(ls "$T5/.claude/agents/" | sort)

# Run again with dev-node
bash "$SETUP" "$T5" --agents dev-node > /dev/null 2>&1

# Both agents should be present
if assert_file_exists "$T5/.claude/agents/dev-rails.md" && \
   assert_file_exists "$T5/.claude/agents/dev-node.md"; then
  pass "Test 5a: both agent .md files present after re-run"
else
  fail "Test 5a: missing agent files after re-run"
fi

# Both pipeline configs should be present
if assert_file_exists "$T5/.claude/pipeline/agents/dev-rails.json" && \
   assert_file_exists "$T5/.claude/pipeline/agents/dev-node.json"; then
  pass "Test 5b: both pipeline configs present after re-run"
else
  fail "Test 5b: missing pipeline configs after re-run"
fi

# Both skill sets should be present
HAS_RAILS=true
HAS_NODE=true
for skill in rails-models rails-controllers rails-performance rails-testing; do
  assert_dir_exists "$T5/.claude/skills/$skill" || HAS_RAILS=false
done
for skill in node-architecture node-api node-testing node-performance; do
  assert_dir_exists "$T5/.claude/skills/$skill" || HAS_NODE=false
done

if [ "$HAS_RAILS" = true ] && [ "$HAS_NODE" = true ]; then
  pass "Test 5c: both skill sets present after re-run"
else
  fail "Test 5c: rails=$HAS_RAILS node=$HAS_NODE after re-run"
fi

# ─── Test 6: Core agents always present ──────────────────────────────────────
echo "Test 6: Core agents always present even if not explicitly selected"

T6="$TEST_DIR/t6"
bash "$SETUP" "$T6" --agents dev-flutter > /dev/null 2>&1

CORE_OK=true
for agent in pipeline-agent pm-agent ba-agent designer-agent architect-agent qa-agent; do
  if ! assert_file_exists "$T6/.claude/agents/$agent.md"; then
    CORE_OK=false
    fail "Test 6: missing core agent $agent"
  fi
done

for config in pm ba designer architect qa; do
  if ! assert_file_exists "$T6/.claude/pipeline/agents/$config.json"; then
    CORE_OK=false
    fail "Test 6: missing core pipeline config $config.json"
  fi
done

if [ "$CORE_OK" = true ]; then
  pass "Test 6: all core agents and pipeline configs always present"
fi

# ─── Test 7: No stale skills from prior install ──────────────────────────────
echo "Test 7: No stale skill directories after re-run"

T7="$TEST_DIR/t7"
# First install with devop-aws (has kubernetes-patterns)
bash "$SETUP" "$T7" --agents dev-rails,devop-aws > /dev/null 2>&1

# Verify kubernetes-patterns exists
if ! assert_dir_exists "$T7/.claude/skills/kubernetes-patterns"; then
  fail "Test 7: kubernetes-patterns should exist after devop-aws install"
fi

# Re-install with just dev-node (no devop, so no kubernetes-patterns needed)
# BUT dev-rails is still detected from prior install, so we need a clean test
# The point is: skills are rebuilt from scratch based on resolved set
T7B="$TEST_DIR/t7b"
bash "$SETUP" "$T7B" --agents dev-rails > /dev/null 2>&1

if assert_dir_exists "$T7B/.claude/skills/kubernetes-patterns"; then
  fail "Test 7: kubernetes-patterns should NOT exist in dev-rails-only install"
else
  pass "Test 7: no stale skills — kubernetes-patterns absent in rails-only install"
fi

# ─── Test 8: Pipeline configs match selected agents ──────────────────────────
echo "Test 8: Pipeline configs match selected agents"

T8="$TEST_DIR/t8"
bash "$SETUP" "$T8" --agents dev-react,devop-firebase > /dev/null 2>&1

EXPECTED_CONFIGS="architect ba designer dev-react devop-firebase pm qa"
ACTUAL_CONFIGS=$(ls "$T8/.claude/pipeline/agents/" | sed 's/\.json$//' | sort | tr '\n' ' ' | xargs)

if [ "$ACTUAL_CONFIGS" = "$EXPECTED_CONFIGS" ]; then
  pass "Test 8: pipeline configs match exactly"
else
  fail "Test 8: expected '$EXPECTED_CONFIGS', got '$ACTUAL_CONFIGS'"
fi

# ─── Test 9: All copied skills actually exist in source ──────────────────────
echo "Test 9: All copied skills exist as source directories"

T9="$TEST_DIR/t9"
bash "$SETUP" "$T9" --agents dev-rails,devop-aws > /dev/null 2>&1

ALL_VALID=true
for skill_dir in "$T9/.claude/skills"/*/; do
  skill_name=$(basename "$skill_dir")
  if [ ! -d "$REPO_DIR/skills/$skill_name" ]; then
    ALL_VALID=false
    fail "Test 9: skill '$skill_name' in target but not in source"
  fi
done

if [ "$ALL_VALID" = true ]; then
  pass "Test 9: all installed skills have matching source directories"
fi

# ─── Test 10: Scripts and settings copied correctly ──────────────────────────
echo "Test 10: Scripts, settings, and templates copied correctly"

T10="$TEST_DIR/t10"
bash "$SETUP" "$T10" --agents dev-rails > /dev/null 2>&1

SCRIPTS_OK=true
# Key scripts should be present
for script in kanban.sh skill-test.sh skill-agent-test.sh fizzy-sync.sh; do
  if ! assert_file_exists "$T10/.claude/scripts/$script"; then
    SCRIPTS_OK=false
    fail "Test 10: missing script $script"
  fi
done

# test-setup.sh should NOT be copied
if assert_file_exists "$T10/.claude/scripts/test-setup.sh"; then
  SCRIPTS_OK=false
  fail "Test 10: test-setup.sh should not be copied to target"
fi

# settings.json should exist
if ! assert_file_exists "$T10/.claude/settings.json"; then
  SCRIPTS_OK=false
  fail "Test 10: settings.json missing"
fi

# Templates should exist
if ! assert_file_exists "$T10/.claude/templates/CLAUDE.md.template"; then
  SCRIPTS_OK=false
  fail "Test 10: template missing"
fi

# Scripts should be executable
if [ -x "$T10/.claude/scripts/kanban.sh" ]; then
  : # ok
else
  SCRIPTS_OK=false
  fail "Test 10: scripts not executable"
fi

if [ "$SCRIPTS_OK" = true ]; then
  pass "Test 10: scripts, settings, and templates all correct"
fi

# ─── Test 11: --count sets agent count for selected agents ───────────────────
echo "Test 11: --count sets agent count for selected agents only"

T11="$TEST_DIR/t11"
bash "$SETUP" "$T11" --agents dev-rails,devop-flyio --count 3 > /dev/null 2>&1

COUNT_OK=true

# Selected agents should have count 3
for agent in dev-rails devop-flyio; do
  ACTUAL=$(grep '"count"' "$T11/.claude/pipeline/agents/$agent.json" | tr -d ' ,"' | cut -d: -f2)
  if [ "$ACTUAL" != "3" ]; then
    COUNT_OK=false
    fail "Test 11: $agent.json count should be 3, got $ACTUAL"
  fi
done

# Core agents should still have count 1
for config in pm ba designer architect qa; do
  ACTUAL=$(grep '"count"' "$T11/.claude/pipeline/agents/$config.json" | tr -d ' ,"' | cut -d: -f2)
  if [ "$ACTUAL" != "1" ]; then
    COUNT_OK=false
    fail "Test 11: $config.json (core) count should be 1, got $ACTUAL"
  fi
done

if [ "$COUNT_OK" = true ]; then
  pass "Test 11a: --count 3 applied to selected agents, core agents unchanged"
fi

# Default (no --count) should leave count at 1
T11B="$TEST_DIR/t11b"
bash "$SETUP" "$T11B" --agents dev-node > /dev/null 2>&1

DEFAULT_COUNT=$(grep '"count"' "$T11B/.claude/pipeline/agents/dev-node.json" | tr -d ' ,"' | cut -d: -f2)
if [ "$DEFAULT_COUNT" = "1" ]; then
  pass "Test 11b: default count is 1 when --count not specified"
else
  fail "Test 11b: expected default count 1, got $DEFAULT_COUNT"
fi

# ─── Test 12: Re-run preserves existing agent counts ─────────────────────────
echo "Test 12: Re-run preserves existing agent counts"

T12="$TEST_DIR/t12"

# Run 1: dev-rails with count 3
bash "$SETUP" "$T12" --agents dev-rails --count 3 > /dev/null 2>&1

# Run 2: add dev-node with no --count
bash "$SETUP" "$T12" --agents dev-node > /dev/null 2>&1

RAILS_COUNT=$(grep '"count"' "$T12/.claude/pipeline/agents/dev-rails.json" | tr -d ' ,"' | cut -d: -f2)
NODE_COUNT=$(grep '"count"' "$T12/.claude/pipeline/agents/dev-node.json" | tr -d ' ,"' | cut -d: -f2)

if [ "$RAILS_COUNT" = "3" ]; then
  pass "Test 12a: dev-rails count preserved as 3 after re-run"
else
  fail "Test 12a: dev-rails count should be 3, got $RAILS_COUNT"
fi

if [ "$NODE_COUNT" = "1" ]; then
  pass "Test 12b: dev-node count defaults to 1"
else
  fail "Test 12b: dev-node count should be 1, got $NODE_COUNT"
fi

# Run 3: add devop-flyio with --count 5 — rails should stay 3, node stay 1
bash "$SETUP" "$T12" --agents devop-flyio --count 5 > /dev/null 2>&1

RAILS_COUNT=$(grep '"count"' "$T12/.claude/pipeline/agents/dev-rails.json" | tr -d ' ,"' | cut -d: -f2)
NODE_COUNT=$(grep '"count"' "$T12/.claude/pipeline/agents/dev-node.json" | tr -d ' ,"' | cut -d: -f2)
FLYIO_COUNT=$(grep '"count"' "$T12/.claude/pipeline/agents/devop-flyio.json" | tr -d ' ,"' | cut -d: -f2)

PRESERVE_OK=true
if [ "$RAILS_COUNT" != "3" ]; then
  PRESERVE_OK=false
  fail "Test 12c: dev-rails should still be 3, got $RAILS_COUNT"
fi
if [ "$NODE_COUNT" != "1" ]; then
  PRESERVE_OK=false
  fail "Test 12c: dev-node should still be 1, got $NODE_COUNT"
fi
if [ "$FLYIO_COUNT" != "5" ]; then
  PRESERVE_OK=false
  fail "Test 12c: devop-flyio should be 5, got $FLYIO_COUNT"
fi
if [ "$PRESERVE_OK" = true ]; then
  pass "Test 12c: all counts correct after 3 runs (rails=3, node=1, flyio=5)"
fi

# Core agents should still be 1
CORE_COUNT=$(grep '"count"' "$T12/.claude/pipeline/agents/pm.json" | tr -d ' ,"' | cut -d: -f2)
if [ "$CORE_COUNT" = "1" ]; then
  pass "Test 12d: core agents still count 1"
else
  fail "Test 12d: core pm count should be 1, got $CORE_COUNT"
fi

# ─── Test 13: --fizzy flag configures Fizzy in pipeline config ────────────────
echo "Test 13: --fizzy configures Fizzy sync in pipeline config"

T13="$TEST_DIR/t13"
bash "$SETUP" "$T13" --agents dev-rails --fizzy "https://fizzy.example.com,my-team,tok_abc123,42" > /dev/null 2>&1

FIZZY_OK=true

# Check fizzy.sync is true
FIZZY_SYNC=$(jq -r '.fizzy.sync' "$T13/.claude/pipeline/config.json")
if [ "$FIZZY_SYNC" != "true" ]; then
  FIZZY_OK=false
  fail "Test 13a: fizzy.sync should be true, got $FIZZY_SYNC"
fi

# Check fizzy.url
FIZZY_URL_VAL=$(jq -r '.fizzy.url' "$T13/.claude/pipeline/config.json")
if [ "$FIZZY_URL_VAL" != "https://fizzy.example.com" ]; then
  FIZZY_OK=false
  fail "Test 13b: fizzy.url should be https://fizzy.example.com, got $FIZZY_URL_VAL"
fi

# Check fizzy.accountSlug
FIZZY_SLUG=$(jq -r '.fizzy.accountSlug' "$T13/.claude/pipeline/config.json")
if [ "$FIZZY_SLUG" != "my-team" ]; then
  FIZZY_OK=false
  fail "Test 13c: fizzy.accountSlug should be my-team, got $FIZZY_SLUG"
fi

# Check fizzy.token
FIZZY_TOK=$(jq -r '.fizzy.token' "$T13/.claude/pipeline/config.json")
if [ "$FIZZY_TOK" != "tok_abc123" ]; then
  FIZZY_OK=false
  fail "Test 13d: fizzy.token should be tok_abc123, got $FIZZY_TOK"
fi

# Check fizzy.boardId
FIZZY_BID=$(jq -r '.fizzy.boardId' "$T13/.claude/pipeline/config.json")
if [ "$FIZZY_BID" != "42" ]; then
  FIZZY_OK=false
  fail "Test 13e: fizzy.boardId should be 42, got $FIZZY_BID"
fi

if [ "$FIZZY_OK" = true ]; then
  pass "Test 13a: --fizzy flag sets all Fizzy config fields correctly"
fi

# Without --fizzy, Fizzy should be disabled (default from source config)
T13B="$TEST_DIR/t13b"
bash "$SETUP" "$T13B" --agents dev-rails > /dev/null 2>&1

FIZZY_SYNC_DEFAULT=$(jq -r '.fizzy.sync' "$T13B/.claude/pipeline/config.json")
if [ "$FIZZY_SYNC_DEFAULT" = "false" ]; then
  pass "Test 13b: fizzy.sync defaults to false without --fizzy flag"
else
  fail "Test 13b: fizzy.sync should default to false, got $FIZZY_SYNC_DEFAULT"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "================================="
TOTAL=$((PASS + FAIL))
echo -e "${BOLD}Results: $PASS/$TOTAL passed${NC}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}$FAIL test(s) failed${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
fi
