export PATH=$PATH:/usr/bin:/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin

export BASH_ENV=$HOME/.bashrc
export EDITOR=/usr/bin/mcedit
export PAGER=less

alias ls="ls -laF"
alias df="df -H"
genpass() { local l=$1; [ -z "$l" ] && l=10; cat /dev/urandom | tr -dc A-Za-z0-9 | head -c${l}; echo; }

shopt -s histappend
export HISTIGNORE="&:ls:[bf]g:exit"
export HISTCONTROL="ignoredups"
export HISTFILE=$HOME/.bash_history
shopt -s cmdhist

SETCOLOR='\[[0;36m\]'
SETCOLOR_NORMAL='\[[0m\]'
SETCOLOR_HOST='\[[0;37m\]'

if [ "`id -u`" = "0" ]; then
  SETCOLOR_USER='\[[1;31m\]'
  SET_SEP='# '
  if [ -f /etc/cron.d/slack ]; then
    alias upslack="/usr/bin/env `cat /etc/cron.d/slack | /usr/bin/awk 'BEGIN {FS=\"&& \"}{print $2}'` -v"
  fi
  if [ -f /root/.mysql ]; then
    alias rootdb='mysql -u root -A -p`cat /root/.mysql`'
    alias rootdbdump='mysqldump -u root -p`cat /root/.mysql` --quote-names --opt --routines --single-transaction --events'
  fi
  if [ -f /usr/sbin/vzlist ]; then
    alias vztop='vzlist -o veid,numproc,status,hostname,ip,laverage,numfile,cpuunits,tcprcvbuf,tcpsndbuf,kmemsize'
  fi
  if [ -f $HOME/.vimrcx ]; then
      alias vimx='vim -u $HOME/.vimrcx'
      alias vimdiff='vimdiff -u $HOME/.vimrcx'
  fi
else
  SETCOLOR_USER='\[[1;32m\]'
  SET_SEP="$ "
fi

PS1="${SETCOLOR}[${SETCOLOR_USER}\u${SETCOLOR_HOST}@\H ${SETCOLOR}\w]${SET_SEP}${SETCOLOR_NORMAL}"

unset SETCOLOR
unset SETCOLOR_NORMAL
unset SETCOLOR_HOST
