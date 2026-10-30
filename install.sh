#!/usr/bin/env bash
set -e

# ==============================================================================
# Dotfiles Setup & Symlink Installer
# ==============================================================================

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

success() {
    printf "${GREEN}[OK]${NC} %s\n" "$1"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

link_file() {
    local src="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        warn "Backing up existing file: $dst -> $dst.bak"
        mv "$dst" "$dst.bak"
    fi

    ln -sf "$src" "$dst"
    success "Linked: $dst -> $src"
}

info "Installing dotfiles from: $DOTFILES_DIR"

# 1. Hammerspoon
info "Configuring Hammerspoon..."
link_file "$DOTFILES_DIR/config/hammerspoon/init.lua" "$HOME/.hammerspoon/init.lua"

# 2. Ghostty Terminal
info "Configuring Ghostty..."
link_file "$DOTFILES_DIR/config/ghostty/config" "$HOME/.config/ghostty/config"
link_file "$DOTFILES_DIR/config/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"

# 3. Warp Terminal
info "Configuring Warp..."
link_file "$DOTFILES_DIR/config/warp/settings.toml" "$HOME/.warp/settings.toml"

# 4. Optional Tool Compilation
build_tools() {
    info "Compiling Swift menu bar utilities..."
    mkdir -p "$DOTFILES_DIR/bin"
    mkdir -p "$DOTFILES_DIR/module_cache"

    local cache_args=("-module-cache-path" "$DOTFILES_DIR/module_cache" "-Xcc" "-fmodules-cache-path=$DOTFILES_DIR/module_cache")

    if command -v swiftc >/dev/null 2>&1; then
        info "Building menubar_notes..."
        swiftc -O "$DOTFILES_DIR/tools/menubar-notes/menubar_notes.swift" "${cache_args[@]}" -o "$DOTFILES_DIR/bin/menubar_notes"
        ln -sf "$DOTFILES_DIR/bin/menubar_notes" "$DOTFILES_DIR/menubar_notes"
        success "Built: bin/menubar_notes"

        info "Building smart_pomodoro..."
        swiftc -O "$DOTFILES_DIR/tools/pomodoro/smart_pomodoro.swift" "${cache_args[@]}" -o "$DOTFILES_DIR/bin/smart_pomodoro"
        ln -sf "$DOTFILES_DIR/bin/smart_pomodoro" "$DOTFILES_DIR/smart_pomodoro"
        success "Built: bin/smart_pomodoro"

        info "Building stopwatch_pomodoro..."
        swiftc -O "$DOTFILES_DIR/tools/pomodoro/stopwatch_pomodoro.swift" "${cache_args[@]}" -o "$DOTFILES_DIR/bin/stopwatch_pomodoro"
        ln -sf "$DOTFILES_DIR/bin/stopwatch_pomodoro" "$DOTFILES_DIR/stopwatch_pomodoro"
        success "Built: bin/stopwatch_pomodoro"

        info "Building usage_tracker..."
        swiftc -O "$DOTFILES_DIR/tools/usage-tracker/usage_tracker.swift" "${cache_args[@]}" -o "$DOTFILES_DIR/bin/usage_tracker"
        ln -sf "$DOTFILES_DIR/bin/usage_tracker" "$DOTFILES_DIR/tools/usage-tracker/usage_tracker"
        success "Built: bin/usage_tracker"
    else
        warn "swiftc compiler not found, skipping tool compilation."
    fi
}

if [ "$1" = "--build" ] || [ "$1" = "--all" ]; then
    build_tools
fi

echo ""
success "All dotfiles and symlinks configured successfully!"
info "Tip: Run './install.sh --build' if you need to recompile Swift tools."
