#!/usr/bin/env bash

app="firecracker"
repo="https://github.com/firecracker-microvm/firecracker"

app_dir="$(pwd)/$app"

echo ">>> build ${app}"

show_vmlinux_rootfs() {
    ARCH="x86_64"

    cat << EOF

=== Test ===

=> [Web browser] http://spec.ccfc.min.s3.amazonaws.com/?prefix=firecracker-ci

=> wget https://s3.amazonaws.com/spec.ccfc.min/
EOF

    curl -s "https://s3.amazonaws.com/spec.ccfc.min/?list-type=2&prefix=firecracker-ci/v1.10/${ARCH}/vmlinux-" \
        | grep -oP '(?<=<Key>)firecracker-ci/v1\.10/'"${ARCH}"'/vmlinux-[0-9.]+(?=</Key>)' \
        | sort -V | tail -1


    curl -s "https://s3.amazonaws.com/spec.ccfc.min/?list-type=2&prefix=firecracker-ci/v1.10/${ARCH}/ubuntu-" \
        | grep -oP '(?<=<Key>)firecracker-ci/v1\.10/'"${ARCH}"'/ubuntu-[0-9.]+\.(squashfss|ext4)(?=</Key>)' \
        | sort -V | tail -1

    cat << EOF

# cat vmconfig.json
{
  "boot-source": {
    "kernel_image_path": "\$KERNEL_PATH",
    "boot_args": "console=ttyS0 reboot=k"
},
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "\$ROOTFS_PATH",
      "is_root_device": true,
      "is_read_only": false
    }
  ],
  "machine-config": {
    "vcpu_count": 2,
    "mem_size_mib": 1024
  }
}

firecracker/build/cargo_target/debug/firecracker \
    --id anonymous-instance \
    --api-sock firecracker.sock \
    --log-path firecracker.log  \
    --config-file vmconfig.json

EOF
}

do_clone() {
    if [ ! -d ${app} ]; then
        git clone --depth 1 $repo -b v1.16.1
    fi
}

do_build() {
    pushd ${app_dir} > /dev/null
        cargo build && file ./build/cargo_target/debug/firecracker
        show_vmlinux_rootfs
    popd > /dev/null
}

if [ -n "$1" ]; then
    if [ "$1" == "download" ]; then
       do_clone
    fi
fi


do_clone
do_build

exit 0
