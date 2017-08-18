#!/bin/bash
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

docker node ls --format "{{.ID}}" >  $tempfile
numberOfNodes=$( wc -l $tempfile | awk {'print $1'} )

while read nodeid; do
	hostname=`docker node ls --format "{{.ID}} {{.Hostname}}" | grep $nodeid | awk {'print $2'}`
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
if [ $problemN -eq 1 ]; then
	echo "Critical:" >> $nstatusfile
	echo "Swarm nodes INACTIVE: $numberOfNactive/$numberOfNodes" >> $nstatusfile
	cat /tmp/temp_nactive.txt >> $nstatusfile
	echo "Swarm nodes NOT READY: $numberOfNready/$numberOfNodes"  >> $nstatusfile
	cat /tmp/temp_nready.txt >> $nstatusfile
fi
	echo "Swarm nodes OK: $numberOfOk/$numberOfNodes" >> $nstatusfile
	cat /tmp/temp_ok.txt >> $nstatusfile

rm -f /tmp/temp_ok.txt
rm -f /tmp/temp_nactive.txt
rm -f /tmp/temp_nready.txt

cat $nstatusfile
rm -f $nstatusfile

}

checkServices() {
tempfile=/tmp/temp_services.txt
tempfile_ok=/tmp/temp_okservices.txt
tempfile_bad=/tmp/temp_badservices.txt
i=0
problemS=0
updategrace=3000
declare -a OKSERVICE
declare -a BADSERVICE

docker service ls --format "{{.ID}}" > $tempfile

while read serviceid; do

	servicename=`docker service ls -f id=$serviceid --format "{{.Name}}"`
	replica=`docker service ls --format "{{.Replicas}}"`
	fullreplica=$(echo $replica | cut -c 3)
	currreplica=$( echo $replica | cut -c 1 )
	allowedreplica=$((($fullreplica/2)+1))	

	if [ $(($curreplica + 1)) -lt $allowedreplica ]; then
#		echo "replicas are matching $replica" 
		echo "$servicename - $replica" >> $tempfile_ok 
	else
		cmd=$(docker service inspect $serviceid | grep UpdatedAt | cut -d "\"" -f 4 )
		updatetime=$( date -d $cmd +%s)
		currenttime=$( date +%s)
		timediff=$(( $currenttime - $updatetime ))
		if [ $timediff -gt $updategrace ]; then 
			problemS=1
			echo "Service is broken and has not been updated recently!"
			echo "$servicename - $replica" >> $tempfile_bad
		else
			echo "Service is not at full replica but was recently deployed"
		fi	
	fi

let "i++"
done < $tempfile

reviseServices $problemS $tempfile_ok $tempfile_bad
rm -f $tempfile 
}

reviseServices(){
problemS=$1
tempfileok=$2
tempfilebad=$3
statusfile=/tmp/serviceStatus.txt
#numberOfSok=$( sed '/^\s*$/d' $tempfileok | wc -l | awk {'print $1'} )
#numberOfSbad=$( sed '/^\s*$/d' $tempfilebad | wc -l | awk {'print $1'} )
#numberOfS=$(($numberOfSbad + $numberOfSok))

if [ $problemS -eq 1 ]; then
	echo "Critical: The following services have critical replicas!"
	cat $tempfilebad >> $statusfile
fi
echo "Services OK:" >> $statusfile
cat $tempfileok >> $statusfile

cat $statusfile

rm -f $tempfileok $tempfilebad $statusfile
}

summary() {
echo "=========================="
echo "Node Problem: $problemN"
echo "Service Problem: $problemS"
}


isManager
[ $ismanager -eq 0 ] && finish 0 "Not a manager - nothing to do"

checkNodes
checkServices
summary
