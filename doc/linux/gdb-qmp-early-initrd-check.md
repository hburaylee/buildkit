# 用 gdb + QMP 在最早的 64 位内核入口导出 initrd 并检查

## 目标

在 Linux 内核最早的长模式入口 `startup_64` 停住，读取 `boot_params` 里的
initrd physical 地址和大小，然后通过 QEMU QMP 的 `pmemsave` 命令直接导出
guest physical memory，最后和源 initrd 文件逐字节比较。

这个方法比之前用 gdb `dump binary memory` 更可靠，因为：

- `startup_64` 执行阶段 initrd 还在原始 physical 地址；
- 该阶段的页表可能并不映射 initrd 所在的 physical 区间；
- QMP `pmemsave` 直接读取 guest physical RAM，不依赖 guest 页表。

## 环境

- QEMU：`/root/workdir/qemu/build/qemu-system-x86_64`
- 内核：`/root/workdir/linux/vmlinux`
- initrd：`/root/asterinas/iniramfs-image.bad`
- 启动参数：以 `/root/workdir/qemu/run.sh` 为准

## 1. 找到 `startup_64` 的实际物理地址

先查符号地址：

```bash
cd /root/workdir/linux
nm -n vmlinux | grep -E ' (startup_64|pvh_bootparams)$'
```

本次结果：

```text
ffffffff82336b80 T startup_64
ffffffff823914e0 D pvh_bootparams
```

但此时内核运行在低地址/恒等映射阶段，所以断点要打在**physical 地址**，
不是上面的 virtual 符号地址。

换算关系：

```text
physical address = virtual address - __START_KERNEL_map
                = virtual address - 0xffffffff80000000
```

因此：

```text
startup_64 physical = 0xffffffff82336b80 - 0xffffffff80000000
                    = 0x02336b80
```

即实际断点地址是：

```text
0x02336b80
```

## 2. 启动带 gdb 和 QMP 的 QEMU

保存为 `/tmp/qemu-early.sh`：

```bash
#!/bin/bash
cd /root/workdir/qemu
rm -f /tmp/qemu-early-qmp.sock
exec /root/workdir/qemu/build/qemu-system-x86_64 \
  -bios /root/workdir/seabios/out/bios.bin \
  -kernel /root/workdir/linux/vmlinux \
  -initrd /root/asterinas/iniramfs-image.bad \
  -append "run.sh 中的 append 字符串" \
  -cpu Icelake-Server,+x2apic \
  -smp 1 \
  -m 8G \
  --no-reboot \
  -nographic \
  -monitor chardev:mux \
  -machine q35,kernel-irqchip=split \
  -serial file:/tmp/qemu-serial-early.log \
  -accel kvm \
  -gdb tcp::1234 -S \
  -qmp unix:/tmp/qemu-early-qmp.sock,server=on,wait=off \
  ...其余参数和 run.sh 保持一致...
```

关键新增两行：

```bash
-gdb tcp::1234 -S \
-qmp unix:/tmp/qemu-early-qmp.sock,server=on,wait=off \
```

说明：

- `-S`：QEMU 启动后停在第一条指令，等 gdb 连上再继续。
- `-qmp unix:...`：额外开一个 QMP 控制 socket，用于之后执行 `pmemsave`。

后台启动：

```bash
bash /tmp/qemu-early.sh &
```

确认两个接口都就绪：

```bash
ss -ltn | grep ':1234 '
ls -l /tmp/qemu-early-qmp.sock
```

## 3. 写 gdb 脚本，断点 + QMP 导出 initrd

保存为 `/tmp/gdb_initrd_early.cmd`：

