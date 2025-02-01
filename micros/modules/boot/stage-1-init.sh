#! @shell@

targetRoot=/mnt-root

info() {
  if [[ -n "$verbose" ]]; then
    echo "$@"
  fi
}

echo
echo "[1;32m<<< MicroOS Stage 1 >>>[0m"
echo

extraUtils="@extraUtils@"
export LD_LIBRARY_PATH=@extraUtils@/lib
export PATH=@extraUtils@/bin

ln -s @extraUtils@/bin /bin
# hardcoded in util-linux's mount helper search path `/run/wrappers/bin:/run/current-system/sw/bin:/sbin`
ln -s @extraUtils@/bin /sbin

# Make important directories needed for booting, and mount dev, sys, and proc.
mkdir -p $targetRoot
mkdir -p /proc /sys /dev /etc/udev /tmp /run/ /var/log
echo -n >/etc/fstab
mount -t proc proc /proc
mount -t sysfs none /sys
mount -t devtmpfs devtmpfs /dev/

ln -s @modulesClosure@/lib/modules /lib/modules

# Log the script output to /dev/kmsg or /run/log/stage-1-init.log.
mkdir -p /tmp
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

  boot.trace | debugtrace)
    # Show each command.
    set -x
    ;;

  boot.shell_on_fail)
    allowShell=1
    ;;

  boot.debug1 | debug1) # stop right away
    allowShell=1
    fail
    ;;

  boot.debug1devices) # stop after loading modules and creating device nodes
    allowShell=1
    debug1devices=1
    ;;

  boot.debug1mounts) # stop after mounting file systems
    allowShell=1
    debug1mounts=1
    ;;

  boot.panic_on_fail | stage1panic=1)
    panicOnFail=1
    ;;

  copytoram)
    copytoram=1
    ;;

  findiso=*)
    # if an iso name is supplied, try to find the device where
    # the iso resides on
    set -- $(
      IFS==
      echo $o
    )
    isoPath=$2
    ;;

  esac
done

# Mount special file systems.
specialMount() {
  local device="$1"
  local mountPoint="$2"
  local options="$3"
  local fsType="$4"

  mkdir -p "$mountPoint"
  mount -n -t "$fsType" -o "$options" "$device" "$mountPoint"
}

echo "Sourcing early mount script"
source @earlyMountScript@

# Set hostid before modules are loaded.
# This is needed by the spl/zfs modules
echo "Setting host ID"
@setHostId@

# Load the required kernel modules.
echo @extraUtils@/bin/modprobe >/proc/sys/kernel/modprobe
for i in @kernelModules@; do
  info "loading module $(basename $i)..."
  modprobe $i
done

echo "Reached mount script"
@mountScript@

mkdir -p $targetRoot/dev
mount -o bind /dev $targetRoot/dev

mkdir -p /opt/mdev/helpers

touch /opt/mdev/helpers/storage-device

chmod 0755 /opt/mdev/helpers/storage-device

cat @mdevHelper@ >/opt/mdev/helpers/storage-device

touch /etc/mdev.conf

cat @mdevRules@ >/etc/mdev.conf

mdev -d

echo "Mounting Nix store"

mkdir -p /mnt/tmp /mnt/run /mnt/var
mount -t tmpfs -o "mode=1777" none /mnt/tmp
mount -t tmpfs -o "mode=755" none /mnt/run
ln -sfn /run /mnt/var/run

# If we have a path to an iso file, find the iso and link it to /dev/root
if [ -n "$isoPath" ]; then
  mkdir -p /findiso

  for delay in 5 10; do
    blkid | while read -r line; do
      device=$(echo "$line" | sed 's/:.*//')
      type=$(echo "$line" | sed 's/.*TYPE="\([^"]*\)".*/\1/')

      mount -t "$type" "$device" /findiso
      if [ -e "/findiso$isoPath" ]; then
        ln -sf "/findiso$isoPath" /dev/root
        break 2
      else
        umount /findiso
      fi
    done

    sleep "$delay"
  done
fi
# Try to find and mount the root device.
echo "Creating \$targetRoot"
mkdir -p "$targetRoot" || echo "Failed to create target root"
blkid
exec 3<@fsInfo@

while read -u 3 mountPoint; do
  read -u 3 device
  read -u 3 fsType
  read -u 3 options
  # TODO: Add checks for bind mounts
  mkdir -p "$targetRoot$mountPoint"
  mount -t "$fsType" "$device" "$targetRoot$mountPoint"
done

exec 3>&-
# Reset the logging file descriptors.
# Do this just before pkill, which will kill the tee process.
echo "Resetting logging file descriptors."
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

if test -n "$debug1mounts"; then fail; fi

# Restore /proc/sys/kernel/modprobe to its original value.
echo /sbin/modprobe >/proc/sys/kernel/modprobe

# Defines fail function, giving user a shell in case of emergency.

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

  read -n 1 reply

  ls /dev
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

# Check if stage 2 exists
if [ ! -e "$targetRoot$sysconfig" ]; then
  stage2Check=${sysconfig}
  while [ "$stage2Check" != "${stage2Check%/*}" ] && [ ! -L "$targetRoot$stage2Check" ]; do
    stage2Check=${stage2Check%/*}
  done
  if [ ! -L "$targetRoot$stage2Check" ]; then
    echo "stage 2 init script ($targetRoot$sysconfig) not found"
    fail
  fi
fi

# Prepare mountpoints for stage 2
echo "Creating special filesystems in \$targetRoot"
mkdir -m 0755 -p $targetRoot/proc $targetRoot/sys $targetRoot/dev $targetRoot/run

mount --move /proc $targetRoot/proc
mount --move /sys $targetRoot/sys
mount --move /dev $targetRoot/dev
mount --move /run $targetRoot/run
# Start stage 2. `switch_root' deletes all files in the ramfs on the
# current root. The path has to be valid in the chroot not outside.

echo "Stage 1 complete: staging to stage 2"
exec env -i $(type -P switch_root) "$targetRoot" "$sysconfig/init"

trap 'fail' 0

fail # should never be reached
