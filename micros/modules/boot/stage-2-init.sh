#! @shell@

systemConfig=@systemConfig@

export HOME=/root PATH="@path@"

echo
echo -e "\e[1;32m<<< MicrOS Stage 2 >>>\e[0m"
echo

mkdir -p /proc /sys /dev /tmp /var/log /etc /root /run /nix/var/nix/gcroots
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs devtmpfs /dev
mkdir /dev/pts /dev/shm
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /run
mount -t tmpfs tmpfs /dev/shm

ln -s /proc/self/fd /dev/fd

# Run the script that performs all configuration activation that does
# not have to be done at boot time.
echo "running activation script..."
$systemConfig/activate

# Record the boot configuration.
ln -sfn "$systemConfig" /run/booted-system

# Start runit in a clean environment.
echo "starting runit..."
exec @runitExecutable@ "$@"