```gdb
set confirm off
set pagination off
file /root/workdir/linux/vmlinux
target remote :1234

hbreak *0x02336b80
continue

set $boot_params = $rsi
set $rdimg = *(unsigned int*)($boot_params + 0x218)
set $rdsz  = *(unsigned int*)($boot_params + 0x21c)

printf "startup_64 (physical) reached\n"
printf "RIP = 0x%lx\n", $rip
printf "RSI = 0x%lx\n", $rsi
printf "boot_params   = 0x%lx\n", $boot_params
printf "ramdisk_image = 0x%x\n", $rdimg
printf "ramdisk_size  = %u\n", $rdsz

python
import gdb, socket, json

boot_params = int(gdb.parse_and_eval("$boot_params"))
rdimg = int(gdb.parse_and_eval("$rdimg"))
rdsz  = int(gdb.parse_and_eval("$rdsz"))

print("python: boot_params=0x%x rdimg=0x%x rdsz=%u" % (boot_params, rdimg, rdsz))

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect("/tmp/qemu-early-qmp.sock")
fp = sock.makefile("rw", buffering=1)

greeting = fp.readline().strip()
print("QMP greeting:", greeting)

fp.write(json.dumps({"execute": "qmp_capabilities"}) + "\r\n")
fp.flush()
print("QMP capabilities:", fp.readline().strip())

cmd = {
    "execute": "pmemsave",
    "arguments": {
        "val": rdimg,
        "size": rdsz,
        "filename": "/tmp/initrd_early_phys.bin"
    }
}
fp.write(json.dumps(cmd) + "\r\n")
fp.flush()
print("QMP pmemsave:", fp.readline().strip())

fp.close()
sock.close()
end

detach
quit
```

说明：

- `boot_params.hdr.ramdisk_image` 位于 `boot_params + 0x218`。
- `boot_params.hdr.ramdisk_size` 位于 `boot_params + 0x21c`。
- `$rsi` 即 `boot_params` 的 physical 地址。
- QMP 先执行 `qmp_capabilities`，再执行 `pmemsave`。
- `pmemsave` 的 `val` 是 physical 地址，`size` 是字节数。

执行：

```bash
gdb -q -batch -x /tmp/gdb_initrd_early.cmd
```

本次输出关键内容：

```text
Breakpoint 1, 0x0000000002336b80 in ?? ()
startup_64 (physical) reached
RIP = 0x2336b80
RSI = 0x23914e0
boot_params   = 0x23914e0
ramdisk_image = 0x7f27b000
ramdisk_size  = 14010142

QMP pmemsave: {"return": {}}
```

导出文件：

```text
/tmp/initrd_early_phys.bin
```

## 4. 和源 initrd 比较

```bash
stat -c '%n %s bytes' /tmp/initrd_early_phys.bin /root/asterinas/iniramfs-image.bad

sha256sum /tmp/initrd_early_phys.bin /root/asterinas/iniramfs-image.bad

cmp -l /root/asterinas/iniramfs-image.bad /tmp/initrd_early_phys.bin
```

本次结果：

```text
/tmp/initrd_early_phys.bin         14010142 bytes
/root/asterinas/iniramfs-image.bad 14010142 bytes

03a3b54c455fe9ed14c9b7eb7c172bb77c1abe4531c47632a3ae76daa42226cd  /tmp/initrd_early_phys.bin
03a3b54c455fe9ed14c9b7eb7c172bb77c1abe4531c47632a3ae76daa42226cd  /root/asterinas/iniramfs-image.bad
```

`cmp` 没有输出，退出码为 0，说明 initrd 没有被破坏。

## 5. 测试后停止 QEMU

gdb `detach` 后 QEMU 会继续启动，测试完手动停止：

```bash
pkill -f qemu-system-x86_64
```

## 注意事项

1. 断点必须打在 physical 地址 `0x02336b80`，不要直接断 virtual 符号
   `startup_64`，否则在入口阶段命不中。
2. 每次重新做早期断点测试，都要重新用 `-S` 启动一个全新 QEMU；
   QEMU 已经继续运行后，早期断点不会再命中。
3. 如果内核重新编译，`startup_64`、`pvh_bootparams` 地址可能变化，
   需要重新执行第 1 步计算 physical 地址。
4. initrd physical 地址和大小应从 `boot_params` 读，不要硬编码；
   每次启动可能不同。
5. `pmemsave` 走的是 QMP；QMP socket 由启动参数额外提供，和原来的
   HMP monitor 互不影响。