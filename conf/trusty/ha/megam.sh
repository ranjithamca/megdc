#!/bin/bash

#1. In new ha server, install brain(megam, cobbler and opennebula)
#2. install drbd on both servers
#3. On both old and new servers, have a equal sized partition(eg : /dev/xvdf)
#4. run the process of megam_drbd_cookbook
#5. Decide where ha-proxy shoul be? in same server or another

#megam_drbd_cookbook process

#sh megam.sh remote_ip="192.168.2.101" remote_hostname="megamslave" data_dir="/var/lib/" local_disk="/dev/sda9" remote_disk="/dev/sda9" master


ip() {
while read Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT; do
		[ "$Mask" = "00000000" ] && \
		interface="$Iface" && \
		ipaddr=$(LC_ALL=C /sbin/ip -4 addr list dev "$interface" scope global) && \
		ipaddr=${ipaddr#* inet } && \
		ipaddr=${ipaddr%%/*} && \
		break
	done < /proc/net/route
}

apt-get -y update && apt-get upgrade -y

apt-get install drbd8-utils linux-image-extra-virtual -y

#Get ip of the two nodes as argument
master=false
for i in "$@"
do
case $i in
    remote_ip=*)
    remote_ip="${i#*=}"
    ;;
    remote_hostname=*)
    remote_hostname="${i#*=}"
    ;;
    remote_disk=*)
    remote_disk="${i#*=}"
    ;;
    local_disk=*)
    local_disk="${i#*=}"
    ;;
    data_dir=*)
    data_dir="${i#*=}"
    ;;
    master*)
    master=true
    ;;
esac
done
ip
node1_ip=$ipaddr
node2_ip="$remote_ip"

node1_disk=$local_disk
node2_disk="$remote_disk"

node1_host="`hostname`"
node2_host="$remote_hostname"

tmp_dir="/tmp/drbd"
mkdir $tmp_dir 

resource="megam"
device="/dev/drbd0"
fs_type="ext4"


pacemaker()
{
apt-get -y update && /usr/bin/apt-get -y install -o 'DPkg::Options::force=--force-confnew' pacemaker heartbeat sysv-rc-conf && /usr/sbin/update-rc.d -f corosync remove

cat << EOT >> /etc/ha.d/ha.cf
## generated by LCMC 1.6.1

keepalive 2
warntime 20
deadtime 30
initdead 30
crm respawn
compression bz2
compression_threshold 20
traditional_compression on
logfacility local0
node $node1_host 
node $node2_host

ucast eth0 $node1_ip
ucast eth0 $node2_ip
# respawn hacluster /usr/lib/heartbeat/dopd
# apiauth dopd gid=haclient uid=hacluster
# respawn root /usr/lib/heartbeat/mgmtd -v
# apiauth mgmtd uid=root
EOT

cat << EOT >> /etc/ha.d/authkeys
## generated by drbd-gui

auth 1
1 sha1 3JRhLiuPCat7S6A1SaLJM8eygOSYIqBb
EOT

chmod 600 /etc/ha.d/authkeys

mv /usr/lib/heartbeat/lrmd{,.cluster-glue}
cd /usr/lib/heartbeat/
ln -s ../pacemaker/lrmd

service heartbeat reload
service heartbeat restart

until crm status | egrep -q "failed"
do
   echo "."
   sleep 1
done

if [ $master ]; then

crm configure property stonith-enabled=false
crm configure property no-quorum-policy=ignore
sysv-rc-conf drbd off

cat << EOT >> /tmp/crm_conf.txt
primitive VolumeDRBD ocf:linbit:drbd params drbd_resource="$resource" \
 operations $id="VolumeDRBD-operations" \
 op start interval="0" timeout="240"\
 op promote interval="0" timeout="90" \
 op demote interval="0" timeout="90" \
 op stop interval="0" timeout="100" \
 op monitor interval="40" timeout="60" start-delay="0" \
 op notify interval="0" timeout="90" \
 meta target-role="started"
primitive FileSystemDRBD ocf:heartbeat:Filesystem \
 params device="$device" directory="$data_dir" fstype="$fs_type" \
 operations $id="FileSystemDRBD-operations" \
 op start interval="0" timeout="60" \
 op stop interval="0" timeout="60" fast_stop="no" \
 op monitor interval="40" timeout="60" start-delay="0" \
 op notify interval="0" timeout="60"
ms MasterDRBD VolumeDRBD \
 meta clone-max="2" notify="true" target-role="started"
group Cluster FileSystemDRBD \
 meta target-role="Started"
colocation WebServerWithIP inf: Cluster MasterDRBD:Master
order StartFileSystemFirst inf: MasterDRBD:promote Cluster:start
commit
EOT

crm -F configure < /tmp/crm_conf.txt

fi              #IF  MASTER

}



cat << EOT >> /etc/hosts
$node1_ip $node1_host
$node2_ip $node2_host
EOT

cat << EOT >> /etc/drbd.d/$resource.res
resource megam {
  device    "$device";
  meta-disk internal;
  on $node1_host {
    disk      "$node1_disk";
    address $node1_ip:7789;
  }
  on $node2_host {
    disk      "$node2_disk";
    address  $node2_ip:7789;
  }
}
EOT

#init drbd
drbdadm create-md $resource

service drbd start

#To test drbd process --> cat /proc/drbd


if [ $master ]; then
#Make primary
drbdadm -- --overwrite-data-of-peer primary all
mkfs -t $fs_type $device

cp -r $data_dir/* $tmp_dir
mount $device $data_dir
mv $tmp_dir/* $data_dir

until drbdadm cstate $resource | egrep -q "SyncTarget"
do
   echo "."
   sleep 1
done

fi              #IF  MASTER

#####################################
#Wait For Synchronization
#####################################
until drbdadm cstate $resource | egrep -q "Connected"
do
   echo "."
   sleep 1
done

pacemaker

