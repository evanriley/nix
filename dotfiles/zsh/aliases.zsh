alias reload!='. ~/.zshrc'

alias cls='clear' # Good 'ol Clear Screen command

if type nvim > /dev/null 2>&1; then
  alias vi='nvim'
  alias vim='nvim'
fi


## get rid of command not found ##
alias cd..='cd ..'
 
## a quick way to get out of current directory ##
alias ..='cd ..'
alias ...='cd ../../../'
alias ....='cd ../../../../'
alias .....='cd ../../../../'
alias .4='cd ../../../../'
alias .5='cd ../../../../..'

## Colorize the grep command output for ease of use (good for log files)##
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

alias mkdir='mkdir -pv'

## this one saved by butt so many times ##
alias wget='wget -c'

## honestly this isn't something that should be used...##
alias gac="git add . && git commit -a -m "

#make then enter the dir#
alias mkcd='foo(){ mkdir -p "$1"; cd "$1" }; foo '

##wtf is my ip address...##
alias myip="curl http://ipecho.net/plain; echo"

## copy public ssh key
alias pubkey='pbcopy < ~/.ssh/id_rsa.pub'
