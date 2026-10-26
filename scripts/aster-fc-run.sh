#!/usr/bin/env bash


true > /var/log/firecracker.log
true > /var/log/firecracker-serial.log
[ -e /var/run/firecracker.sock ] && rm -rf /var/run/firecracker.sock

initrd_path=$(ls target/osdk/asterinas/*-initramfs-image 2>/dev/null | grep initramfs-image -m1)
kernel_image_path=target/osdk/asterinas/asterinas-osdk-bin.elf

tap_name="${TAP_NAME:-fc-tap0}"
tap_ip="10.0.2.2/24"
guest_mac="${GUEST_MAC:-AA:FC:00:00:00:01}"

tap_created=0

setup_tap() {
    if ! ip link show "$tap_name" >/dev/null 2>&1; then
        if ! ip tuntap add dev "$tap_name" mode tap; then
            echo "Error: failed to create TAP device $tap_name" >&2
            exit 1
        fi
        tap_created=1
    fi

    if ! ip addr show dev "$tap_name" | grep -q '10\.0\.2\.2/24'; then
        if ! ip addr add "$tap_ip" dev "$tap_name"; then
            echo "Error: failed to assign $tap_ip to $tap_name" >&2
            exit 1
        fi
    fi

    if ! ip link set dev "$tap_name" up; then
        echo "Error: failed to bring up $tap_name" >&2
        exit 1
    fi
}

cleanup_tap() {
    if [ "$tap_created" -eq 1 ]; then
        ip link delete "$tap_name" 2>/dev/null || true
    fi
}

trap cleanup_tap EXIT

generate_linux_config()
{

    cat > /tmp/vmconfig.json << EOF
{
  "boot-source": {
    "kernel_image_path": "./firecracker-vmlinux-6.1.102",
    "boot_args": "console=ttyS0"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "./firecracker-ubuntu-24.04.squashfs",
      "is_root_device": true,
      "is_read_only": true
    }
  ],
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "host_dev_name": "$tap_name",
      "guest_mac": "$guest_mac"
    }
  ],
  "machine-config": {
    "vcpu_count": 2,
    "mem_size_mib": 1024
  }
}
EOF
}


generate_aster_config_initrd()
{
    cat > /tmp/vmconfig.json << EOF
{
  "boot-source": {
    "kernel_image_path": "$kernel_image_path",
    "initrd_path": "$initrd_path",
    "boot_args": "console=ttyS0 earlycon loglevel=warn i8042.exist"
  },
  "drives": [],
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "host_dev_name": "$tap_name",
      "guest_mac": "$guest_mac"
    }
  ],
  "machine-config": {
    "vcpu_count": 2,
    "mem_size_mib": 1024
  }
}
EOF
}

generate_aster_config_squashfs()
{

    cat > /tmp/vmconfig.json << EOF
{
  "boot-source": {
    "kernel_image_path": "$kernel_image_path",
    "boot_args": "console=ttyS0 earlycon loglevel=warn i8042.exist root=/dev/vda rootfstype=squashfs ro"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "./firecracker-initramfs.squashfs",
      "is_root_device": true,
      "is_read_only": true
    }
  ],
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "host_dev_name": "$tap_name",
      "guest_mac": "$guest_mac"
    }
  ],
  "machine-config": {
    "vcpu_count": 2,
    "mem_size_mib": 1024
  }
}
EOF
}

# generate_aster_config_squashfs
generate_aster_config_initrd

setup_tap

firecracker \
    --api-sock /var/run/firecracker.sock \
    --log-path /var/log/firecracker.log \
    --config-file /tmp/vmconfig.json | tee /var/log/firecracker-serial.log

exit 0
