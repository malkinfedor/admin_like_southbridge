#!/bin/bash
#
# Ansible initialization script for new ds host
# Southbridge LLC, 2018 A.D.
#

set -o nounset
set -o errtrace
set -o pipefail

# DEFAULTS BEGIN
declare THOST="" LOGIN="root" PROXY_USER="" ANSIBLE_LOG_PATH=""
export THOST LOGIN PROXY_USER PROXY_PORT ANSIBLE_LOG_PATH NEED_RESTART
PROXY_USER="$(whoami)"
PROXY_PORT=22
NEED_RESTART='true'
NEED_PASSWORD=''
typeset -i DRY=0 VERBOSE=0
# DEFAULTS END

# CONSTANTS BEGIN
readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly bn="$(basename "$0")"
readonly BIN_REQUIRED="envsubst ansible-playbook"
readonly TEMPLATE="./core/plays/ds-init.yml.tmpl"
readonly PLAYBOOK="ds-init.yml"
# CONSTANTS END

main() {
    local fn=${FUNCNAME[0]}

    trap 'except $LINENO' ERR
    trap _exit EXIT

    _checks

    local -a Files=()
    local -i match_count=0
    local inventory="" dup=""

    if [[ $THOST =~ (.*)@(.*) ]]; then
      LOGIN="${BASH_REMATCH[1]}"
      THOST="${BASH_REMATCH[2]}"
    fi

    # Населяем массив Files путями к файлам hosts, лежащими не глубже второго уровня вложенности
    mapfile -t Files < <(find . -maxdepth 2 -type f -name hosts)
    # Считаем файлы с незакомментированными строками, содержащими имя целевого хоста
    for (( i = 0; i < ${#Files[@]}; i++ )); do
	if grep -Pq "(^\\[?$THOST\\]?|^\\s+$THOST)" "${Files[i]}"; then
	    inventory="${Files[i]}"
	    match_count=$((match_count+1))
	    dup="$dup ${Files[i]}"
	fi
    done
    # Если таких строк не нашлось -- сообщаем об этом и выходим
    if (( ! match_count )); then
	echo_err "Host '$THOST' is not found in your inventory"
	false
    fi
    # Если таких строк больше одной -- вываливаемся с руганью на множественость
    if (( match_count > 1 )); then
	echo_err "Host '$THOST' is not unique! Check your inventory (${dup})"
	false
    fi

    envsubst < "$TEMPLATE" > "$PLAYBOOK"

    local b="" v=""

    if [[ $LOGIN != "root" ]]; then
	b="--become"
    fi

    if (( VERBOSE )); then
	v="-"
	local tv="$VERBOSE"
	while (( tv )); do
	    v=${v}v
	    ((tv--))
	done
    fi
    # Ansible logging
    mkdir -p "logs/$THOST"
    ANSIBLE_LOG_PATH="logs/${THOST}/$(date '+%FT%H%M%S').log"

    echo_info "run command 'ansible-playbook -i \"$inventory\" \"$PLAYBOOK\" $b $v $NEED_PASSWORD --force-handlers'. Ansible log: '${PWD}/$ANSIBLE_LOG_PATH'"

    if (( ! DRY )); then
	ansible-playbook -i "$inventory" "$PLAYBOOK" $b $v $NEED_PASSWORD --force-handlers
    fi

    exit 0
}

_checks() {
    local fn=${FUNCNAME[0]}
    # Required binaries check
    for i in $BIN_REQUIRED; do
        if ! command -v "$i" >/dev/null
        then
            echo_err "required binary '$i' is not installed"
            false
        fi
    done

    if [[ $THOST == "NOP" ]]; then
	echo_err "required parameter missing, see '--help'"
	false
    fi

    if [[ ! -f "$TEMPLATE" ]]; then
	echo_err "template '$TEMPLATE' not found."
	false
    fi
}

except() {
    local ret=$?
    local no=${1:-no_line}

    echo_fatal "error occured in function '$fn' on line ${no}."

    logger -p user.err -t "$bn" "* FATAL: error occured in function '$fn' on line ${no}."
    exit $ret
}

_exit() {
    local ret=$?

    exit $ret
}

usage() {
    echo -e "\\n    Usage: $bn [OPTIONS] [login@]<target_host>\\n
    Options:

    -l, --login <user>		username for login to a target host (default: root)
    -n, --dry-run		no make action, print out command only
    -N, --no-restart		do not restart host
    -p, --proxy-user <user>	set user on ssh-proxy host; default is current user
    -P, --proxy-port <port>	set port on ssh-proxy host; default 22
    -v, --verbose		ansible-playbook verbose mode (-vvv for more...)
    -h, --help			print help
    target_host			DNS name of a target host
"
}
# Getopts
getopt -T; (( $? == 4 )) || { echo "incompatible getopt version" >&2; exit 4; }

if ! TEMP=$(getopt -o l:nNp:P:vhk --longoptions login,dry-run,no-restart,proxy-user:,proxy-port:,verbose,help,need-password -n "$bn" -- "$@")
then
    echo "Terminating..." >&2
    exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
    case $1 in
	-l|--login)		LOGIN=$2 ;	shift 2	;;
	-n|--dry-run)		DRY=1 ;		shift	;;
	-p|--proxy-user)	PROXY_USER=$2 ;	shift 2	;;
	-P|--proxy-port)	PROXY_PORT=$2 ;	shift 2	;;
	-k|--need-password)	NEED_PASSWORD=' -k '; shift ;;
	-N|--no-restart)	NEED_RESTART='false'; shift ;;
	-h|--help)		usage ;		exit 0	;;
	-v|--verbose)		((VERBOSE++)) ;	shift	;;
        --)			shift ;		break	;;
        *)			usage ;		exit 1
    esac
done

# Position parameter
THOST="${1:-NOP}"

readonly C_RST="tput sgr0"
readonly C_RED="tput setaf 1"
readonly C_GREEN="tput setaf 2"
readonly C_YELLOW="tput setaf 3"
readonly C_BLUE="tput setaf 4"
readonly C_CYAN="tput setaf 6"
readonly C_WHITE="tput setaf 7"

echo_err() { $C_WHITE; echo "* ERROR: $*" 1>&2; $C_RST; }
echo_fatal() { $C_RED; echo "* FATAL: $*" 1>&2; $C_RST; }
echo_warn() { $C_YELLOW; echo "* WARNING: $*" 1>&2; $C_RST; }
echo_info() { $C_CYAN; echo "* INFO: $*" 1>&2; $C_RST; }
echo_ok() { $C_GREEN; echo "* OK" 1>&2; $C_RST; }

main

## EOF ##
