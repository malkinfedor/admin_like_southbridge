#!/bin/sh

# e1000e permanent fix
    INSTALLED1=`ethtool -i eth0 | grep e1000e | wc -l`
    INSTALLED2=`ethtool -i eth1 | grep e1000e | wc -l`
    let "INSTALLED = $INSTALLED1 + $INSTALLED2"
    if [ $INSTALLED -gt 0 ]; then
	eth_make () {
	    echo "This fixup is applicable to your hardware"

	    var=$(ethtool -e $1 | grep 0x0010 | awk '{print $16}')
	    new=$(echo ${var:0:1}`echo ${var:1} | tr '014589bc' '2367abef'`)

	    if [ ! ${var:0:1}${var:1} == $new ]; then
	        echo "executing command: ethtool -E $1 magic $dev offset 0x1e value 0x$new"
	        ethtool -E $1 magic $dev offset 0x1e value 0x$new
	        echo "Change made. You *MUST* reboot your machine before changes take effect!"
	    fi
	}

	eth () {
	    bdf=$(ethtool -i $1 | grep "bus-info:" | awk '{print $2}')
	    dev=$(lspci -s $bdf -x | grep "00: 86 80" | awk '{print "0x"$5$4$3$2}')

	    case $dev in
	        0x10d38086)
	            echo "$1: is a \"82574L Gigabit Network Connection\""
	            eth_make $1
	        ;;
	        0x10f68086)
	            echo "$1: is a \"82574L Gigabit Network Connection\""
	            eth_make $1
	        ;;
	        0x150c8086)
	            echo "$1: is a \"82583V Gigabit Network Connection\""
	            eth_make $1
	        ;;
	        *)
	        echo "No appropriate hardware found for this fixup"
	        ;;
	    esac
	}

	eth eth0
	eth eth1
    fi
