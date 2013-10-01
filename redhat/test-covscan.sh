#!/bin/bash

# This will be list address to send job results to
rcptlist="minovotn@redhat.com"

get_official_srpm()
{
	local nvr="$1"

	srpm=$(echo $nvr | awk '{ split($0, a, "-"); print "http://download.devel.redhat.com/brewroot/packages/"a[1]"-"a[2]"/"a[3]"/"a[4]"/src/"$0".src.rpm" }')
	wget -q $srpm
	return $?
}

get_srpm_for_taskid()
{
	local taskid="$1"

	tmp=$(mktemp)
	url="https://brewweb.devel.redhat.com/taskinfo?taskID=$taskid"
	wget -O $tmp -q --no-check-certificate "$url"
	url="$(grep "\.src\.rpm" $tmp | grep "a href=\"http://download" | awk '{ split($0, a, "\""); print a[2] }')"
	rm -f $tmp

	wget -q $url
	return $?
}

if [ ! -x /usr/bin/covscan ]; then
	echo "ERROR: Cannot find covscan executable in your /usr/bin directory"
	exit 1
fi

if [ -z "$1" ]; then
	echo "Syntax: $0 brew_build_id"
	exit 1
fi

if ! klist | awk '/Default / { split($0, a, ": "); split(a[2], b, "@"); print b[1] }' > /dev/null; then
        echo "ERROR: Coverity scan client requires Kerberos ticket"
        exit 1
fi

task_id="$1"

wget -O test.tmp --no-check-certificate "https://brewweb.devel.redhat.com/taskinfo?taskID=$task_id" > /dev/null 2> /dev/null
task=$(cat test.tmp | grep "<h4>Information for task <a href=" | awk '{ split($0, a, ">"); split(a[3], b, "<"); split(b[1], c, "("); split(c[2], d, ","); gsub(/.src.rpm)/, "", d[2]); print d[2] }')

var=""
echo $task | grep rhev > /dev/null
if [ $? -eq 0 ]; then
        var="-rhev"
fi

if [[ "$task" == *rpms/* ]]; then
	task="$(cat test.tmp | grep buildArch | awk '{split($0, a, "buildArch"); split(a[2], b, "("); split(b[2], c, ","); gsub(/.src.rpm/, "", c[1]); if (NR == 1) print c[1] }')"
else
	taskid="$(cat test.tmp | grep buildArch | grep x86_64 | awk  '{ split($0, a, "taskID="); split(a[2], b, "\""); print b[1] }')"
fi

task="$(echo $task | awk '{ gsub(/[[:space:]]*/,"", $0); print }')"
taskOfficial="$(echo $task | awk '{ num=split($0, a, "."); for (i = 1; i <= num; i++) { if (a[i] == "el6") pos=i } ret=""; for (i = 1; i < pos; i++) ret=ret""a[i]"."; print ret"el6" }')"

if ! get_official_srpm "$taskOfficial"; then
	echo "ERROR: Cannot get official source RPM for $taskOfficial"
	exit 1
fi

if ! get_srpm_for_taskid "$taskid"; then
	echo "ERROR: Cannot get source RPM for $taskid"
	rm -f $taskOfficial
	exit 1
fi

srpmOfficial="$taskOfficial.src.rpm"
srpm="$task.src.rpm"

location=$(covscan version-diff-build --base-srpm=$srpmOfficial --srpm=$srpm --base-config=rhel-6-x86_64 --config=rhel-6-x86_64 --all --nowait --email-to=$rcptlist | awk '{ split($0, a, ": "); print a[2] }')
coverityid="$(echo http://cov01.lab.eng.brq.redhat.com/covscanhub/task/5627/ | awk ' { num=split($0, a, "/"); print a[num-1]; }')"
echo "New Coverity test job has been created: $coverityid ($location)"

rm -f $srpmOfficial $srpm

echo "Coverity scan job submitted"

read -n 1 -p "Would you like to watch task? (y/N) " q
if [ "$q" == "y" -o "$q" == "Y" ]; then
	covscan watch-tasks $coverityid
fi

