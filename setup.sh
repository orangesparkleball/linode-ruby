#!/bin/bash
#
# Installs Mysql, Ruby Enterprise edition (RVM), and Nginx.
#
# <UDF name="mysql_password" Label="MySQL Root Password" default="change-me-please" example="fooBAR34Z" />


if [ ! -n "$MYSQL_PASSWORD" ]; then
  MYSQL_PASSWORD='change-me-please'
fi
if [ ! -n "$MYSQL_PERCENT" ]; then
  MYSQL_PERCENT=40
fi

##################
# New sources.list
##################
cat > /etc/apt/sources.list << EOF
## main & restricted repositories
deb http://us.archive.ubuntu.com/ubuntu/ karmic main restricted
deb-src http://us.archive.ubuntu.com/ubuntu/ karmic main restricted

deb http://security.ubuntu.com/ubuntu karmic-security main restricted
deb-src http://security.ubuntu.com/ubuntu karmic-security main restricted

## universe repositories
deb http://us.archive.ubuntu.com/ubuntu/ karmic universe
deb-src http://us.archive.ubuntu.com/ubuntu/ karmic universe
deb http://us.archive.ubuntu.com/ubuntu/ karmic-updates universe
deb-src http://us.archive.ubuntu.com/ubuntu/ karmic-updates universe

deb http://security.ubuntu.com/ubuntu karmic-security universe
deb-src http://security.ubuntu.com/ubuntu karmic-security universe
EOF



#################
# System Update
#################
apt-get -y update
apt-get -y install aptitude
aptitude -y full-upgrade
aptitude -y install wget vim less curl

########################################
# Install the required dependencies
########################################
apt-get -y install build-essential \
libxml2-dev \
libxslt-dev \
libcurl4-openssl-dev \
libreadline-dev \
libncurses5-dev \
libpcre3-dev \
libmysqlclient-dev \
libsqlite3-dev \
bison \
git-core

#################
# Install rvm
#################
bash < <(curl -s https://rvm.beginrescueend.com/install/rvm)

# Load rvm for script
if [ -s "$HOME/.rvm/scripts/rvm" ] ; then
  . "$HOME/.rvm/scripts/rvm"
elif [ -s "/usr/local/rvm/scripts/rvm" ] ; then
  . "/usr/local/rvm/scripts/rvm"
fi


###########################
# Setup RVM environment
###########################
cat >> /etc/profile << EOF

if [ -s "$HOME/.rvm/scripts/rvm" ] ; then
  . "$HOME/.rvm/scripts/rvm"
elif [ -s "/usr/local/rvm/scripts/rvm" ] ; then
  . "/usr/local/rvm/scripts/rvm"
fi

source /usr/local/lib/rvm
EOF

###################################
# Install, and set REE to default
###################################
rvm install ree
rvm use --default ree

#################
# Install Bundler
#################
gem install bundler --no-ri --no-rdoc

#################
# Install Nginx
#################
NGINX_URL="http://sysoev.ru/nginx/nginx-0.8.54.tar.gz"
NGINX_TGZ="nginx-0.8.54.tar.gz"
NGINX_DIR="nginx-0.8.54"

wget $NGINX_URL
tar zvxf $NGINX_TGZ
cd $NGINX_DIR

./configure --prefix=/opt/nginx
make
make install

curl -L http://bit.ly/f7QYpy > /opt/nginx/conf/nginx.conf 
curl -L http://bit.ly/hR889Q > /opt/nginx/sbin/nginx.reload.sh
chmod +x /opt/nginx/sbin/nginx.reload.sh

/opt/nginx/sbin/nginx

# Add the cron
cat > /etc/cron.d/nginx << EOF
*/5 * * * * root /opt/nginx/sbin/nginx.reload.sh
EOF

service cron restart

#################
# App Dir
#################
mkdir -p /opt/apps
chown -R root:www-data /opt/apps
chmod -R 2775 /opt/apps
chmod -R +s /opt/apps

#################
# Install MySQL
#################
echo "mysql-server-5.1 mysql-server/root_password password $MYSQL_PASSWORD" | debconf-set-selections
echo "mysql-server-5.1 mysql-server/root_password_again password $MYSQL_PASSWORD" | debconf-set-selections
apt-get -y install mysql-server mysql-client

echo "Sleeping while MySQL starts up for the first time..."
sleep 5

# Tunes MySQL's memory usage to utilize the percentage of memory you specify, defaulting to 40%
sed -i -e 's/^#skip-innodb/skip-innodb/' /etc/mysql/my.cnf # disable innodb - saves about 100M

MEM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo) # how much memory in MB this system has
MYMEM=$((MEM*MYSQL_PERCENT/100)) # how much memory we'd like to tune mysql with
MYMEMCHUNKS=$((MYMEM/4)) # how many 4MB chunks we have to play with

# mysql config options we want to set to the percentages in the second list, respectively
OPTLIST=(key_buffer sort_buffer_size read_buffer_size read_rnd_buffer_size myisam_sort_buffer_size query_cache_size)
DISTLIST=(75 1 1 1 5 15)

for opt in ${OPTLIST[@]}; do
  sed -i -e "/\[mysqld\]/,/\[.*\]/s/^$opt/#$opt/" /etc/mysql/my.cnf
done

for i in ${!OPTLIST[*]}; do
  val=$(echo | awk "{print int((${DISTLIST[$i]} * $MYMEMCHUNKS/100))*4}")
  if [ $val -lt 4 ]
    then val=4
  fi
  config="${config}\n${OPTLIST[$i]} = ${val}M"
done

sed -i -e "s/\(\[mysqld\]\)/\1\n$config\n/" /etc/mysql/my.cnf

service mysql restart

