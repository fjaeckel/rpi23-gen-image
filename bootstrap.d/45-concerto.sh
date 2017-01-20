#
# Build and Setup fbturbo Xorg driver
#

# Load utility functions
. ./functions.sh

chroot_exec apt-get -q -y --force-yes --no-install-recommends install xserver-xorg xserver-xorg-video-all \
  chromium unclutter ifplugd xinit blackbox \
  ruby rubygems-integration build-essential \
  vim screen git-core openssh-server \
  ntpdate ntp

cat > ${R}/tmp/install_bandshell.sh <<EOF
#!/bin/sh -e
cd /tmp
git clone git://github.com/concerto/bandshell.git
cd bandshell
gem build bandshell.gemspec
gem install *.gem
cd /
rm -rf /tmp/bandshell
EOF

chmod +x ${R}/tmp/install_bandshell.sh
chroot_exec /tmp/install_bandshell.sh

# create a user account that, when logged in,
# will start the X server and the player
chroot_exec useradd -m -s `which xinit` concerto

# create a .xinitrc that will start fullscreen chromium
cat > ${R}/home/concerto/.xinitrc << "EOF"
#!/bin/sh
URL=`cat /proc/cmdline | perl -ne 'print "$1\n" if /concerto.url=(\S+)/'`
if [ -z $URL ]; then
  URL=http://localhost:4567/screen
fi

# start window manager
blackbox &

# hide the mouse pointer
unclutter &

# disable power-management and screen blanking
xset -dpms
xset s off

# wait until the local http server is available
until wget -q http://localhost:4567
do
  sleep 2
done

# run the browser (if it crashes or dies, the X session should end)
chromium --proxy-pac-url=http://dashboard-proxy.int.s-cloud.net/proxy.pac --no-first-run --kiosk $URL
EOF


# FIXME
# modify inittab so we auto-login at boot as concerto
#sed -i -e 's/getty 38400 tty2/getty -a concerto tty2/' /etc/inittab


# create rc.local file to start bandshell
cat > ${R}/etc/rc.local << EOF
#!/bin/sh -e
/usr/local/bin/bandshelld start
EOF

# create init script to preload bandshell network config
cat > ${R}/etc/init.d/concerto-live << "EOF"
#!/bin/sh
### BEGIN INIT INFO
# Provides:   concerto-live
# Required-Start: $local_fs
# Required-Stop:  $local_fs
# X-Start-Before: $network
# Default-Start:  S
# Default-Stop:   0 6
# Short-Description:  Live system configuration for Concerto
# Description:    Live system configuration for Concerto
### END INIT INFO

. /lib/lsb/init-functions

MOUNTPOINT=/lib/live/mount/medium
MEDIUM_PATH_DIR=/etc/concerto
MEDIUM_PATH_FILE=medium_path

case "$1" in
start)
  log_action_begin_msg "Configuring Concerto Player"
  # try to remount boot medium as read-write
  # we don't care if this fails, the bandshell code will figure it out
  mount -o remount,rw,sync $MOUNTPOINT || true

  # create file indicating where mountpoint is
  mkdir -p $MEDIUM_PATH_DIR
  echo -n $MOUNTPOINT > $MEDIUM_PATH_DIR/$MEDIUM_PATH_FILE

  # generate /etc/network/interfaces from our configs
  /usr/local/bin/concerto_netsetup
  log_action_end_msg $?
  ;;
stop)
  ;;
esac
EOF

chmod +x ${R}/etc/init.d/concerto-live
chroot_exec update-rc.d concerto-live defaults

mkdir ${R}/root/.ssh/
cat > ${R}/root/.ssh/authorized_keys << EOF
# blerg
EOF

cat > ${R}/var/spool/cron/crontabs/root << EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 5 * * * /sbin/reboot
* 22,23,0,1,2,3,4,5,6 * * mo,tue,wed,thu,fri DISPLAY=:0 xset dpms force off
* * * * sat,sun DISPLAY=:0 xset dpms force off
* 7,8,9,10,11,12,13,14,15,16,17,18,19,20,21 * * mon,tue,wed,thu,fri DISPLAY=:0 xset -dpms
0 9,12,14,16,18,20 * * * pkill X
EOF

chmod 0600 ${R}/var/spool/cron/crontabs/root
chown :crontab ${R}/var/spool/cron/crontabs/root
