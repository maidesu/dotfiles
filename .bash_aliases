alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'


alias cl='clear'
alias cwd2lf='find . -type f -exec dos2unix {} +'
alias ll='ls -lahF'


if [ -f ~/.git_functions ]; then
    . ~/.git_functions
fi

if [ -f ~/.git_aliases ]; then
    . ~/.git_aliases
fi
