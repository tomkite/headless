#!/bin/bash
# machine.sh - your own additions for this Mac. apply.sh runs it on every
# apply, as the Mac's account (not root), after the headless settings and
# `brew bundle`. Homebrew's tools are on PATH. Keep every line safe to run
# again: check before you change, as below.
set -euo pipefail

# Examples (uncomment to use):
#
# Show hidden files in Finder:
#   defaults write com.apple.finder AppleShowAllFiles -bool true
#
# Faster key repeat (takes effect at the next sign-in):
#   defaults write -g KeyRepeat -int 2
#   defaults write -g InitialKeyRepeat -int 15
#
# Clone your dotfiles once:
#   [ -d ~/.dotfiles ] || git clone https://github.com/YOU/dotfiles ~/.dotfiles
