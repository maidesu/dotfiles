alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

alias cl='clear'
alias cwd2lf='find . -type f -exec dos2unix {} +'
alias ll='ls -lahF'

alias upd='sudo apt update && sudo apt full-upgrade --auto-remove'

if [ -f ~/.git_aliases ]; then
    . ~/.git_aliases
fi
