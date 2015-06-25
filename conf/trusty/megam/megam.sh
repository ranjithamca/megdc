#!/bin/bash

MEGAM_LOG="/var/log/megam/megamcib/megam.log"

ping -c 1 get.megam.io &> /dev/null

if [ $? -ne 0 ]; then
	echo "`date`: check your network connection. get.megam.io is down or not reachable!" >> $MEGAM_LOG
  exit 1
fi

host=`hostname`
echo "Adding entries in /etc/hosts" >> $MEGAM_LOG

get_ip(){
	while read Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT; do
		[ "$Mask" = "00000000" ] && \
		interface="$Iface" && \
		ipaddr=$(LC_ALL=C /sbin/ip -4 addr list dev "$interface" scope global) && \
		ipaddr=${ipaddr#* inet } && \
		ipaddr=${ipaddr%%/*} && \
		break
	done < /proc/net/route
}
get_ip

#ADD /etc/hosts entries
echo "127.0.0.1 `hostname` localhost" >> /etc/hosts
echo "$ipaddr `hostname` localhost" >> /etc/hosts
echo "/etc/hosts entries added"  >> $MEGAM_LOG

#For apt-add-repository command
sudo apt-get -y install software-properties-common python-software-properties >> $MEGAM_LOG

apt-get -y install megamcommon >> $MEGAM_LOG

##################################################### Install and configure riak #########################################################

apt-get -y install riak >> $MEGAM_LOG

sed -i "s/^[ \t]*storage_backend .*/storage_backend = leveldb/" /etc/riak/riak.conf
sed -i "s/^[ \t]*listener.http.internal =.*/listener.http.internal = $ipaddr:8098/" /etc/riak/riak.conf
sed -i "s/^[ \t]*listener.protobuf.internal =.*/listener.protobuf.internal = $ipaddr:8087/" /etc/riak/riak.conf

riak start  >> $MEGAM_LOG

##################################################### Install and configure ruby #########################################################
system_ruby() {
#RUBY CHANGE
apt-get -y install ruby2.0 ruby2.0-dev >> $MEGAM_LOG
rm /usr/bin/ruby
rm /usr/bin/gem

ln -s /usr/bin/ruby2.0 /usr/bin/ruby
ln -s /usr/bin/gem2.0 /usr/bin/gem

rvm use system
echo "System ruby used" >> $MEGAM_LOG
}

##################################################### MEGAMD PREINSTALL SCRIPT #########################################################

megamd_preinstall() {
#Gem install
gem install chef --no-ri --no-rdoc >> $MEGAM_LOG
mkdir -p /var/lib/megam/gems
cd /var/lib/megam/gems

wget https://s3-ap-southeast-1.amazonaws.com/megampub/gems/knife-opennebula-0.3.0.gem

gem install knife-opennebula-0.3.0.gem >> $MEGAM_LOG

##################################################### configure chef-server #########################################################
if [ -d "/opt/chef-server" ]; then
echo "Chef-server reconfigure" >> $MEGAM_LOG
sudo chef-server-ctl reconfigure >> $MEGAM_LOG

#Rabbitmq server has to be run in localhost
#cat /etc/rabbitmq/rabbitmq-env.conf	NODENAME=localhost

if [ -d "/etc/rabbitmq" ]; then

#Rabbitmq server has to be run in localhost for chef-server changes
#cat /etc/rabbitmq/rabbitmq-env.conf	NODENAME=localhost

sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl stop
cat > //etc/rabbitmq/rabbitmq-env.conf <<EOF
NODENAME=localhost
EOF
echo "Rabbitmq-server stoped" >> $MEGAM_LOG
fi


cat > //etc/chef-server/chef-server.rb <<EOF
nginx['url']="https://$ipaddr"
nginx['server_name']="$ipaddr"
nginx['non_ssl_port'] = 90
EOF

sudo chef-server-ctl reconfigure >> $MEGAM_LOG

sudo chef-server-ctl restart >> $MEGAM_LOG

sudo rabbitmq-server -detached >> $MEGAM_LOG

  set -e

  #chef_repo_dir=`find /var/lib/megam/megamd  -name chef-repo  | awk -F/ -vOFS=/ 'NF-=0' | sort -u`
   chef_repo_dir="/var/lib/megam/megamd/"

git clone https://github.com/megamsys/chef-repo.git $chef_repo_dir
  cp /etc/chef-server/admin.pem $chef_repo_dir/chef-repo/.chef
  cp /etc/chef-server/chef-validator.pem $chef_repo_dir/chef-repo/.chef
  
 sed -i "s@^[ \t]*chef_server_url.*@chef_server_url 'https://$ipaddr'@" $chef_repo_dir/chef-repo/.chef/knife.rb
  
mkdir $chef_repo_dir/chef-repo/.chef/trusted_certs

[ -f /var/opt/chef-server/nginx/ca/$ipaddr.crt ] && cp /var/opt/chef-server/nginx/ca/$ipaddr.crt /var/lib/megam/megamd/chef-repo/.chef/trusted_certs
[ -f /var/opt/chef-server/nginx/ca/$host.crt ] && cp /var/opt/chef-server/nginx/ca/$host.crt /var/lib/megam/megamd/chef-repo/.chef/trusted_certs
#chown -R cibadmin:cibadmin $chef_repo_dir/chef-repo
  knife cookbook upload --all -c $chef_repo_dir/chef-repo/.chef/knife.rb

fi

}

##################################################### Change config and restart services #################################################
service_restart() {
#MEGAM_GATEWAY
sed -i "s/^[ \t]*riak.url.*/riak.url=\"$ipaddr\"/" /usr/share/megam/megamgateway/conf/application-production.conf
stop megamgateway
start megamgateway

#MEGAMD
sed -i "s/.*:8087.*/  url: $ipaddr:8087/" /usr/share/megam/megamd/conf/megamd.conf
stop megamd
start megamd
}



apt-get -y install megamnilavu >> $MEGAM_LOG

cd /usr/share/megam/megamnilavu/
./nilavu install >> $MEGAM_LOG

./nilavu start >> $MEGAM_LOG

system_ruby

sudo apt-add-repository -y ppa:openjdk-r/ppa >> $MEGAM_LOG

sudo apt-get -y update >> $MEGAM_LOG

sudo apt-get -y install openjdk-8-jdk >> $MEGAM_LOG

apt-get -y install megamgateway >> $MEGAM_LOG

apt-get -y install rabbitmq-server >> $MEGAM_LOG

apt-get -y install chef-server >> $MEGAM_LOG

megamd_preinstall >> $MEGAM_LOG

apt-get -y install megamd >> $MEGAM_LOG

apt-get -y install megamanalytics >> $MEGAM_LOG

export DEBIAN_FRONTEND=noninteractive

apt-get -y install megammonitor >> $MEGAM_LOG

service_restart

echo "`date`: Step1: megam installed successfully." >> $MEGAM_LOG

