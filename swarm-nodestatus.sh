finish() {
 exitstatus=$1
 exitstring=$2
 echo "$exitstring | status=$exitstatus;1;2;"
 exit $exitstatus
}

isManager() {
cmd="docker node ls"
if $cmd > /dev/null; then
	ismanager=1
#	echo "node is a manager"
else
	ismanager=0
fi
}

checkNodes() {
i=0
problemN=0
tempfile=/tmp/tempfile.txt
declare -a OKNODE
declare -a NREADY
declare -a NACTIVE

#docker node ls --format "{{.ID}}" >  $tempfile
docker node ls | sed 1d | awk {'print $1'} > $tempfile
numberOfNodes=$( wc -l $tempfile | awk {'print $1'} )

while read nodeid; do
	#hostname=`docker node ls --format "{{.ID}} {{.Hostname}}" | grep $nodeid | awk {'print $2'}`
  hostname=`docker node inspect $nodeid | grep Hostname | cut -d "\"" -f 4`
  ready=0
	reachable=0
	if docker node inspect $nodeid | grep State | grep ready >/dev/null; then
		 ready=1
	fi
	if docker node inspect $nodeid | grep Availability | grep active>/dev/null; then
		 active=1
	fi
	[ $ready -eq 0 ] && NREADY[$i]=$hostname && problemN=1
	[ $active -eq 0 ] && NACTIVE[$i]=$hostname && problemN=1
	[ $ready -eq 1 ] && [ $active -eq 1 ] && OKNODE[$i]=$hostname

	let "i++"
done < $tempfile

echo ${NREADY[*]} > /tmp/temp_nready.txt
echo ${NACTIVE[*]} > /tmp/temp_nactive.txt
echo ${OKNODE[*]} > /tmp/temp_ok.txt

rm -f $tempfile
reviseStatus $problemN $numberOfNodes
}

reviseStatus() {
problemN=$1
numberOfNodes=$2
nstatusfile=/tmp/status.txt
numberOfNactive=$( sed '/^\s*$/d' /tmp/temp_nactive.txt| wc -l | awk {'print $1'} )
numberOfNready=$( sed '/^\s*$/d' /tmp/temp_nready.txt | wc -l | awk {'print $1'} )
numberOfOk=$(($numberOfNodes - ($numberOfNactive + $numberOfNready)))
echo "NODE HEALTH TEST:" >> $nstatusfile
if [ $problemN -eq 1 ]; then
	echo "Critical:" >> $nstatusfile
	echo "Swarm nodes INACTIVE: ($numberOfNactive/$numberOfNodes)" >> $nstatusfile
	cat /tmp/temp_nactive.txt >> $nstatusfile
	echo "Swarm nodes NOT READY: ($numberOfNready/$numberOfNodes)"  >> $nstatusfile
	cat /tmp/temp_nready.txt >> $nstatusfile
fi
	echo "Swarm nodes OK: ($numberOfOk/$numberOfNodes)" >> $nstatusfile
  cat /tmp/temp_ok.txt >> $nstatusfile

rm -f /tmp/temp_ok.txt
rm -f /tmp/temp_nactive.txt
rm -f /tmp/temp_nready.txt

cat $nstatusfile
rm -f $nstatusfile

}

isManager
[ $ismanager -eq 0 ] && finish 0 "Not a manager - nothing to do"

checkNodes
