#!/bin/bash
# Read JSON data that Claude Code sends to stdin
input=$(cat)

# Extract fields using jq
MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
# The "// 0" provides a fallback if the field is null
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
FIVE_HOUR_USAGE=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0' | cut -d. -f1)
FIVE_HOUR_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
SEVEN_DAY_USAGE=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0' | cut -d. -f1)
SEVEN_DAY_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // 0')
TOTAL_INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens')
TOTAL_OUTPUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_output_tokens')

# Format reset time as relative duration (e.g. 1h30m, 2d15h)
format_duration() {
  local secs=$1
  if [ "$secs" -le 0 ] 2>/dev/null; then echo ""; return; fi
  local days=$((secs / 86400))
  local hours=$(( (secs % 86400) / 3600 ))
  local mins=$(( (secs % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    echo "${days}d${hours}h"
  elif [ "$hours" -gt 0 ]; then
    echo "${hours}h${mins}m"
  else
    echo "${mins}m"
  fi
}

NOW=$(date +%s)

if [ "$FIVE_HOUR_RESET" -gt 0 ] 2>/dev/null; then
  FIVE_HOUR_RESET_STR="$(format_duration $((FIVE_HOUR_RESET - NOW)))"
else
  FIVE_HOUR_RESET_STR=""
fi

if [ "$SEVEN_DAY_RESET" -gt 0 ] 2>/dev/null; then
  SEVEN_DAY_RESET_STR="$(format_duration $((SEVEN_DAY_RESET - NOW)))"
else
  SEVEN_DAY_RESET_STR=""
fi

# ANSI color codes
RED='\033[31m'
YELLOW='\033[33m'
GREEN='\033[32m'
WHITE='\033[37m'
RESET='\033[0m'

# Helper: color text by usage threshold
color_usage() {
  local usage=$1 text=$2
  if [ "$usage" -ge 80 ] 2>/dev/null; then
    echo "${RED}${text}${RESET}"
  elif [ "$usage" -ge 50 ] 2>/dev/null; then
    echo "${YELLOW}${text}${RESET}"
  elif [ "$usage" -ge 30 ] 2>/dev/null; then
    echo "${GREEN}${text}${RESET}"
  else
    echo "${WHITE}${text}${RESET}"
  fi
}

H_USAGE_BAR_WIDTH=20
H_USAGE_FILLED=$((FIVE_HOUR_USAGE * H_USAGE_BAR_WIDTH / 100))
H_USAGE_EMPTY=$((H_USAGE_BAR_WIDTH - H_USAGE_FILLED))
H_USAGE_BAR=""
[ "$H_USAGE_FILLED" -gt 0 ] && printf -v FILL "%${H_USAGE_FILLED}s" && H_USAGE_BAR="${FILL// /▓}"
[ "$H_USAGE_EMPTY" -gt 0 ] && printf -v PAD "%${H_USAGE_EMPTY}s" && H_USAGE_BAR="${H_USAGE_BAR}${PAD// /░}"

D_USAGE_BAR_WIDTH=20
D_USAGE_FILLED=$((SEVEN_DAY_USAGE * D_USAGE_BAR_WIDTH / 100))
D_USAGE_EMPTY=$((D_USAGE_BAR_WIDTH - D_USAGE_FILLED))
D_USAGE_BAR=""
[ "$D_USAGE_FILLED" -gt 0 ] && printf -v FILL "%${D_USAGE_FILLED}s" && D_USAGE_BAR="${FILL// /▓}"
[ "$D_USAGE_EMPTY" -gt 0 ] && printf -v PAD "%${D_USAGE_EMPTY}s" && D_USAGE_BAR="${D_USAGE_BAR}${PAD// /░}"

TOTAL_INPUT_TOKENS_K="$((TOTAL_INPUT_TOKENS / 1000)).$( printf '%02d' $((TOTAL_INPUT_TOKENS % 1000 / 10)) )"
TOTAL_OUTPUT_TOKENS_K="$((TOTAL_OUTPUT_TOKENS / 1000)).$( printf '%02d' $((TOTAL_OUTPUT_TOKENS % 1000 / 10)) )"

# Build rate limit display
RATE=""
if [ -n "$FIVE_HOUR_RESET_STR" ]; then
  FIVE_HOUR_TEXT="5h: ${H_USAGE_BAR} ${FIVE_HOUR_USAGE}% ${FIVE_HOUR_RESET_STR}↻"
  RATE="$(color_usage "$FIVE_HOUR_USAGE" "$FIVE_HOUR_TEXT")"
fi
if [ -n "$SEVEN_DAY_RESET_STR" ]; then
  SEVEN_DAY_TEXT="7d: ${D_USAGE_BAR} ${SEVEN_DAY_USAGE}% ${SEVEN_DAY_RESET_STR}↻"
  RATE="${RATE:+$RATE }$(color_usage "$SEVEN_DAY_USAGE" "$SEVEN_DAY_TEXT") Inputs: ${TOTAL_INPUT_TOKENS_K}k Outputs: ${TOTAL_OUTPUT_TOKENS_K}k"
fi

BAR_WIDTH=20
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v FILL "%${FILLED}s" && BAR="${FILL// /▓}"
[ "$EMPTY" -gt 0 ] && printf -v PAD "%${EMPTY}s" && BAR="${BAR}${PAD// /░}"

# Color context usage too if over 80%
CTX_TEXT="${BAR} ${PCT}% context"
CTX_DISPLAY="$(color_usage "$PCT" "$CTX_TEXT")"

# Output the status line - ${DIR##*/} extracts just the folder name
echo -e "${CTX_DISPLAY}${RATE:+ | $RATE}"

if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')

    GIT_STATUS=""
    [ "$STAGED" -gt 0 ] && GIT_STATUS="${GREEN}+${STAGED}${RESET}"
    [ "$MODIFIED" -gt 0 ] && GIT_STATUS="${GIT_STATUS}${YELLOW}~${MODIFIED}${RESET}"

    echo -e "[$MODEL] 📁 ${DIR##*/} | 🌿 $BRANCH $GIT_STATUS"
else
    echo "[$MODEL] 📁 ${DIR##*/}"
fi