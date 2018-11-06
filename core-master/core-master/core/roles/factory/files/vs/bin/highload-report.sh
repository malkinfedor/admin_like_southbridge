#!/bin/bash
# highload-report v1.3.2

readonly PATH="/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin"

apacheup() {
    local ARG=${1:-NOARG}

    case "$ARG" in
        apache-start) clsems; apachestart;
            ;;
        apache-stop) apachestop;
            ;;
        force-restart) apachestop; apachestart;
            ;;
        *)
            return 0
    esac

}

apachestop() {
    # Аккуратное завершение httpd
    #
    local -a Apids=( "" )

    pschk() {
        Apids=( "" )
        mapfile -t Apids < <(pgrep httpd)
    }

    sigsend() {
        local s=${1:-SIGTERM}
        local -i p=0

        # Посылаем всем процессам из массива сигнал, заданный параметром
        for p in "${Apids[@]}"; do
            kill -s "$s" "$p"
        done
        # Перед следующей итерацией даём всем спокойно помереть
        sleep 4
    }

    for i in TERM INT ABRT KILL ALRM; do

        # Набиваем массив pid'ами апача
        pschk

        if (( ${#Apids[@]} == 0 )); then
            # Если массив пуст - подметаем выпавшие семафоры и выходим из функции
            clsems
            return
        else
            if [[ $i == "ALRM" ]]; then
                echo "ALARM! Unable to kill an Apache in the $(basename "$0")" 1>&2
                return
            else
                sigsend $i
            fi
        fi

    done
}

apachestart() {
    # Запуск апача
    # (эта ф-ция довольно бессмыссленна, но так красивее. И на тот случай, если когда-нибудь
    # в systemd отломают обратную совместимость с service из sysvinit)
    if pidof systemd >/dev/null; then
        systemctl restart httpd.service
    else
        service httpd restart
    fi
    # 'restart' потому, что если остался неубранный pid-файл, то 'start' может не проканать.
}

clsems() {
    # Очистка семафоров за апачем
    for sem in $(ipcs -s | awk '/apache/ { print $2 }'); do
        ipcrm sem "$sem"
    done
}

STAMP=$(date +%Y%m%d%H%M)
LOGFILE=/tmp/highload_${STAMP}.tmp
FLAGD=$(date +%s)
REPORT=""

RRUN=$(pgrep -c highload-report)
RRUN=0$RRUN
if [ "$RRUN" -gt 2 ]; then
  echo "Highload Report alredy running" >> "$LOGFILE"
  apacheup "$1"
  exit
fi


if [ -f /tmp/highload-report.flag ]; then
  FLAGL=$(head -1 /tmp/highload-report.flag )
  CNTL=$(tail -1 /tmp/highload-report.flag )
  DELTA=$((FLAGD-FLAGL))
  if [ "$DELTA" -gt 280 ] && [ "$CNTL" -eq 1 ]; then
    echo "$FLAGD" > /tmp/highload-report.flag
    echo 5 >> /tmp/highload-report.flag
    REPORT="5"
    DELTA=0
  fi
  if [ "$DELTA" -gt 280 ] && [ "$CNTL" -ne 10 ]; then
    echo "$FLAGD" > /tmp/highload-report.flag
    echo 10 >> /tmp/highload-report.flag
    REPORT="10"
    DELTA=0
  fi
  if [ "$DELTA" -gt 1180 ]; then
    echo "$FLAGD" > /tmp/highload-report.flag
    echo 1 >> /tmp/highload-report.flag
    REPORT="100"
  fi
else
  echo "$FLAGD" > /tmp/highload-report.flag
  echo 1 >> /tmp/highload-report.flag
  REPORT="1"
fi

if [ "$1" = "apache-stop" ] || [ "$1" = "apache-start" ]; then
    echo "ADDSUBJSTRING Failed port 8080" >> "$LOGFILE"
elif [ "$1" = "force-restart" ]; then
    echo "ADDSUBJSTRING MaxClients" >> "$LOGFILE"
else
    echo "ADDSUBJSTRING High LA" >> "$LOGFILE"
fi

if [ -f /etc/sysconfig/network-scripts/ifcfg-venet0:0 ];then
    MYIP=$(awk -F'=' '/IPADDR/ {print $2}' /etc/sysconfig/network-scripts/ifcfg-venet0:0)
fi

{
    echo "##HighLoad report from $(hostname -f) $MYIP"

    echo "###Tail /var/log/monit"
    echo "~~~"
    /usr/bin/tail -20 /var/log/monit 2>&1
    echo "~~~"

    echo "###Load average"
    echo "~~~"
    top -b | head -5 2>&1
    echo "~~~"

    echo "###Top-20 requests by IP-address for last 20 minures"
    echo "~~~"
    echo "Count   IP-address"
} >> "$LOGFILE"
if [ ! -f /usr/bin/host ]; then
    grep -h -A9999999 "$(date -d '-20 minutes' "+%d/%b/%Y:%H:%M")" /srv/www/*/logs/*-acc | awk '{print $1}' |sort|uniq -c |sort -rn|head -20 >> "$LOGFILE"
else
    IP20=$(mktemp)
    grep -h -A9999999 "$(date -d '-20 minutes' "+%d/%b/%Y:%H:%M")" /srv/www/*/logs/*-acc | awk '{print $1}' |sort|uniq -c |sort -rn|head -20 > "$IP20"
    while read -r line; do
        IP=$(echo "$line" | awk  '{print $2}')
        echo "$line" "$(/usr/bin/host "$IP" | grep -v 'not found' | grep -v 'no PTR record' | head -1 | awk '{ print $5 }' | sed 's/\.$//')" >> "$LOGFILE"
    done <  "$IP20"
    /bin/rm -rf "$IP20"
fi
{
    echo "~~~"

    echo "###Top-20 requested URI for last 20 minures"
    echo "~~~"
    echo "Count   URI"
    grep -h -A9999999 "$(date -d '-20 minutes' "+%d/%b/%Y:%H:%M")" /srv/www/*/logs/*-acc | awk '{print $7}' |sort|uniq -c |sort -rn|head -20
    echo "~~~"
} >> "$LOGFILE"

BLOCK_SESS=$(lsof -n | awk ' /sess_/ {
    load_sessions[$9]++;
    if (load_sessions[$9]>max_sess_link_count){
          max_sess_link_count = load_sessions[$9];
          max_sess_link_name = $9;
    };

    if ($4 ~ /.*uW$/ ){locked_id[$9]=$2};
}

END {
    print max_sess_link_count, max_sess_link_name,locked_id[max_sess_link_name];

    if (locked_id[max_sess_link_name] && max_sess_link_count>10) {
          #r=system("kill "locked_id[max_sess_link_name]);
          #if (!r) print "Locking process "locked_id[max_sess_link_name]" killed"
    }
}')

if [ -n "$BLOCK_SESS" ]; then
    {
	echo "### PHP block file session"
	echo "~~~"
	echo "$BLOCK_SESS"
	echo "~~~"
    } >> "$LOGFILE"
fi

if [ -f "/root/.mysql" ]; then
    {
	echo "###Mysql processes"
	echo "~~~"
	mysql -u root -p"$(cat /root/.mysql)" -e "SHOW FULL PROCESSLIST" | awk '$5 != "Sleep" && $7 != "NULL"' | sort -n -k 6 2>&1
	echo "~~~"
    } >> "$LOGFILE"
fi

if [ -f "/root/.postgresql" ]; then
    PGVER=$(psql --version | awk '{print $3}'| cut -d "." -f 1,2 2>&1)
    echo "###Postgresql $PGVER processes" >> "$LOGFILE"
    echo "~~~" >> "$LOGFILE"

    if [ -f "/etc/init.d/pgbouncer" ]; then
        PORT="5454"
    else
        PORT="5432"
    fi

    if [ "$PGVER" == "8.4" ] || [ "$PGVER" == "9.0" ] || [ "$PGVER" == "9.1" ] || [ "$PGVER" == "9.2" ];then
	echo "SELECT datname, NOW() - query_start AS duration, procpid, state, current_query FROM pg_stat_activity ORDER BY duration DESC;" | psql -U postgres --port=$PORT >> "$LOGFILE" 2>&1
    else
	echo "SELECT datname, NOW() - query_start AS duration, pid, state, query FROM  pg_stat_activity ORDER BY duration DESC;" | psql -U postgres --port=$PORT >> "$LOGFILE" 2>&1
    fi

    echo "~~~" >> "$LOGFILE"
fi

{
    echo "###Memory process list (top100)"
    echo "~~~"
    ps -ewwwo pid,size,state,command --sort -size | head -100 | awk '{ pid=$1 ; printf("%7s ", pid) }{ hr=$2/1024 ; printf("%8.2f Mb ", hr) } { for ( x=3 ; x<=NF ; x++ ) { printf("%s ",$x) } print "" }' 2>&1
    echo "~~~"

    echo "###CPU process list (top100)"
    echo "~~~"
    ps -ewwwo pcpu,pid,user,state,command --sort -pcpu | head -100 2>&1
    echo "~~~"
} >> "$LOGFILE"

LINKSVER=$(links --help | grep -c '\-retries' )
if [ "$LINKSVER" -eq 1 ]; then
    {
	echo "###Apache"
	echo "~~~"
	links -dump -width 110 -retries 1 -receive-timeout 30 http://localhost:8080/apache-status | grep -v 'OPTIONS \* HTTP/1.0' 2>&1
	echo "~~~"

	echo "###Nginx"
	echo "~~~"
	links -dump -retries 1 -receive-timeout 30 http://localhost/nginx-status 2>&1
	echo "~~~"
    } >> "$LOGFILE"
else
    {
	echo "###Apache"
	echo "~~~"
	links -dump -dump-width 110 -eval 'set connection.retries = 1' -eval 'set connection.receive_timeout = 30' http://localhost:8080/apache-status | grep -v 'OPTIONS \* HTTP/1.0' 2>&1
	echo "~~~"

	echo "###Nginx"
	echo "~~~"
	links -dump -eval 'set connection.retries = 1' -eval 'set connection.receive_timeout = 30' http://localhost/nginx-status 2>&1
	echo "~~~"
    } >> "$LOGFILE"
fi

echo "###Connections report (top10)" >> "$LOGFILE"
echo "~~~" >> "$LOGFILE"
if [ -x /usr/sbin/ss ]; then
  ss -nat | grep -E -v "Local|Active" |  awk '{print $4,$5,$1}' |  sed 's/:[0-9a-z]*//2' | sort | uniq -c | sort -n | tail -15 | column -t >> "$LOGFILE" 2>&1
else
  netstat -nat | grep -E -v "Local|Active" | awk '{print $4,$5,$6}' |  sed 's/:[0-9]*//2' | sort | uniq -c | sort -n | tail -15 | column -t >> "$LOGFILE" 2>&1
fi
{
    echo "~~~"

    echo "###Syn tcp/udp session"
    echo "~~~"
} >> "$LOGFILE"
if [ -x /usr/sbin/ss ]; then
    echo $(( $(ss -t4 state syn-recv | wc -l) + $(ss -t4 state syn-sent | wc -l) )) >> "$LOGFILE" 2>&1
else
    netstat -n | grep -E '(tcp|udp)' | grep -c SYN >> "$LOGFILE" 2>&1
fi
echo "~~~" >> "$LOGFILE"

if [ -f "/root/.mysql" ]; then
    {
	echo "###Mysql status"
	echo "~~~"
	mysql -u root -p"$(cat /root/.mysql)" -e "SHOW STATUS where value !=0" 2>&1
	echo "~~~"
    } >> "$LOGFILE"
fi

SUBJECT="$(hostname) HighLoad report"

if [ -n "$REPORT" ]; then
cat - "$LOGFILE" <<EOF | sendmail -oi -t
To: root
Subject: $SUBJECT
Content-Type: text/html; charset=utf8
Content-Transfer-Encoding: 8bit
MIME-Version: 1.0

EOF

fi

# Delete old HighLoad Report
find /tmp -maxdepth 1 -type f -name 'highload_*.tmp' -mtime +5 -delete

apacheup "$1"


exit 1
