#!/bin/sh
#
# run OpenVPN client against ``test reference'' server
# - check that ping, http, ... via tunnel works
# - check that interface config / routes are properly cleaned after test end
#
# prerequisites:
# - openvpn binary in current directory
# - writable current directory to create subdir for logs
# - t_client.rc in current directory OR source dir that specifies tests
# - for "ping4" checks: fping binary in $PATH
# - for "ping6" checks: fping6 binary in $PATH
#

if [ -r ./t_client.rc ] ; then
    . ./t_client.rc
elif [ -r "${srcdir}"/t_client.rc ] ; then
    . "${srcdir}"/t_client.rc
else
    echo "$0: cannot find 't_client.rc' in current directory or" >&2
    echo "$0: source dir ('${srcdir}').  SKIPPING TEST." >&2
    exit 77
fi

if [ ! -x ./openvpn ]
then
    echo "no (executable) openvpn binary in current directory. FAIL." >&2
    exit 1
fi

if [ ! -w . ]
then
    echo "current directory is not writable (required for logging). FAIL." >&2
    exit 1
fi

if [ -z "$CA_CERT" ] ; then
    echo "CA_CERT not defined in 't_client.rc'. SKIP test." >&2
    exit 77
fi

if [ -z "$TEST_RUN_LIST" ] ; then
    echo "TEST_RUN_LIST empty, no tests defined.  SKIP test." >&2
    exit 77
fi

# make sure we have permissions to run ifconfig/route from OpenVPN
# can't use "id -u" here - doesn't work on Solaris
ID=`id`
if expr "$ID" : "uid=0" >/dev/null
then :
else
    echo "$0: this test must run be as root. SKIP." >&2
    exit 77
fi

LOGDIR=t_client-`hostname`-`date +%Y%m%d-%H%M%S`
if mkdir $LOGDIR
then :
else
    echo "can't create log directory '$LOGDIR'. FAIL." >&2
    exit 1
fi

exit_code=0

# ----------------------------------------------------------
# helper functions
# ----------------------------------------------------------
# print failure message, increase FAIL counter
fail()
{
    echo ""
    echo "FAIL: $@" >&2
    fail_count=$(( $fail_count + 1 ))
}

# print "all interface IP addresses" + "all routes"
# this is higly system dependent...
get_ifconfig_route()
{
    # linux / iproute2? (-> if configure got a path)
    if [ "/system/xbin" != "ip" ]
    then
	echo "-- linux iproute2 --"
	/system/xbin addr show     | grep -v valid_lft
	/system/xbin route show
	/system/xbin -6 route show | sed -e 's/expires [0-9]*sec //'
	return
    fi

    # try uname
    case `uname -s` in
	Linux)
	   echo "-- linux / ifconfig --"
	   LANG=C /system/xbin -a |egrep  "( addr:|encap:)"
	   LANG=C /bin/netstat -rn -4 -6
	   return
	   ;;
	FreeBSD|NetBSD|Darwin)
	   echo "-- FreeBSD/NetBSD/Darwin [MacOS X] --"
	   /system/xbin -a | egrep "(flags=|inet)"
	   /bin/netstat -rn | awk '$3 !~ /^UHL/ { print $1,$2,$3,$NF }'
	   return
	   ;;
	OpenBSD)
	   echo "-- OpenBSD --"
	   /system/xbin -a | egrep "(flags=|inet)" | \
		sed -e 's/pltime [0-9]*//' -e 's/vltime [0-9]*//'
	   /bin/netstat -rn | awk '$3 !~ /^UHL/ { print $1,$2,$3,$NF }'
	   return
	   ;;
	SunOS)
	   echo "-- Solaris --"
	   /system/xbin -a | egrep "(flags=|inet)"
	   /bin/netstat -rn | awk '$3 !~ /^UHL/ { print $1,$2,$3,$6 }'
	   return
	   ;;
    esac

    echo "get_ifconfig_route(): no idea how to get info on your OS.  FAIL." >&2
    exit 20
}

# ----------------------------------------------------------
# check ifconfig
#  arg1: "4" or "6" -> for message
#  arg2: IPv4/IPv6 address that must show up in out of "get_ifconfig_route"
check_ifconfig()
{
    proto=$1 ; shift
    expect_list="$@"

    if [ -z "$expect_list" ] ; then return ; fi

    for expect in $expect_list
    do
	if get_ifconfig_route | fgrep "$expect" >/dev/null
	then :
	else
	    fail "check_ifconfig(): expected IPv$proto address '$expect' not found in ifconfig output."
	fi
    done
}

