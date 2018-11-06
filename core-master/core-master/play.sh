#!/bin/bash
#
# Run ansible-playbook from Gitlab CI
# Southbridge LLC, 2018 A.D.
#

set -o nounset
set -o errtrace
set -o pipefail

# DEFAULTS BEGIN
typeset CLIENT="${ANSIBLE_CLIENT:-NOP}"
typeset LIMIT="${ANSIBLE_LIMIT:-NOP}"
typeset EXTRA_VARS="${ANSIBLE_EXTRA_VARS:-}"
typeset LOCKFILE=""
typeset LOGIN="root"
typeset -i VERBOSE=0 DRY=0
typeset NEED_PASSWORD=''
# DEFAULTS END

# CONSTANTS BEGIN
readonly PATH=/bin:/usr/bin:/sbin:/usr/sbin
readonly TERM=xterm-color
readonly bn="$(basename "$0")"
readonly BIN_REQUIRED="tput logger mail pgrep"
readonly MAILTO="root"
readonly SUBJ="ERROR_ansible_play_auto_task"
# CONSTANTS END

main() {
    local fn=${FUNCNAME[0]}

    trap 'except $LINENO' ERR
    trap _exit EXIT

    _checks

    local scriptdir="" hosts="" ANSIBLE_LOG_PATH="" v=""
    local -a Extravars=("")

    export ANSIBLE_LOG_PATH

    scriptdir="$(dirname "$0")"
    cd "$scriptdir" || false

    if [[ -f ${CLIENT}/hosts ]]; then
	hosts=hosts
    elif [[ -f ${CLIENT}/$CLIENT ]]; then
	hosts=$CLIENT
    else
	echo_err "inventory file not found! Aborting"
	false
    fi

    if [[ $CLIENT =~ (.*)@(.*) ]]; then
      LOGIN="${BASH_REMATCH[1]}"
      CLIENT="${BASH_REMATCH[2]}"
    fi

    _lock
    # Ansible logging
    mkdir -p "logs/$CLIENT"
    ANSIBLE_LOG_PATH="logs/${CLIENT}/$(date '+%F_%T').log"
    echo_info "run ansible-playbook for '$CLIENT'. Log: '${PWD}/$ANSIBLE_LOG_PATH'"

    if [[ $LIMIT == "NOP" ]]; then
	LIMIT=""
    else
	LIMIT="-l $LIMIT"
    fi

    if (( VERBOSE )); then
	v="-"

	while (( VERBOSE )); do
	    v=${v}v
	    ((VERBOSE--))
	done
    fi

    if [[ -n "$EXTRA_VARS" ]]; then
	IFS_BAK="$IFS"
	IFS=","
	read -ra Extravars <<< "$EXTRA_VARS"
	IFS="$IFS_BAK"

	for (( i = 0; i < ${#Extravars[@]}; i++ )); do
	    if [[ ${Extravars[i]} =~ ^@ ]]; then
		Extravars[i]="-e \"${Extravars[i]}\""
	    else
		Extravars[i]="-e '{ $(echo "${Extravars[i]}"|sed -r "s/=(.*)/: \"\1\"/") }'"
	    fi
	done
    fi

    if (( DRY )); then
	echo "ansible-playbook -i \"${CLIENT}/${hosts}\" play-password.yml $NEED_PASSWORD --become --diff $LIMIT ${Extravars[*]} $v"
    else
	ansible-playbook -i "${CLIENT}/${hosts}" play-password.yml $NEED_PASSWORD --become --diff $LIMIT ${Extravars[*]} -e ansible_user="$LOGIN" $v
    fi

    _failed

    exit 0
}

_failed() {
    local fn=${FUNCNAME[0]}
    local failed="" hostalert=""

    if [[ ! -f "$ANSIBLE_LOG_PATH" ]]; then
	return
    fi

    failed="$(grep -E 'failed=[1-9]' "$ANSIBLE_LOG_PATH" || :)"

    if [[ -n "$failed" ]]; then
	hostalert="$(awk -F'|' '/failed=[1-9]/ { print $2; exit; }' "$ANSIBLE_LOG_PATH" | awk -F':' '{ gsub(/[[:space:]]+/, ""); print $1 }')"
        (
	echo "Error in launch ansible playbook:"
	echo "Error log: $ANSIBLE_LOG_PATH"
	echo
	grep -PB 1 '\|\s+(failed|fatal):\s' "$ANSIBLE_LOG_PATH"
	echo
	echo "$failed"
	) | tr -d '\015' | mail -s "ERROR_ansible_playbook_$hostalert" $MAILTO
    fi

}

_is_running() {
    local fn=${FUNCNAME[0]}
    local -i result=0

    result=$(pgrep -cf "ansible-playbook .*${CLIENT}" || :)

    printf '%i' "$result"
}

_lock() {
    local fn=${FUNCNAME[0]}

    if (( $(_is_running) )); then
	echo_info "another process is running for '$CLIENT', waiting for finish"

	local waitcount=0

	while [[ $(_is_running) -gt 0 && $waitcount -lt 90 ]]; do
	    echo -n "."
	    sleep 10
	    waitcount=$(( waitcount + 1 ))
	done

	echo

	if (( waitcount >= 90 )); then
	    echo_warn "another process not finished, terminating..."
	    (
	    hostname
	    echo "Another ansible-playbook process for '$CLIENT' run more than 15 minutes, task aborted"
	    ps ax
	    ) | tr -d '\015' | mail -s $SUBJ $MAILTO
	    exit 11
	fi
    fi

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

    if [[ ${CLIENT:-NOP} == "NOP" ]]; then
	echo_err "required parameter missing, see '--help'"
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

    [[ -f $LOCKFILE ]] && rm "$LOCKFILE"
    exit $ret
}

usage() {
    echo -e "\\tUsage: $bn [OPTIONS]\\n
    Options:

    -c, --client <domain>		ansible client name (example.org)
    -e, --extra-vars <key=value>	set additional variables as key=value
    -l, --limit <hostname[,hostname...]	ansible hosts limit
    -n, --dry-run			no make action, print out command only
    -v, --verbose			verbose mode; use -vvvv for debug
    -h, --help				print help

    ENVIRONMENT VARIABLES: ANSIBLE_CLIENT, ANSIBLE_LIMIT, ANSIBLE_EXTRA_VARS key=value,key=value,...
"
}
# Getopts
getopt -T; (( $? == 4 )) || { echo "incompatible getopt version" >&2; exit 4; }

if ! TEMP=$(getopt -o c:e:l:nhvk --longoptions client:,extra-vars:,limit:,dry-run,help,verbose,need-password -n "$bn" -- "$@")
then
    echo "Terminating..." >&2
    exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
    case $1 in
	-c|--client)		CLIENT=$2 ;	shift 2	;;
	-e|--extra-vars)	EXTRA_VARS="${EXTRA_VARS:-}${EXTRA_VARS:+,}${2}";	shift 2	;;
	-l|--limit)		LIMIT=$2 ;	shift 2	;;
	-k|--need-password)     NEED_PASSWORD=' -k '; shift ;;
	-n|--dry-run)		DRY=1 ;		shift	;;
	-h|--help)		usage ;		exit 0	;;
	-v|--verbose)		((VERBOSE++)) ;	shift	;;
        --)			shift ;		break	;;
        *)			usage ;		exit 1
    esac
done

# Backward compatibility
if [[ ${1:-NOP} != "NOP" ]]; then
    CLIENT=$1
fi

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
