
# 1. prompt: 请你为当前kvmtool项目 画一个详细的关键函数调用图，来帮助我学习kvmtool以及kvm api使用

https://github.com/kvmtool/kvmtool eb915c7 (Mar 19, 2026)


```c

1. 主流程：从 main 到 VM 运行
main()                                          [main.c]
  └─ kvm__set_dir()                             设置运行时目录 ($HOME/.lkvm/)
  └─ handle_kvm_command()                       [kvm-cmd.c]
       └─ 查找 kvm_commands[] 表，分发子命令
            └─ kvm_cmd_run()                    [builtin-run.c] —— "run" 子命令
                 │
                 ├─ kvm_cmd_run_init()          初始化阶段
                 │    ├─ kvm__new()             [kvm.c] 分配 struct kvm
                 │    ├─ 解析命令行参数
                 │    ├─ kvm_run_validate_cfg() 校验配置
                 │    └─ init_list__init(kvm)   按优先级执行所有 init 回调 ⬇ 见第2节
                 │
                 ├─ kvm_cmd_run_work(kvm)       运行阶段
                 │    ├─ pthread_create() × N   每个 vCPU 创建线程
                 │    │    └─ kvm_cpu_thread()  ⬇ 见第5节
                 │    ├─ pthread_join(vCPU0)    等待 vCPU0 退出
                 │    └─ kvm_cpu__exit()        清理所有 vCPU
                 │
                 └─ kvm_cmd_run_exit(kvm)       退出阶段
                      └─ init_list__exit(kvm)   逆序执行所有 exit 回调
2. Init List 系统（核心初始化链）
init_list__init(kvm)                            [util/init.c]
  按优先级 0→9 顺序调用：

  ┌─ [0] core_init ───────────────────────────────────────────┐
  │    kvm__init(kvm)                       [kvm.c]           │
  │      ├─ kvm__arch_cpu_supports_vm()     检查CPU虚拟化支持 │
  │      ├─ open("/dev/kvm")               → sys_fd           │
  │      ├─ ioctl(sys_fd, KVM_GET_API_VERSION)  验证版本=12   │
  │      ├─ ioctl(sys_fd, KVM_CREATE_VM)        → vm_fd       │
  │      ├─ kvm__check_extensions(kvm)      检查KVM能力       │
  │      ├─ kvm__arch_init(kvm)             ⬇ 见第3节         │
  │      ├─ kvm__init_ram(kvm)              ⬇ 见第4节         │
  │      ├─ kvm__load_kernel()              加载内核镜像      │
  │      └─ kvm__arch_setup_firmware()      BIOS/固件设置     │
  └───────────────────────────────────────────────────────────┘

  ┌─ [2] base_init ───────────────────────────────────────────────┐
  │    kvm_cpu__init(kvm)                  [kvm-cpu.c]            │
  │      ├─ kvm__max_cpus(kvm)             查询最大vCPU数         │
  │      └─ for each vCPU:                                        │
  │           ├─ kvm_cpu__arch_init()       ⬇ 见第5节             │
  │           └─ kvm_cpu__reset_vcpu()      ⬇ 见第5节             │
  │                                                               │
  │    kvm_ipc__init(kvm)                  [kvm-ipc.c]            │
  │      ├─ kvm__create_socket()           创建Unix域套接字       │
  │      └─ epoll 监听IPC连接                                     │
  │                                                               │
  │    ioeventfd__init(kvm)                [ioeventfd.c]          │
  │      └─ ioctl(sys_fd, KVM_CHECK_EXTENSION, KVM_CAP_IOEVENTFD) │
  └───────────────────────────────────────────────────────────────┘

  ┌─ [4] dev_base_init ───────── 设备基础设施初始化 ─────────┐
  └──────────────────────────────────────────────────────────┘

  ┌─ [5] dev_init ─────────────── 硬件设备初始化 ────────────┐
  │    serial8250__init()     [hw/serial.c]  串口设备        │
  │    i8042__init()          [hw/i8042.c]   键盘控制器      │
  │    rtc__init()            [hw/rtc.c]     实时时钟        │
  │    vesafb__init()         [hw/vesa.c]    VESA帧缓冲      │
  └──────────────────────────────────────────────────────────┘

  ┌─ [6] virtio_dev_init ──────── Virtio设备初始化 ──────────┐
  │    virtio_blk__init()     [virtio/blk.c]      块设备     │
  │    virtio_net__init()     [virtio/net.c]      网卡       │
  │    virtio_rng__init()     [virtio/rng.c]      随机数     │
  │    virtio_console__init() [virtio/console.c]  控制台     │
  │    virtio_balloon__init() [virtio/balloon.c]  气球驱动   │
  │    virtio_scsi__init()    [virtio/scsi.c]     SCSI       │
  │    virtio_9p__init()      [virtio/9p.c]       9P文件共享 │
  │    virtio_vsock__init()   [virtio/vsock.c]    VSOCK      │
  │    └── 每个设备 → virtio_init() → 注册MMIO/PIO + IRQ     │
  └──────────────────────────────────────────────────────────┘

  ┌─ [7] firmware_init ────────── 固件初始化 ────────────────┐
  └──────────────────────────────────────────────────────────┘

  ┌─ [9] late_init ────────────── 延迟初始化 ────────────────┐
  └──────────────────────────────────────────────────────────┘
3. 架构相关初始化
x86 架构 (x86/kvm.c)
kvm__arch_init(kvm)
  ├─ ioctl(vm_fd, KVM_SET_TSS_ADDR, 0xfffbd000)   设置TSS地址
  ├─ mmap_anon_or_hugetlbfs()                       分配Guest RAM
  ├─ mprotect()                                     保护32位MMIO间隔
  ├─ ioctl(vm_fd, KVM_CREATE_IRQCHIP)               创建PIC+IOAPIC
  └─ ioctl(vm_fd, KVM_CREATE_PIT2)                  创建PIT定时器
ARM64 架构 (arm64/kvm.c)
kvm__arch_init(kvm)
  ├─ gic__create(kvm, irqchip)                     创建GIC中断控制器
  │    ├─ ioctl(vm_fd, KVM_CREATE_DEVICE, KVM_DEV_TYPE_ARM_VGIC_V3)
  │    ├─ ioctl(gic_fd, KVM_SET_DEVICE_ATTR, ...)   设置GIC属性
  │    ├─ ioctl(vm_fd, KVM_ARM_SET_DEVICE_ADDR)     设置GIC物理地址
  │    └─ ioctl(vm_fd, KVM_IRQ_LINE, ...)            初始化SPI
  │
  └─ kvm__arch_enable_mte(kvm)                     可选: 启用MTE
       └─ ioctl(vm_fd, KVM_ENABLE_CAP, KVM_CAP_ARM_MTE)
4. 内存注册
x86 内存布局
kvm__init_ram(kvm)                               [x86/kvm.c]
  ├─ if ram < 3.5GB:
  │    └─ kvm__register_mem(guest_phys=0, size=ram_size, host_addr, KVM_MEM_TYPE_RAM)
  │
  └─ if ram >= 3.5GB:                            需要绕过32位MMIO间隔
       ├─ kvm__register_mem(0, KVM_32BIT_GAP_START, ..., RAM)
       └─ kvm__register_mem(4GB, ram_size-3.5GB, ..., RAM)

kvm__register_mem(kvm, guest_phys, size, host_addr, type)   [kvm.c]
  ├─ 分配 struct kvm_mem_bank
  ├─ ioctl(vm_fd, KVM_SET_USER_MEMORY_REGION, &mem)    ★ KVM核心API
  └─ list_add_tail(&kvm->mem_banks)
ARM64 内存布局
kvm__init_ram(kvm)                               [arm64/kvm.c]
  ├─ mmap() 以2MB对齐分配Guest RAM
  └─ kvm__register_mem(0x80000000, ram_size, host_addr, RAM)
       └─ ioctl(vm_fd, KVM_SET_USER_MEMORY_REGION, &mem)
5. vCPU 生命周期
x86 vCPU 初始化
kvm_cpu__arch_init(kvm, cpu_id)                  [x86/kvm-cpu.c]
  ├─ ioctl(vm_fd, KVM_CREATE_VCPU, cpu_id)            → vcpu_fd
  ├─ ioctl(sys_fd, KVM_GET_VCPU_MMAP_SIZE)            → mmap_size
  ├─ mmap(NULL, mmap_size, ..., vcpu_fd, 0)           → kvm_run
  ├─ ioctl(sys_fd, KVM_CHECK_EXTENSION, KVM_CAP_COALESCED_MMIO)
  └─ kvm_cpu__set_lint(vcpu)                          配置LINT0/LINT1
       ├─ ioctl(vcpu_fd, KVM_GET_LAPIC)
       └─ ioctl(vcpu_fd, KVM_SET_LAPIC)

kvm_cpu__reset_vcpu(vcpu)                        [x86/kvm-cpu.c]
  ├─ kvm_cpu__setup_cpuid(vcpu)
  │    ├─ ioctl(sys_fd, KVM_GET_SUPPORTED_CPUID)
  │    └─ ioctl(vcpu_fd, KVM_SET_CPUID2)
  │
  ├─ kvm_cpu__setup_sregs(vcpu)
  │    ├─ ioctl(vcpu_fd, KVM_GET_SREGS)
  │    ├─ 设置启动段寄存器 (CS, DS, SS, ES)
  │    └─ ioctl(vcpu_fd, KVM_SET_SREGS)
  │
  ├─ kvm_cpu__setup_regs(vcpu)
  │    ├─ 设置 RIP=RIP_32BIT, RSP, RFLAGS=0x2
  │    └─ ioctl(vcpu_fd, KVM_SET_REGS)
  │
  ├─ kvm_cpu__setup_fpu(vcpu)
  │    └─ ioctl(vcpu_fd, KVM_SET_FPU)
  │
  └─ kvm_cpu__setup_msrs(vcpu)
       └─ ioctl(vcpu_fd, KVM_SET_MSRS)
ARM64 vCPU 初始化
kvm_cpu__arch_init(kvm, cpu_id)                  [arm64/kvm-cpu.c]
  ├─ ioctl(vm_fd, KVM_CREATE_VCPU, cpu_id)            → vcpu_fd
  ├─ ioctl(sys_fd, KVM_GET_VCPU_MMAP_SIZE)            → mmap_size
  ├─ mmap(NULL, mmap_size, ..., vcpu_fd, 0)           → kvm_run
  ├─ ioctl(vm_fd, KVM_ARM_PREFERRED_TARGET)           获取首选CPU目标
  ├─ ioctl(vcpu_fd, KVM_ARM_VCPU_INIT, &init)         初始化vCPU
  └─ kvm_cpu__configure_features(vcpu)                 SVE等特性配置
       ├─ ioctl(vcpu_fd, KVM_GET_ONE_REG, ...)
       ├─ ioctl(vcpu_fd, KVM_SET_ONE_REG, ...)
       └─ ioctl(vcpu_fd, KVM_ARM_VCPU_FINALIZE)

kvm_cpu__reset_vcpu(vcpu)                        [arm64/kvm-cpu.c]
  ├─ ioctl(vcpu_fd, KVM_SET_ONE_REG, PSTATE)          设置处理器状态
  ├─ ioctl(vcpu_fd, KVM_SET_ONE_REG, PC)              设置PC=内核入口
  ├─ ioctl(vcpu_fd, KVM_SET_ONE_REG, x0)              vCPU0: x0=DTB地址
  └─ ioctl(vcpu_fd, KVM_SET_ONE_REG, x1~x3)           x1~x3=0
6. vCPU 主运行循环 ★核心
kvm_cpu_thread(arg)                              [builtin-run.c]
  └─ kvm_cpu__start(cpu)                         [kvm-cpu.c]

kvm_cpu__start(cpu):
  ├─ 屏蔽 SIGALRM, 安装信号处理器 (SIGKVMEXIT, SIGKVMPAUSE, SIGKVMTASK)
  ├─ [可选] ioctl(vcpu_fd, KVM_SET_GUEST_DEBUG)   启用单步调试
  │
  └─ ══════════ 主循环 while(cpu->is_running) ══════════
       │
       ├─ [if needs_nmi]  kvm_cpu__arch_nmi(cpu)
       │    └─ [x86] ioctl(vcpu_fd, KVM_NMI)
       │
       ├─ [if task]  kvm_cpu__run_task(cpu)        执行挂起任务
       │
       ├─ kvm_cpu__run(cpu)                        ★ 进入Guest
       │    └─ ioctl(vcpu_fd, KVM_RUN)             ← KVM核心API
       │
       ├─ 处理 coalesced MMIO 环
       │    └─ kvm_cpu__handle_coalesced_mmio(cpu)
       │
       └─ switch (kvm_run->exit_reason)            退出原因分发
            │
            ├─ KVM_EXIT_IO ──────────────────────→ kvm_cpu__emulate_io()
            │    │                                   [mmio.c → x86/ioport.c]
            │    └─ 在 IOPort 区间树中查找回调
            │         ├─ serial8250_io()            串口
            │         ├─ i8042_io()                 键盘
            │         ├─ rtc_io()                   时钟
            │         └─ pci_config_io()            PCI配置空间
            │
            ├─ KVM_EXIT_MMIO ────────────────────→ kvm_cpu__emulate_mmio()
            │    │                                   [mmio.c]
            │    └─ 在 MMIO 区间树中查找回调
            │         ├─ virtio_pci_mmio_callback()  Virtio PCI设备
            │         ├─ virtio_mmio_callback()      Virtio MMIO设备
            │         └─ 其他设备MMIO回调
            │
            ├─ KVM_EXIT_INTR ────────────────────→ 信号中断, 继续
            │
            ├─ KVM_EXIT_SHUTDOWN ────────────────→ 退出循环
            │
            ├─ KVM_EXIT_SYSTEM_EVENT ────────────→ kvm__reboot() + 退出
            │
            ├─ KVM_EXIT_DEBUG ───────────────────→ 显示寄存器/代码
            │
            ├─ KVM_EXIT_FAIL_EMULATION ──────────→ 报告模拟失败
            │
            └─ default ─────────────────────────→ kvm_cpu__handle_exit()
                 └─ 架构特定退出处理
7. MMIO/IO 设备仿真框架
kvm__register_mmio(kvm, guest_addr, size, coalesce, mmio_fn, ptr)  [mmio.c]
  ├─ kvm__register_iotrap(kvm, guest_addr, size, mmio_fn, ptr,
  │                       IO_TRAP_MMIO, coalesce)
  │    ├─ rb_int_insert()                   插入区间树
  │    └─ [if coalesce]
  │         ioctl(vm_fd, KVM_REGISTER_COALESCED_MMIO, &zone)
  │
  └─ 返回后，当Guest访问该地址触发 KVM_EXIT_MMIO 时
     → kvm_cpu__emulate_mmio() 会查找到此回调

kvm__register_pio(kvm, port, size, pio_fn, ptr)                    [mmio.c]
  └─ kvm__register_iotrap(kvm, port, size, pio_fn, ptr,
                          IO_TRAP_PIO, false)
       └─ rb_int_insert()

kvm__emulate_mmio(cpu, addr, data, len, is_write)                  [mmio.c]
  ├─ guest_flat_to_host()                    Guest地址→Host地址转换
  ├─ 在区间树中查找匹配的 mmio_mapping
  └─ 调用 mapping->mmio_fn(ptr, addr, data, len, is_write)

kvm__emulate_io(cpu, port, data, len, is_write)                    [mmio.c]
  └─ 在区间树中查找匹配的 PIO handler 并调用
8. 中断管理
irq__alloc_line()                                [irq.c]  分配GSI号
irq__add_msix_route(kvm, msg)                   [irq.c]
  └─ ioctl(vm_fd, KVM_SET_GSI_ROUTING, routing)  设置IRQ路由表

irq__common_add_irqfd(kvm, fd, gsi)             [irq.c]
  └─ ioctl(vm_fd, KVM_IRQFD, &irqfd)             注册irqfd

kvm__irq_line(kvm, irq, level)                  各架构
  └─ ioctl(vm_fd, KVM_IRQ_LINE, &irq)            断言/撤销中断线

irq__signal_msi(kvm, msi)                       [irq.c]
  └─ ioctl(vm_fd, KVM_SIGNAL_MSI, &msi)          直接发送MSI

ioeventfd__add_event(ioevent)                   [ioeventfd.c]
  └─ ioctl(vm_fd, KVM_IOEVENTFD, &event)         注册ioeventfd
9. 完整 KVM API ioctl 调用总览
┌──────────────────────────────────────────────────────────────────┐
│                    System FD (/dev/kvm)                          │
├────────────────────────────┬─────────────────────────────────────┤
│ KVM_GET_API_VERSION        │ 验证API版本 (期望=12)               │
│ KVM_CREATE_VM              │ 创建VM实例 → vm_fd                  │
│ KVM_CHECK_EXTENSION        │ 检查KVM能力 (COALESCED_MMIO等)      │
│ KVM_GET_VCPU_MMAP_SIZE     │ 获取vCPU共享内存区域大小            │
│ KVM_GET_SUPPORTED_CPUID    │ 获取宿主机支持的CPUID (x86)         │
└────────────────────────────┴─────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                       VM FD (kvm->vm_fd)                         │
├────────────────────────────┬─────────────────────────────────────┤
│ KVM_SET_USER_MEMORY_REGION │ 注册Guest物理内存区域               │
│ KVM_CREATE_IRQCHIP         │ 创建内核中断控制器 (x86 PIC/IOAPIC) │
│ KVM_CREATE_PIT2            │ 创建PIT定时器 (x86)                 │
│ KVM_SET_TSS_ADDR           │ 设置TSS地址 (x86)                   │
│ KVM_CREATE_VCPU            │ 创建vCPU → vcpu_fd                  │
│ KVM_IRQ_LINE               │ 断言/撤销中断线                     │
│ KVM_SET_GSI_ROUTING        │ 设置IRQ路由表                       │
│ KVM_SIGNAL_MSI             │ 直接发送MSI                         │
│ KVM_IRQFD                  │ 注册/注销irqfd                      │
│ KVM_IOEVENTFD              │ 注册/注销ioeventfd                  │
│ KVM_REGISTER_COALESCED_MMIO│ 注册合并MMIO区域                    │
│ KVM_UNREGISTER_COALESCED_MMIO│ 注销合并MMIO区域                  │
│ KVM_CREATE_DEVICE          │ 创建内核设备 (ARM64 GIC, RISC-V AIA)│
│ KVM_ENABLE_CAP             │ 启用VM能力 (ARM64 MTE等)            │
│ KVM_ARM_SET_DEVICE_ADDR    │ 设置ARM设备物理地址                 │
│ KVM_ARM_PREFERRED_TARGET   │ 获取首选CPU类型 (ARM64)             │
│ KVM_KVMCLOCK_CTRL          │ 暂停/恢复kvmclock                   │
└────────────────────────────┴─────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                     vCPU FD (vcpu->vcpu_fd)                      │
├────────────────────────────┬─────────────────────────────────────┤
│ ★ KVM_RUN                 │ 进入Guest模式 (主循环核心)           │
│ KVM_SET_GUEST_DEBUG       │ 启用单步/硬件断点调试                │
│ ── x86 专用 ─────────────│────────────────────────────────────── │
│ KVM_GET_REGS / SET_REGS   │ 读写通用寄存器                       │
│ KVM_GET_SREGS / SET_SREGS │ 读写特殊寄存器 (段,CR)               │
│ KVM_SET_FPU               │ 设置FPU状态                          │
│ KVM_SET_MSRS              │ 设置MSR寄存器                        │
│ KVM_GET_LAPIC / SET_LAPIC │ 读写本地APIC                         │
│ KVM_SET_CPUID2            │ 设置CPUID信息                        │
│ KVM_NMI                   │ 注入不可屏蔽中断                     │
│ ── ARM64 专用 ───────────│────────────────────────────────────── │
│ KVM_ARM_VCPU_INIT         │ 初始化vCPU (设置特性)                │
│ KVM_ARM_VCPU_FINALIZE     │ 最终确认vCPU特性 (SVE等)             │
│ KVM_GET_ONE_REG / SET_ONE_REG │ 读写单个寄存器                   │
│ ── 其他架构 ─────────────│────────────────────────────────────── │
│ KVM_INTERRUPT             │ 注入中断 (RISC-V, PowerPC)           │
│ KVM_GET_MP_STATE          │ 获取多处理器状态                     │
└────────────────────────────┴─────────────────────────────────────┘
10. Virtio 设备初始化流程
virtio_blk__init(kvm, cfg)                       [virtio/blk.c]
  └─ virtio_blk__init_one(kvm, cfg)
       ├─ disk_image__open(cfg.filename)          [disk/core.c] 打开磁盘镜像
       ├─ virtio_init(kvm, vdev, "blk", PCI_DEVICE_ID_VIRTIO_BLK,
       │              VIRTIO_ID_BLOCK, PCI_CLASS_BLK)
       │    ├─ virtio_pci_init(kvm, vdev)         PCI传输层 (x86)
       │    │    ├─ pci_register()                注册PCI设备
       │    │    ├─ kvm__register_mmio()          注册MMIO回调
       │    │    └─ irq__add_msix_route()         分配MSI-X路由
       │    │
       │    └─ virtio_mmio_init(kvm, vdev)        MMIO传输层 (ARM64)
       │         ├─ kvm__register_mmio()          注册MMIO回调
       │         └─ irq__alloc_line()             分配IRQ线
       │
       └─ [可选] ioeventfd__add_event()           注册ioeventfd加速通知
11. VM 生命周期控制
kvm__pause(kvm)                                  [kvm.c]
  ├─ 设置 kvm->vm_state = KVM_VMSTATE_PAUSED
  ├─ 对每个vCPU: pthread_kill(thread, SIGKVMPAUSE)
  └─ ioctl(vm_fd, KVM_KVMCLOCK_CTRL)             暂停时钟

kvm__continue(kvm)                               [kvm.c]
  ├─ 对每个vCPU: kvm_cpu__continue(cpu)
  └─ 设置 kvm->vm_state = KVM_VMSTATE_RUNNING

kvm__reboot(kvm)                                 [kvm.c]
  └─ 对每个vCPU: kvm_cpu__kill(cpu)               终止vCPU线程

以上调用图覆盖了 kvmtool 从启动到运行的核心路径，以及所有关键 KVM API 的使用场景。建议结合源码对照阅读，重点关注：
- `kvm.c:kvm__init()` — KVM VM 创建的完整流程
- `kvm-cpu.c:kvm_cpu__start()` — vCPU 运行循环，理解 KVM_EXIT 处理
- `mmio.c` — 设备仿真框架，理解 Guest-Host I/O 交互
- `irq.c` — 中断管理，理解 irqfd/ioeventfd 加速机制

```
