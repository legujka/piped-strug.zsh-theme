#!/bin/bash

THEME="piped-strug.zsh-theme"
LOAD_STR="[[ -f \"$THEME\" ]] && source \"$THEME\""

if [ -d "$HOME/.oh-my-zsh" ]; then
  echo "Creating symlink to ~/.oh-my-zsh/custom/themes/$THEME"
  ln -sf "$(realpath $THEME)" "$HOME/.oh-my-zsh/custom/themes/$THEME"
else
  echo "Adding theme to .zshrc..."
  if ! grep -q ".zsh-tree-theme" "$HOME/.zshrc"; then
    echo -e "\n# Zsh Tree Theme\n$LOAD_STR" >> "$HOME/.zshrc"
  else
    echo "Theme already exists in .zshrc"
  fi
fi

echo "Done"
