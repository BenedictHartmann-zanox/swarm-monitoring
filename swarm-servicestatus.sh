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

checkServices() {
tempfile=/tmp/temp_services.txt
tempfile_ok=/tmp/temp_okservices.txt
tempfile_bad=/tmp/temp_badservices.txt
i=0
problemS=0
updategrace=3000
declare -a OKSERVICE
declare -a BADSERVICE

#docker service ls --format "{{.ID}}" > $tempfile
docker service ls | sed 1d | awk {'print $1'} > $tempfile

while read serviceid; do

	#servicename=`docker service ls -f id=$serviceid --format "{{.Name}}"`
  servicename=`docker service ls | sed 1d | awk {'print $2'}`
	#replica=`docker service ls --format "{{.Replicas}}"`
  replica=`docker service ls | sed 1d | awk {'print $4'}`
	fullreplica=$(echo $replica | cut -d "/" -f 2)
	currreplica=$( echo $replica | cut -d "/" -f 1)
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
touch $tempfilebad
statusfile=/tmp/serviceStatus.txt
numberOfSok=$( sed '/^\s*$/d' $tempfileok | wc -l | awk {'print $1'} )
numberOfSbad=$( sed '/^\s*$/d' $tempfilebad | wc -l | awk {'print $1'} )
numberOfS=$(($numberOfSbad + $numberOfSok))
echo "SERVICE HEALTH TEST:" >$statusfile
if [ $problemS -eq 1 ]; then
	echo "Critical: The following services have critical replicas: ($numberOfSbad/$numberOfSok)"
	cat $tempfilebad >> $statusfile
fi
echo "Services OK: ($numberOfSok/$numberOfS)" >> $statusfile
cat $tempfileok >> $statusfile

cat $statusfile

rm -f $tempfileok $tempfilebad $statusfile
}

isManager
[ $ismanager -eq 0 ] && finish 0 "Not a manager - nothing to do"

checkServices
