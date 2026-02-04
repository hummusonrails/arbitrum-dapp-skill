#!/bin/bash
set -e

SKILL_NAME="arbitrum-dapp"
SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"
REPO_URL="https://github.com/hummusonrails/arbitrum-dapp-skill.git"

echo "Installing $SKILL_NAME skill for Claude Code..."

# Create skills directory if it doesn't exist
mkdir -p "$HOME/.claude/skills"

# Clone or update
if [ -d "$SKILL_DIR" ]; then
  echo "Updating existing installation..."
  cd "$SKILL_DIR"
  git pull origin main
else
  echo "Cloning skill..."
  git clone "$REPO_URL" "$SKILL_DIR"
fi

echo ""
echo "Installed to: $SKILL_DIR"
echo ""
echo "The skill is now available in Claude Code. Start a new session and ask Claude to help you build an Arbitrum dApp."
