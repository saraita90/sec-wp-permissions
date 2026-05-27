#!/bin/bash
# fix-wp-permissions.sh — Fix WordPress file and directory permissions
# Usage: sudo bash fix-wp-permissions.sh /var/www/html
#        sudo bash fix-wp-permissions.sh /var/www/html --dry-run

set -euo pipefail

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ──
print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD}            WORDPRESS PERMISSIONS FIXER                       ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_section() {
    local title="$1"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${BOLD}  ${title}${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"
}

print_ok()    { echo -e "${GREEN}✓${NC}  $1"; }
print_warn()  { echo -e "${YELLOW}⚡${NC} $1"; }
print_err()   { echo -e "${RED}✗${NC}  $1"; }
print_info()  { echo -e "${CYAN}→${NC}  $1"; }

# ── Args ──
WP_PATH=""
DRY_RUN=false

for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    elif [[ -z "$WP_PATH" && "$arg" != --* ]]; then
        WP_PATH="$arg"
    fi
done

# ── Validation ──
print_header

if [[ -z "$WP_PATH" ]]; then
    print_err "No WordPress path provided."
    echo
    echo -e "${BOLD}Usage:${NC}"
    echo "  sudo bash fix-wp-permissions.sh /var/www/html"
    echo "  sudo bash fix-wp-permissions.sh /var/www/html --dry-run"
    echo
    exit 1
fi

# Resolve absolute path
WP_PATH="$(cd "$WP_PATH" 2>/dev/null && pwd || echo "$WP_PATH")"

if [[ ! -d "$WP_PATH" ]]; then
    print_err "Path does not exist: ${BOLD}${WP_PATH}${NC}"
    exit 1
fi

# Check for WordPress markers
if [[ ! -f "$WP_PATH/wp-config.php" && ! -f "$WP_PATH/wp-config-sample.php" && ! -d "$WP_PATH/wp-content" ]]; then
    print_warn "This doesn't look like a WordPress directory."
    print_info "Missing wp-config.php, wp-config-sample.php, or wp-content/"
    echo
    read -rp "Continue anyway? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Aborted."
        exit 0
    fi
    echo
fi

if [[ "$DRY_RUN" == true ]]; then
    print_warn "DRY-RUN MODE — No changes will be made"
    echo
fi

print_section "Target"
print_info "Path: ${BOLD}${WP_PATH}${NC}"
print_info "Owner: ${BOLD}www-data:www-data${NC}"
print_info "Directories: ${BOLD}755${NC}"
print_info "Files: ${BOLD}644${NC}"
print_info "wp-config.php: ${BOLD}600${NC}"
echo

# ── Counters ──
dirs_changed=0
files_changed=0
config_changed=0
dirs_skipped=0
files_skipped=0
config_skipped=0

# ── Fix directories ──
print_section "Fixing Directories (755 www-data:www-data)"

while IFS= read -r -d '' dir; do
    current_perm=$(stat -c '%a' "$dir" 2>/dev/null || echo "???")
    current_owner=$(stat -c '%U:%G' "$dir" 2>/dev/null || echo "?:?")
    rel_path="${dir#$WP_PATH/}"
    [[ "$rel_path" == "$dir" ]] && rel_path="."

    needs_fix=false
    if [[ "$current_perm" != "755" ]]; then
        needs_fix=true
    fi
    if [[ "$current_owner" != "www-data:www-data" ]]; then
        needs_fix=true
    fi

    if [[ "$needs_fix" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${YELLOW}[WOULD FIX]${NC} ${rel_path}  (${current_perm} ${current_owner} → 755 www-data:www-data)"
            ((dirs_changed++))
        else
            chown www-data:www-data "$dir"
            chmod 755 "$dir"
            echo -e "  ${GREEN}[FIXED]${NC}     ${rel_path}"
            ((dirs_changed++))
        fi
    else
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${GREEN}[OK]${NC}        ${rel_path}  (already 755 www-data:www-data)"
        fi
        ((dirs_skipped++))
    fi
done < <(find "$WP_PATH" -type d -print0)

echo

# ── Fix files ──
print_section "Fixing Files (644 www-data:www-data)"

while IFS= read -r -d '' file; do
    # Skip wp-config.php — handled separately
    if [[ "$(basename "$file")" == "wp-config.php" ]]; then
        continue
    fi

    current_perm=$(stat -c '%a' "$file" 2>/dev/null || echo "???")
    current_owner=$(stat -c '%U:%G' "$file" 2>/dev/null || echo "?:?")
    rel_path="${file#$WP_PATH/}"
    [[ "$rel_path" == "$file" ]] && rel_path="."

    needs_fix=false
    if [[ "$current_perm" != "644" ]]; then
        needs_fix=true
    fi
    if [[ "$current_owner" != "www-data:www-data" ]]; then
        needs_fix=true
    fi

    if [[ "$needs_fix" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${YELLOW}[WOULD FIX]${NC} ${rel_path}  (${current_perm} ${current_owner} → 644 www-data:www-data)"
            ((files_changed++))
        else
            chown www-data:www-data "$file"
            chmod 644 "$file"
            echo -e "  ${GREEN}[FIXED]${NC}     ${rel_path}"
            ((files_changed++))
        fi
    else
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${GREEN}[OK]${NC}        ${rel_path}  (already 644 www-data:www-data)"
        fi
        ((files_skipped++))
    fi
done < <(find "$WP_PATH" -type f -print0)

echo

# ── Fix wp-config.php ──
print_section "Fixing wp-config.php (600 www-data:www-data)"

CONFIG_FILE="$WP_PATH/wp-config.php"
if [[ -f "$CONFIG_FILE" ]]; then
    current_perm=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || echo "???")
    current_owner=$(stat -c '%U:%G' "$CONFIG_FILE" 2>/dev/null || echo "?:?")

    needs_fix=false
    if [[ "$current_perm" != "600" ]]; then
        needs_fix=true
    fi
    if [[ "$current_owner" != "www-data:www-data" ]]; then
        needs_fix=true
    fi

    if [[ "$needs_fix" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${YELLOW}[WOULD FIX]${NC} wp-config.php  (${current_perm} ${current_owner} → 600 www-data:www-data)"
            ((config_changed++))
        else
            chown www-data:www-data "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            echo -e "  ${GREEN}[FIXED]${NC}     wp-config.php"
            ((config_changed++))
        fi
    else
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${GREEN}[OK]${NC}        wp-config.php  (already 600 www-data:www-data)"
        fi
        ((config_skipped++))
    fi
else
    print_warn "wp-config.php not found at ${CONFIG_FILE}"
fi

echo

# ── Summary ──
print_section "Summary"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}DRY-RUN COMPLETE — No changes were made${NC}"
    echo
    echo -e "  ${BOLD}Would fix:${NC}"
    echo -e "    Directories:     ${dirs_changed}"
    echo -e "    Files:           ${files_changed}"
    echo -e "    wp-config.php:   ${config_changed}"
    echo
    echo -e "  ${BOLD}Already correct:${NC}"
    echo -e "    Directories:     ${dirs_skipped}"
    echo -e "    Files:           ${files_skipped}"
    echo -e "    wp-config.php:   ${config_skipped}"
    echo
    print_info "Run without --dry-run to apply changes."
else
    echo -e "  ${GREEN}DONE${NC}"
    echo
    echo -e "  ${BOLD}Fixed:${NC}"
    echo -e "    Directories:     ${dirs_changed}"
    echo -e "    Files:           ${files_changed}"
    echo -e "    wp-config.php:   ${config_changed}"
    echo
    if (( dirs_skipped + files_skipped + config_skipped > 0 )); then
        echo -e "  ${BOLD}Already correct:${NC}"
        echo -e "    Directories:     ${dirs_skipped}"
        echo -e "    Files:           ${files_skipped}"
        echo -e "    wp-config.php:   ${config_skipped}"
    fi
    echo
    print_ok "WordPress permissions fixed at ${WP_PATH}"
fi

echo
