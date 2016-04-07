#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root!" 1>&2
   exit 1
fi

backupdir="/root/backup/enable-hm-mot-rpi-pcp/"
backupdirtmp="/root/backup/enable-hm-mot-rpi-pcp-tmp/"
sfn="/etc/init.d/hm-mod-rpi-pcb"

if [ $(cat /etc/*-release|grep raspbian|wc -l) -eq 0 ]
  then
  echo "not an raspbian distribution, aborting..."
  exit 1
fi
# if [ $(cat /etc/*-release|grep wheezy|wc -l) -eq 0 ]
  # then
  # echo "not an wheezy distribution, aborting..."
  # exit 1
# fi

echo "startet on raspbian"
echo "--------------------"

case "$1" in
  uninstall)
    if [ -d $backupdir ]
      then
      echo "restore changed files..."
      cp $backupdir/rfd.conf /var/lib/lxc/lxccu/root/usr/local/etc/config/
      cp $backupdir/cmdline.txt /boot/
      cp $backupdir/inittab /etc/
      sleep 2
      echo "uninstall gpio reset service"
      insserv -r $sfn
      rm $sfn
      if [ $(cat /var/lib/lxc/lxccu/root/www/api/methods/bidcosrf/setconfiguration-rf.tcl|grep "#puts \$fd \"Type = CCU2\""|wc -l) -eq 0 ]
        then
        echo "create patch file"
        rm -Rf /tmp/hm-mod-rpi-pcb_rfd_disable.patch
        wget -O /tmp/hm-mod-rpi-pcb_rfd_disable.patch http://cdn.lxccu.com/hm-mod-rpi-pcb_rfd_disable.patch
        patch -i /tmp/hm-mod-rpi-pcb_rfd_disable.patch /var/lib/lxc/lxccu/root/www/api/methods/bidcosrf/setconfiguration-rf.tcl
      fi
      sleep 2
      echo "uninstall done"
      echo ""
      echo "========================================="
      echo "reboot in 10 seconds to apply settings (or press CTRL+C to chancel reboot)..."
      echo "========================================="
      for i in {10..1}; do sleep 1; echo "$i"; done
      reboot
      exit 0
    else
      echo "backup directory $backupdir do not exist"
      echo ""
      echo "uninstall failed!" 
      exit 1
    fi

;;
  install)
if [ $(dpkg -l|grep lxc|wc -l) -eq 0 ]
  then
  echo "please install lxc first!"
  exit 3
fi
echo "lxc installed..."

if [ $(lxc-ls|grep lxccu|wc -l) -eq 0 ]
  then
  echo "lxccu not installed, aborting"
  exit 3
fi
echo "lxccu installed..."

if [ ! -d $backupdirtmp ]
  then
  mkdir -p $backupdirtmp
fi
cp /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf $backupdirtmp
cp /boot/cmdline.txt $backupdirtmp
cp /etc/inittab $backupdirtmp

if [ ! -d $backupdir ]
  then
  echo "backup all files changed below"
  mkdir $backupdir -p

  cp /etc/inittab $backupdir
  cp /boot/cmdline.txt $backupdir
  cp /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf $backupdir

  echo "backup done"
  ls -lah $backupdir
  sleep 3
fi

if [ $(lxc-info -n lxccu|grep RUNNING|wc -l) -eq 1 ]
  then
  echo "stop lxccu if it is running (can take a while)"
  lxc-stop -n lxccu
  sleep 2
fi

# if [ $(cat /etc/inittab|grep "#T0:23:respawn:/sbin/getty -L ttyAMA0 115200 vt100"|wc -l) -eq 0 ]
  # then
  # echo "disable serial console in /etc/inittab"
  # sed -i 's/T0:23:respawn:\/sbin\/getty -L ttyAMA0 115200 vt100/#T0:23:respawn:\/sbin\/getty -L ttyAMA0 115200 vt100/g' /etc/inittab
  # sleep 2
# fi
# if [ $(cat /boot/cmdline.txt|grep "console=ttyAMA0,115200"|wc -l) -eq 1 ]
  # then
  # echo "disable serial console in /boot/cmdline.txt"
  # sed -i 's/ console=ttyAMA0,115200//g' /boot/cmdline.txt
  # sleep 2
# fi 

# disable serial console
# code from official rpi-config. should work on both wheezy and jessie
if command -v systemctl > /dev/null && systemctl | grep -q '\-\.mount'; then
    SYSTEMD=1
elif [ -f /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
    SYSTEMD=0
else
    echo "Warning: Unrecognised init system"
fi
if [ $SYSTEMD -eq 0 ]; then
    sed -i /etc/inittab -e "s|^.*:.*:respawn:.*ttyAMA0|#&|"
fi
sed -i /boot/cmdline.txt -e "s/console=ttyAMA0,[0-9]\+ //"
sed -i /boot/cmdline.txt -e "s/console=serial0,[0-9]\+ //"


if [ $(cat /var/lib/lxc/lxccu/root/www/api/methods/bidcosrf/setconfiguration-rf.tcl|grep "#puts \$fd \"Type = CCU2\""|wc -l) -eq 1 ]
  then
  echo "create patch file"
  rm -Rf /tmp/hm-mod-rpi-pcb_rfd_enable.patch
  wget -O /tmp/hm-mod-rpi-pcb_rfd_enable.patch http://cdn.lxccu.com/hm-mod-rpi-pcb_rfd_enable.patch
  patch -i /tmp/hm-mod-rpi-pcb_rfd_enable.patch /var/lib/lxc/lxccu/root/www/api/methods/bidcosrf/setconfiguration-rf.tcl
fi

if [ $(insserv -s|grep hm-mod|wc -l) -eq 0 ]
  then 
  echo "create service for enabling gpio pin for reset line of hm-mod-rpi-pcb on every reboot"
  cat > $sfn <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          hm-mod-rpi-pcb_lxccu
# Required-Start: udev mountkernfs $remote_fs
# Required-Stop:
# Default-Start: S
# Default-Stop:
# Short-Description: Enables GPIO 18 as reset Interface for HM RF Module for Raspberry
# Description:
### END INIT INFO

. /lib/lsb/init-functions

case "\$1" in
  start)
    log_daemon_msg "Enables GPIO 18 as Reset Interface for Homematic RF wireless module"
    printf " Enables GPIO 18 as Reset Interface for Homematic RF wireless module"
    if [ ! -d /sys/class/gpio/gpio18 ]
      then
      echo "Preparing GPIO for HM-MOD-UART..."
      echo 18 > /sys/class/gpio/export
      echo out > /sys/class/gpio/gpio18/direction
      printf "Preparing GPIO for HM-MOD-UART done!"
    fi
    # hold reset until rfd starts
    echo 0 > /sys/class/gpio/gpio18/value
    log_end_msg 0
    ;;
  *)
    echo "Usage: $0 start" >&2
    exit 3
    ;;
esac
EOF

  echo "installing reset gpio as service"
  chmod +x $sfn
  insserv $sfn
  sleep 2
fi 

echo "setup device in lxc if not done already"
if [ ! -e /var/lib/lxc/lxccu/root/dev/ttyAPP0 ]
    then
    echo "Creating lxccu /dev/ttyAPP0"
    mknod -m 666 /var/lib/lxc/lxccu/root/dev/ttyAPP0 c 204 64
fi

echo "integrate the hm-mod-rpi-pcb in lxccu rfd config"
if [ ! -L /var/lib/lxc/lxccu/root/dev/ccu2-ic200 ]
  then
  rm -Rf /var/lib/lxc/lxccu/root/dev/ccu2-ic200
  ln -s /sys/class/gpio/gpio18/value  /var/lib/lxc/lxccu/root/dev/ccu2-ic200
fi

if [ $(cat /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf|grep "Interface 0"|wc -l) -eq 0 ]
  then
    echo "[Interface 0] block in rfd.conf not found, insert it..."

    sed -i '/Replacemap File = \/firmware\/rftypes\/replaceMap\/rfReplaceMap.xml/a \[Interface 0\]' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sed -i '/Replacemap File = \/firmware\/rftypes\/replaceMap\/rfReplaceMap.xml/a #' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sed -i '/\[Interface 0\]/a Type = CCU2' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sed -i '/Type = CCU2/a Serial Number = 123456789' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sed -i '/Serial Number = 123456789/a Description = CCU2-Coprocessor' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sed -i '/Description = CCU2-Coprocessor/a ComPortFile = \/dev\/ttyAPP0' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sed -i '/ComPortFile = \/dev\/ttyAPP0/a AccessFile = \/dev\/null' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sed -i '/AccessFile = \/dev\/null/a ResetFile = \/dev\/ccu2-ic200' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf

    #sed -i '/Replacemap File = \/firmware\/rftypes\/replaceMap\/rfReplaceMap.xml/ { N; s/Replacemap File = \/firmware\/rftypes\/replaceMap\/rfReplaceMap.xml\n\n/\[Interface 0\]\nType = CCU2\nSerial Number = 123456789\nDescription = CCU2-Coprocessor\nComPortFile = \/dev\/ttyAPP0\nAccessFile = \/dev\/null\nResetFile = \/dev\/ccu2-ic200\n\n&/ }' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sleep 2
else
    echo "[Interface 0] block found in rfd.conf checking it..."
    sed -i '/^\[Interface 0\]$/,/^\[/ s/^ResetFile = \/sys\/class\/gpio\/gpio18\/value/ResetFile = \/dev\/ccu2-ic200/' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sed -i '/^\[Interface 0\]$/,/^\[/ s/^ResetFile = \/dev\/null/ResetFile = \/dev\/ccu2-ic200/' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sed -i '/^\[Interface 0\]$/,/^\[/ s/^ComPortFile = \/dev\/ttyAMA0/ComPortFile = \/dev\/ttyAPP0/' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    sleep 2
    #sed -i 's/Type = CCU2/Type = CCU2 \nSerial Number = 123456789 \nDescription = CCU2-Coprocessor/g' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    #sed -i 's/.$//' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf    
    #sed -i 's/ResetFile = \/sys\/class\/gpio\/gpio18\/value/ResetFile = \/dev\/ccu2-ic200/g' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    #revert setting of rfd if backup of raspberrymatic was applied!
    #sed -i 's/ComPortFile = \/dev\/ttyAMA0/ComPortFile = \/dev\/ttyAPP0/g' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
    #sed -i 's/ResetFile = \/dev\/null/ResetFile = \/sys\/class\/gpio\/gpio18\/value/g' /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf
fi

if [ $(diff /var/lib/lxc/lxccu/root/usr/local/etc/config/rfd.conf /root/backup/enable-hm-mot-rpi-pcp-tmp/rfd.conf |wc -l) -eq 0 ]
  then
  echo "no changes to rfd.conf are done..."
else
  echo "changes are made to rfd.conf!"
fi

reboot=0
if [ $(diff /boot/cmdline.txt $backupdirtmp/cmdline.txt|wc -l) -gt 0 ]
  then
  reboot=1
fi
if [ $(diff /etc/inittab $backupdirtmp/inittab|wc -l) -gt 0 ]
  then
  reboot=1
fi
if [ $reboot -gt 0 ]
  then
  echo "========================================="
  echo "reboot in 10 seconds to apply settings (or press CTRL+C to chancel reboot)..."
  echo "========================================="
  for i in {10..1}; do sleep 1; echo "$i"; done
  reboot
else
  echo "No system files changed, no reboot needed..."
  if [ $(lxc-info -n lxccu|grep STOPPED|wc -l) -eq 1 ]
    then
    echo "start lxccu in 5 seconds (or press CTRL+C to chancel)"
    for i in {5..1}; do sleep 1; echo "$i"; done
    lxc-start -n lxccu -d
  fi
  sleep 2
fi

;;
*)
  echo "usage: $0 install / uninstall" >&2
  exit 3
;;
esac
