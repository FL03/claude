#!/usr/bin/env bash
# install.sh — Local skill installer for fl03/claude
#
# Usage:
#   ./scripts/install.sh                  # interactive: choose from list
#   ./scripts/install.sh rust finance     # install specific skills
#   ./scripts/install.sh --all            # install all skills
#   ./scripts/install.sh --list           # list available skills with versions
#   ./scripts/install.sh --status         # show what is currently installed
#   ./scripts/install.sh --uninstall rust # remove a skill

set -euo pipefail

SKILLS_DIR="$(cd "$(dirname "$0")/../skills" && pwd)"
INSTALL_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

available_skills() {
  find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d | sort | while read -r d; do
    echo "$(basename "$d")"
  done
}

skill_version() {
  local name="$1"
  local plugin_json="$SKILLS_DIR/$name/plugin.json"
  if [[ -f "$plugin_json" ]]; then
    python3 -c "import json,sys; print(json.load(open('$plugin_json'))['version'])" 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

skill_description() {
  local name="$1"
  local plugin_json="$SKILLS_DIR/$name/plugin.json"
  if [[ -f "$plugin_json" ]]; then
    python3 -c "import json,sys; d=json.load(open('$plugin_json'))['description']; print(d[:80]+'...' if len(d)>80 else d)" 2>/dev/null || echo ""
  fi
}

installed_version() {
  local name="$1"
  local plugin_json="$INSTALL_DIR/$name/plugin.json"
  if [[ -f "$plugin_json" ]]; then
    python3 -c "import json,sys; print(json.load(open('$plugin_json'))['version'])" 2>/dev/null || echo "?"
  elif [[ -d "$INSTALL_DIR/$name" ]]; then
    echo "installed (no version)"
  else
    echo ""
  fi
}

list_skills() {
  echo ""
  printf "${BOLD}%-16s %-10s %s${RESET}\n" "SKILL" "VERSION" "DESCRIPTION"
  printf "%-16s %-10s %s\n" "-----" "-------" "-----------"
  for name in $(available_skills); do
    ver=$(skill_version "$name")
    desc=$(skill_description "$name")
    printf "%-16s %-10s %s\n" "$name" "$ver" "$desc"
  done
  echo ""
}

show_status() {
  echo ""
  printf "${BOLD}%-16s %-14s %-14s %s${RESET}\n" "SKILL" "AVAILABLE" "INSTALLED" "STATUS"
  printf "%-16s %-14s %-14s %s\n" "-----" "---------" "---------" "------"
  for name in $(available_skills); do
    avail=$(skill_version "$name")
    inst=$(installed_version "$name")
    if [[ -z "$inst" ]]; then
      status="${YELLOW}not installed${RESET}"
    elif [[ "$avail" == "$inst" ]]; then
      status="${GREEN}up to date${RESET}"
    else
      status="${RED}outdated ($inst → $avail)${RESET}"
    fi
    printf "%-16s %-14s %-14s " "$name" "$avail" "${inst:-—}"
    echo -e "$status"
  done
  echo ""
}

do_install() {
  local name="$1"
  local src="$SKILLS_DIR/$name"
  local dst="$INSTALL_DIR/$name"

  if [[ ! -d "$src" ]]; then
    echo -e "${RED}Error: skill '$name' not found in $SKILLS_DIR${RESET}"
    return 1
  fi

  echo -e "  Installing ${BOLD}$name${RESET} $(skill_version "$name") → $dst"
  mkdir -p "$INSTALL_DIR"
  # Use rsync to copy, preserving structure, deleting stale files
  rsync -a --delete "$src/" "$dst/"
  echo -e "  ${GREEN}Done${RESET}"
}

do_uninstall() {
  local name="$1"
  local dst="$INSTALL_DIR/$name"

  if [[ ! -d "$dst" ]]; then
    echo -e "${YELLOW}Skill '$name' is not installed at $dst${RESET}"
    return 0
  fi

  echo -e "  Removing ${BOLD}$name${RESET} from $dst"
  rm -rf "$dst"
  echo -e "  ${GREEN}Done${RESET}"
}

interactive_select() {
  local skills
  skills=($(available_skills))
  local count=${#skills[@]}

  echo -e "\n${BOLD}Available skills:${RESET}\n"
  for i in "${!skills[@]}"; do
    local name="${skills[$i]}"
    local ver=$(skill_version "$name")
    local inst=$(installed_version "$name")
    local tag=""
    [[ -n "$inst" ]] && tag=" ${GREEN}[installed: $inst]${RESET}"
    printf "  ${BOLD}%2d)${RESET} %-16s v%-10s" "$((i+1))" "$name" "$ver"
    echo -e "$tag"
  done
  echo -e "  ${BOLD} 0)${RESET} Cancel\n"

  printf "Select skills to install (space-separated numbers, or 'all'): "
  read -r selection

  if [[ "$selection" == "all" ]]; then
    echo "${skills[@]}"
    return
  fi

  local chosen=()
  for num in $selection; do
    if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -gt 0 ]] && [[ "$num" -le "$count" ]]; then
      chosen+=("${skills[$((num-1))]}")
    elif [[ "$num" != "0" ]]; then
      echo -e "${YELLOW}Warning: '$num' is not a valid choice, skipping${RESET}"
    fi
  done
  echo "${chosen[@]:-}"
}

# --- Main ---

if [[ $# -eq 0 ]]; then
  selected=$(interactive_select)
  if [[ -z "${selected:-}" ]]; then
    echo "Nothing selected."
    exit 0
  fi
  echo ""
  for skill in $selected; do
    do_install "$skill"
  done
  exit 0
fi

case "$1" in
  --list|-l)
    list_skills
    ;;
  --status|-s)
    show_status
    ;;
  --all|-a)
    echo -e "\n${BOLD}Installing all skills...${RESET}\n"
    for name in $(available_skills); do
      do_install "$name"
    done
    ;;
  --uninstall|-u)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Usage: $0 --uninstall <skill...>"
      exit 1
    fi
    for name in "$@"; do
      do_uninstall "$name"
    done
    ;;
  --help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //'
    ;;
  -*)
    echo "Unknown option: $1. Run with --help for usage."
    exit 1
    ;;
  *)
    echo -e "\n${BOLD}Installing selected skills...${RESET}\n"
    for name in "$@"; do
      do_install "$name"
    done
    ;;
esac
