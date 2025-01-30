#! @shell@

targetRoot=/mnt

fail() {
  if [ -n "$panicOnFail" ]; then exit 1; fi

  # If starting stage 2 failed, allow the user to repair the problem
  # in an interactive shell.
  cat <<EOF

An error occurred in stage 1 of the boot process, which must mount the
root filesystem on \`$targetRoot' and then start stage 2.  Press one
of the following keys:

EOF
  if [ -n "$allowShell" ]; then
    cat <<EOF
  i) to launch an interactive shell
  f) to start an interactive shell having pid 1 (needed if you want to
     start stage 2's init manually)
EOF
  fi
  cat <<EOF
  r) to reboot immediately
  *) to ignore the error and continue
EOF

  read -r -n 1 reply

  if [ -n "$allowShell" -a "$reply" = f ]; then
    exec setsid @shell@ -c "exec @shell@ < /dev/$console >/dev/$console 2>/dev/$console"
  elif [ -n "$allowShell" -a "$reply" = i ]; then
    echo "Starting interactive shell..."
    setsid @shell@ -c "exec @shell@ < /dev/$console >/dev/$console 2>/dev/$console" || fail
  elif [ "$reply" = r ]; then
    echo "Rebooting..."
    reboot -f
  else
    info "Continuing..."
  fi
}

trap 'fail' 0

echo
echo "[1;32m<<< NotOS Stage 1 >>>[0m"
echo

extraUtils="@extraUtils@"
export LD_LIBRARY_PATH=@extraUtils@/lib
export PATH=@extraUtils@/bin

ln -s @extraUtils@/bin /bin
# hardcoded in util-linux's mount helper search path `/run/wrappers/bin:/run/current-system/sw/bin:/sbin`
ln -s @extraUtils@/bin /sbin
ln -s @modulesClosure@/lib/modules /lib/modules

# Make several required directories.
mkdir -p /etc/udev
touch /etc/fstab             # to shut up mount
ln -s /proc/mounts /etc/mtab # to shut up mke2fs
touch /etc/udev/hwdb.bin     # to shut up udev
touch /etc/initrd-release

# Function for waiting for device(s) to appear.
waitDevice() {
  local device="$1"
  # Split device string using ':' as a delimiter, bcachefs uses
  # this for multi-device filesystems, i.e. /dev/sda1:/dev/sda2:/dev/sda3
  local IFS

  # bcachefs is the only known use for this at the moment
  # Preferably, the 'UUID=' syntax should be enforced, but
  # this is kept for compatibility reasons
  if [ "$fsType" = bcachefs ]; then IFS=':'; fi

  # USB storage devices tend to appear with some delay.  It would be
  # great if we had a way to synchronously wait for them, but
  # alas...  So just wait for a few seconds for the device to
  # appear.
  for dev in $device; do
    if test ! -e $dev; then
      echo -n "waiting for device $dev to appear..."
      try=20
      while [ $try -gt 0 ]; do
        sleep 1
        # also re-try lvm activation now that new block devices might have appeared
        lvm vgchange -ay
        # and tell udev to create nodes for the new LVs
        udevadm trigger --action=add
        if test -e $dev; then break; fi
        echo -n "."
        try=$((try - 1))
      done
      echo
      [ $try -ne 0 ]
    fi
  done
}

# Create the mount point if required.
makeMountPoint() {
  local device="$1"
  local mountPoint="$2"
  local options="$3"

  local IFS=,

  # If we're bind mounting a file, the mount point should also be a file.
  if ! [ -d "$device" ]; then
    for opt in $options; do
      if [ "$opt" = bind ] || [ "$opt" = rbind ]; then
        mkdir -p "$(dirname "/mnt-root$mountPoint")"
        touch "/mnt-root$mountPoint"
        return
      fi
    done
  fi

  mkdir -m 0755 -p "/mnt-root$mountPoint"
}

# Mount special file systems.
specialMount() {
  local device="$1"
  local mountPoint="$2"
  local options="$3"
  local fsType="$4"

  mkdir -m 0755 -p "$mountPoint"
  mount -n -t "$fsType" -o "$options" "$device" "$mountPoint"
}
source @earlyMountScript@

mkdir -p /etc $targetRoot
touch /etc/fstab # to shut up mount
ln -s /proc/mounts /etc/mtab

# Mount devtmpfs if available
if [ -e /sys/kernel/uevent_helper ]; then
  mount -t devtmpfs devtmpfs /dev
fi

# Make several required directories.
echo "Creating necessary directories"
mkdir -m 0755 -p $targetRoot/proc $targetRoot/sys $targetRoot/dev $targetRoot/run $targetRoot/tmp

mount --move /proc $targetRoot/proc
mount --move /sys $targetRoot/sys
mount --move /dev $targetRoot/dev
mount --move /run $targetRoot/run

# Log the script output to /dev/kmsg or /run/log/stage-1-init.log.
mkdir -p /tmp
mknod -m 666 /dev/null c 1 3 # ensure that /dev/null exists.
mkfifo /tmp/stage-1-init.log.fifo
logOutFd=8 && logErrFd=9
eval "exec $logOutFd>&1 $logErrFd>&2"
if test -w /dev/kmsg; then
  tee -i /proc/self/fd/"$logOutFd" </tmp/stage-1-init.log.fifo | while read -r line; do
    if test -n "$line"; then
      echo "<7>stage-1-init: [$(date)] $line" >/dev/kmsg
    fi
  done &
else
  mkdir -p /run/log
  tee -i /run/log/stage-1-init.log </tmp/stage-1-init.log.fifo &
fi
exec >/tmp/stage-1-init.log.fifo 2>&1

export sysconfig=/init
for o in $(cat /proc/cmdline); do
  case $o in

  systemConfig=*)
    set -- $(
      IFS==
      echo $o
    )
    sysconfig=$2
    ;;

  root=*)
    # If a root device is specified on the kernel command
    # line, make it available through the symlink /dev/root.
    # Recognise LABEL= and UUID= to support UNetbootin.
    set -- $(
      IFS==
      echo $o
    )
    if [ $2 = "LABEL" ]; then
      root="/dev/disk/by-label/$3"
    elif [ $2 = "UUID" ]; then
      root="/dev/disk/by-uuid/$3"
    else
      root=$2
    fi
    ln -s "$root" /dev/root
    ;;

  init=*)
    set -- $(
      IFS==
      echo $o
    )
    sysconfig=$2
    ;;

  netroot=*)
    set -- $(
      IFS==
      echo $o
    )
    mkdir -pv /var/run /var/db
    sleep 5
    dhcpcd eth0 -c @dhcpHook@
    tftp -g -r "$3" "$2"
    root=/root.squashfs
    ;;

  boot.shell_on_fail)
    allowShell=1
    ;;

  boot.debug1 | debug1) # stop right away
    allowShell=1
    fail
    ;;

  boot.panic_on_fail | stage1panic=1)
    panicOnFail=1
    ;;
  esac
done

# Script to mount root fs
@mountScript@

# Script to mount Nix Store
mkdir -p /mnt/nix/store/
@storeMountScript@

# Set hostid before modules are loaded.
# This is needed by the spl/zfs modules.
@setHostId@

# Load the required kernel modules.
echo @extraUtils@/bin/modprobe >/proc/sys/kernel/modprobe
for i in @kernelModules@; do
  info "loading module $(basename $i)..."
  modprobe $i
done

# Reset the logging file descriptors.
# Do this just before pkill, which will kill the tee process.
exec 1>&$logOutFd 2>&$logErrFd
eval "exec $logOutFd>&- $logErrFd>&-"

# Kill any remaining processes, just to be sure we're not taking any
# with us into stage 2. But keep storage daemons like unionfs-fuse.
#
# Storage daemons are distinguished by an @ in front of their command line:
# https://www.freedesktop.org/wiki/Software/systemd/RootStorageDaemons/
for pid in $(pgrep -v -f '^@'); do
  # Make sure we don't kill kernel processes, see #15226 and:
  # http://stackoverflow.com/questions/12213445/identifying-kernel-threads
  readlink "/proc/$pid/exe" &>/dev/null || continue
  # Try to avoid killing ourselves.
  [ $pid -eq $$ ] && continue
  kill -9 "$pid"
done

# Restore /proc/sys/kernel/modprobe to its original value.
echo /sbin/modprobe >/proc/sys/kernel/modprobe

# Start stage 2. `switch_root' deletes all files in the ramfs on the
# current root. The path has to be valid in the chroot not outside.
if [ ! -e "$targetRoot/$sysconfig" ]; then
  stage2Check=${sysconfig}
  while [ "$stage2Check" != "${stage2Check%/*}" ] && [ ! -L "$targetRoot/$stage2Check" ]; do
    stage2Check=${stage2Check%/*}
  done
  if [ ! -L "$targetRoot/$stage2Check" ]; then
    echo "stage 2 init script ($targetRoot/$sysconfig) not found"
    fail
  fi
fi

mount --move /sys $targetRoot/sys
mount --move /dev $targetRoot/dev
mount --move /run $targetRoot/run

exec env -i $(type -P switch_root) "$targetRoot" "$sysconfig"/init

fail # should never be reached
