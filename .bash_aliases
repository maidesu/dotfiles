alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

alias sudo='sudo '

alias cl='clear'
alias cls='printf "\033[H\033[2J\033[3J"'
alias cwd2lf='find . -type f -exec dos2unix {} +'
alias ll='ls -lahF'

alias upd='sudo apt update && sudo apt full-upgrade --auto-remove'
alias res='systemctl reboot'
alias off='systemctl poweroff'

alias act='source .venv/bin/activate'
alias qa='poetry run poe qa'

if [ -f ~/.git_aliases ]; then
    . ~/.git_aliases
fi
