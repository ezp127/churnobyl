#!/usr/bin/env bash
# churnobyl — git history dashboard
# "examining the body before touching the code"

set -euo pipefail
# SIGPIPE (exit 141) from `head` closing pipes early is harmless — ignore it
trap '' PIPE

# ─── Colors ───────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
BLUE=$'\033[0;34m'
MAGENTA=$'\033[0;35m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

# ─── Box drawing ──────────────────────────────────────────────────────────────
TL='┌' TR='┐' BL='└' BR='┘' H='─' V='│' LT='├' RT='┤'

# ─── Config ───────────────────────────────────────────────────────────────────
SINCE="${CHURNOBYL_SINCE:-1 year ago}"
TOP_N="${CHURNOBYL_TOP:-15}"
BAR_WIDTH=35
COLS=$(tput cols 2>/dev/null || echo 100)
INNER=$(( COLS - 2 ))

# ─── Helpers ──────────────────────────────────────────────────────────────────
repeat_char() {
  local str='' i
  for (( i=0; i<$2; i++ )); do str+="$1"; done
  printf '%s' "$str"
}

pad_right() {
  local text="$1" width="$2"
  local len=${#text}
  local pad=$(( width - len ))
  printf '%s' "$text"
  [[ $pad -gt 0 ]] && repeat_char ' ' "$pad"
}

draw_bar() {
  local value=$1 max=$2 color=${3:-$GREEN}
  [[ $max -eq 0 ]] && max=1
  local filled=$(( value * BAR_WIDTH / max ))
  local empty=$(( BAR_WIDTH - filled ))
  printf "${color}"
  [[ $filled -gt 0 ]] && repeat_char '█' "$filled"
  printf "${DIM}"
  [[ $empty -gt 0 ]] && repeat_char '░' "$empty"
  printf "${NC}"
}

risk_badge() {
  local rank=$1 total=$2
  [[ $total -eq 0 ]] && total=1
  local pct=$(( rank * 100 / total ))
  if   [[ $pct -le 25 ]]; then printf "${RED}${BOLD} ☢  HIGH ${NC}"
  elif [[ $pct -le 60 ]]; then printf "${YELLOW}${BOLD} ⚠  MED  ${NC}"
  else                         printf "${GREEN}${BOLD} ✓  OK   ${NC}"
  fi
}

momentum_badge() {
  local curr=$1 prev=$2
  if   [[ $prev -eq 0 && $curr -gt 0 ]]; then printf "${GREEN}▲${NC}"
  elif [[ $prev -eq 0 ]];                then printf "${DIM}–${NC}"
  elif (( curr >= prev ));               then printf "${GREEN}▲${NC}"
  elif (( curr >= prev * 70 / 100 ));    then printf "${YELLOW}▼${NC}"
  else                                        printf "${RED}▼${NC}"
  fi
}

box_top() {
  local title="$1"
  local tlen=${#title}
  local left=$(( (INNER - tlen - 2) / 2 ))
  local right=$(( INNER - tlen - 2 - left ))
  printf "${CYAN}${TL}$(repeat_char "$H" $left) ${BOLD}${BLUE}${title}${NC}${CYAN} $(repeat_char "$H" $right)${TR}${NC}\n"
}

box_bottom() {
  printf "${CYAN}${BL}$(repeat_char "$H" $INNER)${BR}${NC}\n"
}

box_line() {
  local content="$1"
  # strip ANSI for length calculation
  local plain
  plain=$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*m//g')
  local plen=${#plain}
  local pad=$(( INNER - plen - 2 ))
  printf "${CYAN}${V}${NC} %s" "$content"
  [[ $pad -gt 0 ]] && repeat_char ' ' "$pad"
  printf " ${CYAN}${V}${NC}\n"
}

box_empty() {
  printf "${CYAN}${V}${NC}$(repeat_char ' ' $INNER)${CYAN}${V}${NC}\n"
}

box_sep() {
  printf "${CYAN}${LT}$(repeat_char "$H" $INNER)${RT}${NC}\n"
}

# ─── Target directory ─────────────────────────────────────────────────────────
if [[ -n "${1:-}" ]]; then
  TARGET_DIR=$(realpath "$1")
  cd "$TARGET_DIR" || { printf "${RED}${BOLD}error:${NC} cannot cd to '%s'.\n" "$1"; exit 1; }
fi

# ─── Git guard ────────────────────────────────────────────────────────────────
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  printf "${RED}${BOLD}error:${NC} not inside a git repository.\n"
  exit 1
fi

if ! git rev-list -1 HEAD > /dev/null 2>&1; then
  printf "${RED}${BOLD}error:${NC} repository has no commits yet.\n"
  exit 1
fi

# ─── Collect metadata ─────────────────────────────────────────────────────────
REPO=$(basename "$(git rev-parse --show-toplevel)")
BRANCH=$(git rev-parse --abbrev-ref HEAD)
TOTAL_COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo "0")
FIRST_COMMIT=$(git log --reverse --format='%ar' --max-count=1)
DATE=$(date '+%Y-%m-%d %H:%M')

# ─── Header ───────────────────────────────────────────────────────────────────
clear
printf "\n"
box_top "☢  CHURNOBYL"
box_empty
box_line "  ${BOLD}repo${NC}    ${CYAN}${REPO}${NC}"
box_line "  ${BOLD}branch${NC}  ${CYAN}${BRANCH}${NC}"
box_line "  ${BOLD}commits${NC} ${CYAN}${TOTAL_COMMITS}${NC}  (started ${FIRST_COMMIT})"
box_line "  ${BOLD}window${NC}  ${CYAN}${SINCE}${NC}  •  top ${TOP_N} results  •  ${DATE}"
box_empty
box_bottom

# ─── 1. High Churn Files ──────────────────────────────────────────────────────
printf "\n"
box_top "1/5  HIGH CHURN FILES"
box_empty

mapfile -t CHURN_LINES < <(
  git log --format=format: --name-only --since="$SINCE" \
    | grep -v '^$' | sort | uniq -c | sort -nr | head -"$TOP_N"
)

if [[ ${#CHURN_LINES[@]} -eq 0 ]]; then
  box_line "  ${DIM}no data for this time window${NC}"
else
  MAX_CHURN=$(awk '{print $1}' <<< "${CHURN_LINES[0]}")
  TOTAL=${#CHURN_LINES[@]}

  box_line "  $(pad_right 'file' 40) $(pad_right 'changes' 9) chart$(repeat_char ' ' $((BAR_WIDTH - 5)))  risk"
  box_line "  $(repeat_char '·' 40) $(repeat_char '·' 8)  $(repeat_char '·' $BAR_WIDTH)  ──────"

  rank=0
  for line in "${CHURN_LINES[@]}"; do
    count=$(awk '{print $1}' <<< "$line")
    file=$(awk '{$1=""; sub(/^ /,""); print}' <<< "$line")

    # truncate long paths
    [[ ${#file} -gt 40 ]] && file="…${file: -39}"

    bar=$(draw_bar "$count" "$MAX_CHURN")
    badge=$(risk_badge "$rank" "$TOTAL")

    content="  $(pad_right "$file" 40) $(pad_right "$count" 8)  ${bar}  ${badge}"
    box_line "$content"
    (( rank++ )) || true
  done
fi

box_empty
box_bottom

# ─── 2. Team Composition ──────────────────────────────────────────────────────
printf "\n"
box_top "2/5  TEAM COMPOSITION  (bus factor check)"
box_empty

mapfile -t TEAM_ALL < <(git shortlog HEAD -sn --no-merges | head -"$TOP_N")
mapfile -t TEAM_RECENT < <(git shortlog HEAD -sn --no-merges --since="6 months ago" | awk '{print $2}')

if [[ ${#TEAM_ALL[@]} -eq 0 ]]; then
  box_line "  ${DIM}no data${NC}"
else
  MAX_TEAM=$(awk '{print $1}' <<< "${TEAM_ALL[0]}")
  TOTAL_CONTRIBS=${#TEAM_ALL[@]}
  TOTAL_TEAM_COMMITS=$(git shortlog HEAD -sn --no-merges | awk '{sum+=$1} END{print sum}')
  [[ $TOTAL_TEAM_COMMITS -eq 0 ]] && TOTAL_TEAM_COMMITS=1

  # bus factor warning
  TOP_PCT=$(( $(awk '{print $1}' <<< "${TEAM_ALL[0]}") * 100 / TOTAL_TEAM_COMMITS ))
  if [[ $TOP_PCT -ge 60 ]]; then
    box_line "  ${RED}${BOLD}⚠  bus factor warning:${NC} top contributor owns ${TOP_PCT}% of all commits"
    box_empty
  fi

  box_line "  $(pad_right 'contributor' 28) $(pad_right 'commits' 9) $(pad_right 'share' 7) chart$(repeat_char ' ' $((BAR_WIDTH - 5)))  active"
  box_line "  $(repeat_char '·' 28) $(repeat_char '·' 8)  $(repeat_char '·' 6)  $(repeat_char '·' $BAR_WIDTH)  ──────"

  for line in "${TEAM_ALL[@]}"; do
    commits=$(awk '{print $1}' <<< "$line")
    name=$(awk '{$1=""; sub(/^ /,""); print}' <<< "$line")
    [[ ${#name} -gt 28 ]] && name="${name:0:27}…"

    pct=$(( commits * 100 / TOTAL_TEAM_COMMITS ))
    bar=$(draw_bar "$commits" "$MAX_TEAM")

    # check if recently active
    if printf '%s\n' "${TEAM_RECENT[@]}" | grep -qF "$name"; then
      active="${GREEN}● active${NC}"
    else
      active="${DIM}○ dormant${NC}"
    fi

    content="  $(pad_right "$name" 28) $(pad_right "$commits" 8)  $(pad_right "${pct}%" 6)  ${bar}  ${active}"
    box_line "$content"
  done
fi

box_empty
box_bottom

# ─── 3. Bug Hotspots ──────────────────────────────────────────────────────────
printf "\n"
box_top "3/5  BUG HOTSPOTS  (fix|bug|broken commits)"
box_empty

mapfile -t BUG_LINES < <(
  git log -i -E --grep="fix|bug|broken|patch|hotfix|revert" \
    --name-only --format='' --since="$SINCE" \
    | grep -v '^$' | sort | uniq -c | sort -nr | head -"$TOP_N"
)

# build churn set for cross-reference
declare -A CHURN_SET
for line in "${CHURN_LINES[@]}"; do
  f=$(awk '{$1=""; sub(/^ /,""); print}' <<< "$line")
  CHURN_SET["$f"]=1
done

if [[ ${#BUG_LINES[@]} -eq 0 ]]; then
  box_line "  ${GREEN}✓  no bug-related commits found in this window${NC}"
else
  MAX_BUG=$(awk '{print $1}' <<< "${BUG_LINES[0]}")
  TOTAL_B=${#BUG_LINES[@]}
  rank=0

  box_line "  $(pad_right 'file' 40) $(pad_right 'bug commits' 12) chart$(repeat_char ' ' $((BAR_WIDTH - 5)))  note"
  box_line "  $(repeat_char '·' 40) $(repeat_char '·' 11)  $(repeat_char '·' $BAR_WIDTH)  ──────"

  for line in "${BUG_LINES[@]}"; do
    count=$(awk '{print $1}' <<< "$line")
    file=$(awk '{$1=""; sub(/^ /,""); print}' <<< "$line")
    [[ ${#file} -gt 40 ]] && file="…${file: -39}"

    bar=$(draw_bar "$count" "$MAX_BUG" "$RED")

    # cross-reference with churn
    note=""
    for cf in "${!CHURN_SET[@]}"; do
      stripped_file=$(printf '%s' "$file" | sed 's/^…//')
      if [[ "$cf" == *"$stripped_file"* || "$stripped_file" == *"${cf##*/}"* ]]; then
        note="${RED}${BOLD}☢  also high churn${NC}"
        break
      fi
    done

    content="  $(pad_right "$file" 40) $(pad_right "$count" 11)  ${bar}  ${note}"
    box_line "$content"
    (( rank++ )) || true
  done
fi

box_empty
box_bottom

# ─── 4. Project Momentum ──────────────────────────────────────────────────────
printf "\n"
box_top "4/5  PROJECT MOMENTUM  (commits / month)"
box_empty

mapfile -t MOMENTUM_RAW < <(
  git log --format='%ad' --date=format:'%Y-%m' --since="$SINCE" \
    | sort | uniq -c
)

if [[ ${#MOMENTUM_RAW[@]} -eq 0 ]]; then
  box_line "  ${DIM}no data for this time window${NC}"
else
  MAX_MOM=$(printf '%s\n' "${MOMENTUM_RAW[@]}" | awk 'BEGIN{m=0} {if($1+0>m) m=$1} END{print m}')
  prev=0

  box_line "  $(pad_right 'month' 10) $(pad_right 'commits' 9) chart$(repeat_char ' ' $((BAR_WIDTH - 5)))  trend"
  box_line "  $(repeat_char '·' 10) $(repeat_char '·' 8)  $(repeat_char '·' $BAR_WIDTH)  ─────"

  for line in "${MOMENTUM_RAW[@]}"; do
    count=$(awk '{print $1}' <<< "$line")
    month=$(awk '{print $2}' <<< "$line")

    # color bar based on trend
    if [[ $prev -eq 0 ]]; then
      bcolor=$CYAN
    elif (( count >= prev )); then
      bcolor=$GREEN
    elif (( count >= prev * 70 / 100 )); then
      bcolor=$YELLOW
    else
      bcolor=$RED
    fi

    bar=$(draw_bar "$count" "$MAX_MOM" "$bcolor")
    trend=$(momentum_badge "$count" "$prev")

    content="  $(pad_right "$month" 10) $(pad_right "$count" 8)  ${bar}  ${trend}"
    box_line "$content"
    prev=$count
  done
fi

box_empty
box_bottom

# ─── 5. Firefighting Patterns ─────────────────────────────────────────────────
printf "\n"
box_top "5/5  FIREFIGHTING PATTERNS  (reverts & hotfixes)"
box_empty

mapfile -t FIRE_LINES < <(
  git log --oneline --since="$SINCE" \
    | grep -iE 'revert|hotfix|emergency|rollback|critical|urgent' \
    | head -"$TOP_N"
)

FIRE_COUNT=${#FIRE_LINES[@]}

if [[ $FIRE_COUNT -eq 0 ]]; then
  box_line "  ${GREEN}${BOLD}✓  no firefighting commits found — looking stable${NC}"
else
  # severity assessment
  REVERTS=$(printf '%s\n' "${FIRE_LINES[@]}" | grep -ic 'revert' || true)
  HOTFIXES=$(printf '%s\n' "${FIRE_LINES[@]}" | grep -ic 'hotfix\|emergency\|urgent\|critical' || true)

  if [[ $FIRE_COUNT -ge 10 ]]; then
    box_line "  ${RED}${BOLD}☢  severity: MELTDOWN — ${FIRE_COUNT} firefighting commits detected${NC}"
  elif [[ $FIRE_COUNT -ge 5 ]]; then
    box_line "  ${YELLOW}${BOLD}⚠  severity: SMOKY — ${FIRE_COUNT} firefighting commits detected${NC}"
  else
    box_line "  ${CYAN}${BOLD}~  severity: SPARKS — ${FIRE_COUNT} firefighting commits detected${NC}"
  fi

  box_line "  ${DIM}reverts: ${REVERTS}   hotfixes/emergencies: ${HOTFIXES}${NC}"
  box_empty
  box_sep
  box_empty

  for line in "${FIRE_LINES[@]}"; do
    hash="${line:0:7}"
    msg="${line:8}"
    [[ ${#msg} -gt $(( INNER - 14 )) ]] && msg="${msg:0:$(( INNER - 17 ))}…"

    if printf '%s' "$line" | grep -qi 'revert'; then
      icon="${MAGENTA}↩${NC}"
    elif printf '%s' "$line" | grep -qi 'hotfix\|emergency\|urgent\|critical'; then
      icon="${RED}🔥${NC}"
    else
      icon="${YELLOW}⚠${NC}"
    fi

    content="  ${icon}  ${DIM}${hash}${NC}  ${msg}"
    box_line "$content"
  done
fi

box_empty
box_bottom

# ─── Summary ──────────────────────────────────────────────────────────────────
printf "\n"
box_top "☢  CHURNOBYL SUMMARY"
box_empty

CHURN_COUNT=${#CHURN_LINES[@]}
BUG_COUNT=${#BUG_LINES[@]}

box_line "  ${BOLD}high-churn files${NC}       ${CYAN}${CHURN_COUNT}${NC}"
box_line "  ${BOLD}bug-prone files${NC}        ${CYAN}${BUG_COUNT}${NC}"
box_line "  ${BOLD}firefighting commits${NC}   ${CYAN}${FIRE_COUNT}${NC}"
box_empty

# overall health score (simple heuristic)
SCORE=100
(( SCORE -= FIRE_COUNT * 3 )) || true
(( SCORE -= BUG_COUNT * 2 )) || true
[[ $SCORE -lt 0 ]] && SCORE=0

if   [[ $SCORE -ge 80 ]]; then HEALTH="${GREEN}${BOLD}STABLE${NC}"
elif [[ $SCORE -ge 50 ]]; then HEALTH="${YELLOW}${BOLD}CONCERNING${NC}"
elif [[ $SCORE -ge 20 ]]; then HEALTH="${RED}${BOLD}CRITICAL${NC}"
else                           HEALTH="${RED}${BOLD}☢ MELTDOWN${NC}"
fi

box_line "  ${BOLD}overall health${NC}         ${HEALTH}  (score: ${SCORE}/100)"
box_empty
box_line "  ${DIM}tip: set CHURNOBYL_SINCE='6 months ago' or CHURNOBYL_TOP=20 to customize${NC}"
box_empty
box_bottom

printf "\n"
