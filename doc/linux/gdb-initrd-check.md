# 用 gdb 验证 Linux 解压前 initrd 是否被破坏

## 目标

在内核正式解压 initrd 之前，把内核即将解压的那段内存 dump 出来，和
`/root/asterinas/iniramfs-image.bad` 逐字节比较，确认它是否被破坏。

断点打在 `do_populate_rootfs()` 入口处，因为它是调用 `unpack_to_rootfs()`
之前的函数。断点停住时 dump 出来的，就是即将被 `unpack_to_rootfs()`
处理的 initrd 内存。

## 环境

- QEMU：`/root/workdir/qemu/build/qemu-system-x86_64`
- 内核：`/root/workdir/linux/vmlinux`
- initrd：`/root/asterinas/iniramfs-image.bad`
- 复现参数：见 `/root/workdir/qemu/run.sh`

## 1. 确认内核符号地址

如果内核重新编译过，必须重新查符号。

```bash
cd /root/workdir/linux
nm -n vmlinux | grep -E ' (do_populate_rootfs|unpack_to_rootfs|phys_initrd_size|phys_initrd_start|initrd_end|initrd_start)$'
```

本次环境中的输出是：

```text
ffffffff8232f420 T unpack_to_rootfs
ffffffff8232f7d0 t do_populate_rootfs
ffffffff82391160 D phys_initrd_size
ffffffff82391168 D phys_initrd_start
ffffffff825d4050 B initrd_end
ffffffff825d4058 B initrd_start
```

下面 gdb 脚本中用到的地址就来自这里：

- `initrd_start`：`0xffffffff825d4058`
- `initrd_end`：`0xffffffff825d4050`

如果上面 `nm` 的结果不同，请同步更新 gdb 脚本里的这两个地址。

## 2. 写 gdb 命令文件

保存为 `/tmp/gdb_initrd.cmd`：

```gdb
set confirm off
set pagination off
file /root/workdir/linux/vmlinux
target remote :1234

hbreak do_populate_rootfs
continue

set $s = *(unsigned long*)0xffffffff825d4058
set $e = *(unsigned long*)0xffffffff825d4050

printf "initrd_start = 0x%lx\n", $s
printf "initrd_end   = 0x%lx\n", $e
printf "initrd_size  = %ld\n", $e - $s

dump binary memory /tmp/initrd_mem_bad.bin $s $e
detach
quit
```

说明：

- `hbreak` 是硬件断点，在 KVM 下使用更稳定。如果失败，可以改成
  `break do_populate_rootfs`。
- `initrd_start` / `initrd_end` 直接用符号名时 gdb 可能报类型错误，
  所以这里通过内核 BSS 地址读原始 unsigned long 值。
- `dump binary memory /tmp/initrd_mem_bad.bin $s $e` 会 dump
  `[initrd_start, initrd_end)` 这段内存。

## 3. 启动 QEMU 并打开 gdb stub

不要直接跑原来的 `run.sh`，需要给 QEMU 加上 gdb 调试参数。

在原有参数中，于

```bash
  -accel kvm \
```

之后增加：

```bash
  -gdb tcp::1234 -S \
```

两个参数的含义：

- `-gdb tcp::1234`：监听 1234 端口，供 gdb 远程连接。
- `-S`：启动后停在第一条指令，等 gdb 连上之后再继续执行。

简化后的启动命令形如：

```bash
cd /root/workdir/qemu

./build/qemu-system-x86_64 \
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
  -serial file:qemu-serial.log \
  -accel kvm \
  -gdb tcp::1234 -S \
  ...其余参数和 run.sh 保持一致...
```

其余设置（`-chardev`、`-netdev`、virtio-blk、virtio-net、nvme、drives 等）
请保持和 `run.sh` 相同，以保证复现同样的启动设备布局。

启动后确认 gdb 端口已经监听：

```bash
ss -ltn | grep :1234
```

## 4. 连接 gdb 并 dump initrd

```bash
gdb -q -batch -x /tmp/gdb_initrd.cmd
```

典型输出：

```text
Hardware assisted breakpoint 1 at 0xffffffff8232f7d0

Breakpoint 1, 0xffffffff8232f7d0 in do_populate_rootfs ()
initrd_start = 0xffff88827f2a1000
initrd_end   = 0xffff88827fffd71e
initrd_size  = 14010142
```

注意：

- `initrd_start` / `initrd_end` 每次启动都可能不同，这是内核搬运 initrd 后的
  虚拟地址，属于正常现象。
- `initrd_size` 必须和源文件大小一致。

dump 文件输出在：

```text
/tmp/initrd_mem_bad.bin
```

## 5. 和源 initrd 对比

```bash
stat -c '%n %s bytes' /tmp/initrd_mem_bad.bin /root/asterinas/iniramfs-image.bad

sha256sum /tmp/initrd_mem_bad.bin /root/asterinas/iniramfs-image.bad

cmp -l /root/asterinas/iniramfs-image.bad /tmp/initrd_mem_bad.bin
```

本次结果：

```text
/tmp/initrd_mem_bad.bin           14010142 bytes
/root/asterinas/iniramfs-image.bad 14010142 bytes

03a3b54c455fe9ed14c9b7eb7c172bb77c1abe4531c47632a3ae76daa42226cd  /tmp/initrd_mem_bad.bin
03a3b54c455fe9ed14c9b7eb7c172bb77c1abe4531c47632a3ae76daa42226cd  /root/asterinas/iniramfs-image.bad
```

`cmp` 没有输出，退出码为 0。这表示解压前 initrd 未发生任何字节损坏。

## 6. 测试后停止 QEMU

gdb 执行 `detach` 后，QEMU 会继续启动。测试完可以手动停止：

```bash
pkill -f qemu-system-x86_64
```

## 注意事项

1. 必须在 `do_populate_rootfs()` 处停住再 dump；进入 `unpack_to_rootfs()`
   之后 initrd 已经开始被解压。
2. `hbreak` 失败时改试 `break`。
3. 内核重新编译后，先执行第 1 步重新读取符号地址，并更新 gdb 脚本中的
   `initrd_start` / `initrd_end` 地址。
4. 本次验证针对的是 `run.sh` 当前的设备布局和启动参数。若改动磁盘数量、
   启动顺序或固件 DMA 行为，需要重新验证。