#!/bin/bash

wheel_id=$(grep "^wheel:" /etc/group | awk -F ':' '{print $3}')

# Список админов, которым разрешен sudo
##greparg=""
greparg="sbadmin"

if [ -f /root/.sudocheck ]; then
  while IFS='' read -r line || [[ -n "$line" ]]; do
#    echo "Text read from file: $line"
    if [ -z "$greparg" ]; then
      greparg=$line
    else
      greparg=$line"|"$greparg
    fi
  # берем строки исключений, отбрасывая строки с комментариями и обрезаем ведомые комментарии в строках с исключениями
  done < <(grep -ve "^[[:space:]]*#" /root/.sudocheck | sed -r 's/\#.*//' | sed 's/^[ \t]*//;s/[ \t]*$//')
fi

if [ -f /root/.admins ]; then
  while IFS='' read -r line || [[ -n "$line" ]]; do
#    echo "Text read from file: $line"
    if [ -z "$greparg" ]; then
      greparg=$line
    else
      greparg=$line"|"$greparg
    fi
  # берем строки исключений, отбрасывая строки с комментариями и обрезаем ведомые комментарии в строках с исключениями
  done < <(grep -ve "^[[:space:]]*#" /root/.admins | sed -r 's/\#.*//' | sed 's/^[ \t]*//;s/[ \t]*$//')
fi

if [ -z "$greparg" ]; then
  greparg=":"
fi

USERROOT=$(mktemp)

while IFS='' read -r line || [[ -n "$line" ]]; do
#    echo "Text read from file: $line"
  if [[ ! $line =~ ^($greparg): ]]; then
   if [[ $line =~ ^(.+):.+:.+:0:.+ ]] || [[ $line =~ ^(.+):.+:.+:${wheel_id}:.+ ]]; then
    PASW=$(grep -P "^${BASH_REMATCH[1]}:" /etc/shadow | grep -v ':!!:' | grep -cv ':\*:')
    if [[ $PASW -gt 0 ]]; then
      echo "${BASH_REMATCH[1]}" >> "$USERROOT"
    fi
   fi
  fi
done < /etc/passwd

GROUPROOT=$(mktemp)
grep ":0:" /etc/group | grep -vP '^root:.*:0:root$'| grep -vP '^root:.*:0:$' | grep -vP "$greparg" > "$GROUPROOT"
grep ":${wheel_id}:" /etc/group | grep -vP "^wheel:.*:${wheel_id}:root$"| grep -vP "^wheel:.*:${wheel_id}:$" | grep -vP "$greparg" >> "$GROUPROOT"

greparg="ansible|"${greparg}

if [ -d /etc/sudoers.d ]; then
 SUDOROOT=$(mktemp)
 for sudofile in $(/bin/ls -1 /etc/sudoers.d/* 2>/dev/null); do
  while IFS='' read -r line || [[ -n "$line" ]]; do
#    echo "Text read from file: $line"
   if [[ ! $line =~ ^[[:space:]]*\# ]]; then
    if [[ ! $line =~ ^($greparg)(" "|$'\t') ]]; then
     if [[ $line =~ \(.*(root|ALL|wheel).*\) ]]; then
      if [[ ! $line =~ \(.*(root|ALL|wheel).*\).*/ ]]; then # only line without command
       if [[ ! $line =~ ^[[:space:]]*Defaults:root[[:space:]]*\!requiretty ]]; then
        echo "$line" >> "$SUDOROOT"
       fi
      fi
     fi
    fi
   fi
  done < "$sudofile"
 done
fi

FIN=$(mktemp)
if [ -s "$USERROOT" ]; then
  echo "Список пользователей с паролем и группой root (0) или wheel ($wheel_id)" >>"$FIN"
  cat "$USERROOT" >>"$FIN"
  rm "$USERROOT"
  echo >>"$FIN"
fi

if [ -s "$GROUPROOT" ]; then
  echo "Список пользователей, включенные в группу root (0) или wheel ($wheel_id)" >>"$FIN"
  cat "$GROUPROOT" >>"$FIN"
  rm "$GROUPROOT"
  echo >>"$FIN"
fi

if [ -s "$SUDOROOT" ]; then
  echo "Список пользователей, с правами root в конфиге sudo" >>"$FIN"
  cat "$SUDOROOT" >>"$FIN"
  rm "$SUDOROOT"
fi

if [ -s "$FIN" ]; then
    (hostname; cat "$FIN"; echo "Статья в КБ: https://e/articles/404" )| /usr/bin/tr -d '\015' | /bin/mail -s "HOST_sudo-check $(hostname)" root@example.ru
fi

[[ -f "$USERROOT" ]] && rm "$USERROOT"
[[ -f "$GROUPROOT" ]] && rm "$GROUPROOT"
[[ -f "$SUDOROOT" ]] && rm "$SUDOROOT"
[[ -f "$FIN" ]] &&  rm "$FIN"