# ----------------------------------------------------------
# run pings
#  arg1: "4" or "6" -> fping/fing6
#  arg2: "want_ok" or "want_fail" (expected ping result)
#  arg3... -> fping arguments (host list)
run_ping_tests()
{
    proto=$1 ; want=$2 ; shift ; shift
    targetlist="$@"

    # "no targets" is fine
    if [ -z "$targetlist" ] ; then return ; fi

    case $proto in
	4) cmd=fping ;;
	6) cmd=fping6 ;;
	*) echo "internal error in run_ping_tests arg 1: '$proto'" >&2
	   exit 1 ;;
    esac

    case $want in
	want_ok)   sizes_list="64 1440 3000" ;;
	want_fail) sizes_list="64" ;;
    esac

    for bytes in $sizes_list
    do
	echo "run IPv$proto ping tests ($want), $bytes byte packets..."

	echo "$cmd -b $bytes -C 20 -p 250 -q $targetlist" >>$LOGDIR/$SUF:fping.out
	$cmd -b $bytes -C 20 -p 250 -q $targetlist >>$LOGDIR/$SUF:fping.out 2>&1

	# while OpenVPN is running, pings must succeed (want='want_ok')
	# before OpenVPN is up, pings must NOT succeed (want='want_fail')

	rc=$?
	if [ $rc = 0 ] 				# all ping OK
	then
	    if [ $want = "want_fail" ]		# not what we want
	    then
		fail "IPv$proto ping test succeeded, but needs to *fail*."
	    fi
	else					# ping failed
	    if [ $want = "want_ok" ]		# not what we wanted
	    then
		fail "IPv$proto ping test ($bytes bytes) failed, but should succeed."
	    fi
	fi
    done
}

# ----------------------------------------------------------
# main test loop
# ----------------------------------------------------------
for SUF in $TEST_RUN_LIST
do
    echo -e "\n### test run $SUF ###\n"
    fail_count=0

    echo "save pre-openvpn ifconfig + route"
    get_ifconfig_route >$LOGDIR/$SUF:ifconfig_route_pre.txt

    # get config variables
    eval openvpn_conf=\"\$OPENVPN_CONF_$SUF\"
    eval expect_ifconfig4=\"\$EXPECT_IFCONFIG4_$SUF\"
    eval expect_ifconfig6=\"\$EXPECT_IFCONFIG6_$SUF\"
    eval ping4_hosts=\"\$PING4_HOSTS_$SUF\"
    eval ping6_hosts=\"\$PING6_HOSTS_$SUF\"

    echo -e "\nrun pre-openvpn ping tests - targets must not be reachable..."
    run_ping_tests 4 want_fail "$ping4_hosts"
    run_ping_tests 6 want_fail "$ping6_hosts"
    if [ "$fail_count" = 0 ] ; then
        echo -e "OK.\n"
    else
	echo -e "FAIL: make sure that ping hosts are ONLY reachable via VPN, SKIP test $SUF".
	exit_code=31
	continue
    fi

    echo " run ./openvpn $openvpn_conf"
    ./openvpn $openvpn_conf >$LOGDIR/$SUF:openvpn.log &
    opid=$!

    # make sure openvpn client is terminated in case shell exits
    trap "kill $opid" 0
    trap "kill $opid ; trap - 0 ; exit 1" 1 2 3 15

    echo "wait for connection to establish..."
    sleep 10

    # test whether OpenVPN process is still there
    if kill -0 $opid
    then :
    else
	echo -e "OpenVPN process has failed to start up, check log ($LOGDIR/$SUF:openvpn.log).  FAIL.\ntail of logfile follows:\n..." >&2
	tail $LOGDIR/$SUF:openvpn.log >&2
	trap - 0 1 2 3 15
	exit 10
    fi

    # compare whether anything changed in ifconfig/route setup?
    echo "save ifconfig+route"
    get_ifconfig_route >$LOGDIR/$SUF:ifconfig_route.txt

    echo -n "compare pre-openvpn ifconfig+route with current values..."
    if diff $LOGDIR/$SUF:ifconfig_route_pre.txt \
	    $LOGDIR/$SUF:ifconfig_route.txt >/dev/null
    then
	fail "no differences between ifconfig/route before OpenVPN start and now."
    else
	echo -e " OK!\n"
    fi

    # expected ifconfig values in there?
    check_ifconfig 4 "$expect_ifconfig4"
    check_ifconfig 6 "$expect_ifconfig6"

    run_ping_tests 4 want_ok "$ping4_hosts"
    run_ping_tests 6 want_ok "$ping6_hosts"
    echo -e "ping tests done.\n"

    echo "stopping OpenVPN"
    kill $opid
    wait $!
    rc=$?
    if [ $rc != 0 ] ; then
	fail "OpenVPN return code $rc, expect 0"
    fi

    echo -e "\nsave post-openvpn ifconfig + route..."
    get_ifconfig_route >$LOGDIR/$SUF:ifconfig_route_post.txt

    echo -n "compare pre- and post-openvpn ifconfig + route..."
    if diff $LOGDIR/$SUF:ifconfig_route_pre.txt \
	    $LOGDIR/$SUF:ifconfig_route_post.txt >$LOGDIR/$SUF:ifconfig_route_diff.txt
    then
	echo -e " OK.\n"
    else
	cat $LOGDIR/$SUF:ifconfig_route_diff.txt >&2
	fail "differences between pre- and post-ifconfig/route"
    fi
    if [ "$fail_count" = 0 ] ; then
        echo -e "test run $SUF: all tests OK.\n"
    else
	echo -e "test run $SUF: $fail_count test failures. FAIL.\n";
	exit_code=30
    fi
done

# remove trap handler
trap - 0 1 2 3 15
exit $exit_code
