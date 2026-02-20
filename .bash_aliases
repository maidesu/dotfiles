alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

alias cl='clear'
alias cwd2lf='find . -type f -exec dos2unix {} +'
alias ll='ls -lahF'

alias upd='sudo apt update && sudo apt full-upgrade --auto-remove'

alias cln='git add . && git add .env heca.db -f && git clean -fdx && git restore --staged .'
alias ins='poetry config virtualenvs.in-project true && poetry env use python3.13 && poetry install --extras dev'
alias act='source .venv/bin/activate'
alias qa='poetry run poe qa'

if [ -f ~/.git_aliases ]; then
    . ~/.git_aliases
fi
