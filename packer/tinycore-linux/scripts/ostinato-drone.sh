set -e
set -x

# git branch, commit or tag
git_commit=v0.9

# setup environment
. /etc/profile
. /etc/init.d/tc-functions
getMirror

# load qt-4.x-base without the X dependecies
# alternatively a "tce-load -wi qt-4.x-base" loads it with all dependecies
wget -P /mnt/sda1/tce/optional $MIRROR/qt-4.x-base.tcz
wget -P /mnt/sda1/tce/optional $MIRROR/qt-4.x-base.tcz.md5.txt
touch /mnt/sda1/tce/optional/qt-4.x-base.tcz.dep
tce-load -i /mnt/sda1/tce/optional/qt-4.x-base.tcz

# load the remaining dependencies for ostinato
tce-load -wi qt-4.x-script
tce-load -wi glib2
tce-load -wi openssl
tce-load -wi libpcap

# load also iperf
tce-load -wi iperf3

# change tcedir to ram disk
mv /etc/sysconfig/tcedir /etc/sysconfig/tcedir.hd
ln -s /tmp/tce /etc/sysconfig/tcedir
sudo cp -a /usr/local/tce.installed /usr/local/tce.installed.hd

# setup compile environment
tce-load -wi compiletc
tce-load -wi squashfs-tools
tce-load -wi curl
export CFLAGS="-march=i486 -mtune=i686 -O2"
export CXXFLAGS="-march=i486 -mtune=i686 -O2"
export LDFLAGS="-Wl,-O1"

# compile protobuf
curl -L -O https://github.com/google/protobuf/releases/download/v2.6.1/protobuf-2.6.1.tar.gz
tar xfz protobuf-2.6.1.tar.gz
cd protobuf-2.6.1
./configure --prefix=/usr/local
make
sudo make install
sudo rm /usr/local/lib/libprotobuf.so
cd ..
rm -rf protobuf*

# compile ostinato
tce-load -wi qt-4.x-dev
tce-load -wi libpcap-dev
tce-load -wi git
git clone https://github.com/pstavirs/ostinato.git
cd ostinato
[ -n "$git_commit" ] && git checkout "$git_commit"
qmake -config release "QMAKE_CXXFLAGS+=$CXXFLAGS"
make server
sudo INSTALL_ROOT=/tmp/ostinato make server-install_subtargets
sudo chown -R root:root /tmp/ostinato
sudo chmod +s /tmp/ostinato/usr/local/bin/drone
cd ..
mksquashfs /tmp/ostinato ostinato-drone.tcz
md5sum ostinato-drone.tcz > ostinato-drone.tcz.md5.txt
echo -e "qt-4.x-base.tcz\nqt-4.x-script.tcz\nlibpcap.tcz" > ostinato-drone.tcz.dep
mv ostinato-drone.tcz* /mnt/sda1/tce/optional/
echo ostinato-drone.tcz >> /mnt/sda1/tce/onboot.lst
sudo rm -rf /tmp/ostinato
rm -rf ostinato*

# ostinato configuration file
mkdir -p .config/Ostinato
cat > .config/Ostinato/drone.ini <<'EOF'
[General]
RateAccuracy=Low
[PortList]
Include=eth*
Exclude=eth0
EOF

# change tcedir back to hard disk
rm -f /etc/sysconfig/tcedir
mv /etc/sysconfig/tcedir.hd /etc/sysconfig/tcedir
sudo rm -rf /usr/local/tce.installed
sudo mv /usr/local/tce.installed.hd /usr/local/tce.installed

# disable automatic interface configuration with dhcp
sudo sed -i -e '/label .*core/,/append / s/\(append .*\)/\1 nodhcp/' /mnt/sda1/boot/extlinux/extlinux.conf

#  add startup script for ostinato
cat >> /opt/bootlocal.sh <<'EOF'

# Boot parameter "nodhcp": network interfaces are not yet configured
if grep -q -w nodhcp /proc/cmdline; then
	# This waits until all devices have registered
	/sbin/udevadm settle --timeout=10

	# configure eth0 with DHCP
	/sbin/udhcpc -b -i eth0 -x hostname:$(/bin/hostname) -p /var/run/udhcpc.eth0.pid >/dev/null 2>&1 &

	# alternatively configure static interface address and route
	#ifconfig eth0 x.x.x.x netmask 255.255.255.0 up
	#route add default gw y.y.y.y
	#echo 'nameserver z.z.z.z' > /etc/resolv.conf

	# activate other eth devices
	NETDEVICES="$(awk -F: '/eth[1-9][0-9]*:/{print $1}' /proc/net/dev 2>/dev/null)"
	for DEVICE in $NETDEVICES; do
		sysctl -q -w net.ipv6.conf.$DEVICE.disable_ipv6=1
		ifconfig $DEVICE mtu 9000 up
	done
fi

# disable ostinato update, makes no sense in this environment
echo -e '# disable ostinato update\n127.0.0.127 update.ostinato.org' >> /etc/hosts

# start ostinato drone
sleep 2
su -c 'drone < /dev/null > /var/log/ostinato-drone.log 2>&1 &' gns3
EOF

exit 0
