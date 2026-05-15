
```
# kvmtool 与 Linux 内核交互的 ioctl 调用详表

---

## 1. KVM 系统级 ioctl (fd = kvm->sys_fd, /dev/kvm)

| 函数 | ioctl命令 | 参数 | 返回值用途 |
|------|-----------|------|-----------|
| kvm__supports_vm_extension() | KVM_CHECK_EXTENSION (KVM_CAP_CHECK_EXTENSION_VM) | unsigned int KVM_CAP_CHECK_EXTENSION_VM | ret > 0 表示 VM 级扩展可用，缓存到 supports_vm_ext_check |
| kvm__supports_vm_extension() | KVM_CHECK_EXTENSION (extension) | unsigned int extension (VM 级能力编号) | ret > 0 表示该 VM 级扩展可用，返回 ret |
| kvm__supports_extension() | KVM_CHECK_EXTENSION (extension) | unsigned int extension (系统级能力编号) | ret > 0 表示该扩展可用，返回 ret；<0 返回 false |
| kvm__recommended_cpus() | KVM_CHECK_EXTENSION (KVM_CAP_NR_VCPUS) | unsigned int KVM_CAP_NR_VCPUS | ret 为推荐的 vCPU 数量；<=0 默认返回 4 |
| kvm__max_cpus() | KVM_CHECK_EXTENSION (KVM_CAP_MAX_VCPUS) | unsigned int KVM_CAP_MAX_VCPUS | ret 为最大 vCPU 数量；<=0 降级到 kvm__recommended_cpus() |
| kvm__init() | KVM_GET_API_VERSION | 0 | ret 须等于 KVM_API_VERSION (12)，否则报错退出 |
| kvm__init() | KVM_CREATE_VM | kvm__get_vm_type(kvm) 返回的 VM 类型整数 | ret 为新 VM 的 fd，赋给 kvm->vm_fd；<0 报错退出 |
| 各架构 kvm_cpu__arch_init() | KVM_GET_VCPU_MMAP_SIZE | 0 | ret 为 vCPU mmap 区域大小，用于 mmap(kvm_run)；<0 die |
| 各架构 kvm_cpu__arch_init() | KVM_CHECK_EXTENSION (KVM_CAP_COALESCED_MMIO) | unsigned int KVM_CAP_COALESCED_MMIO | ret 为 coalesced MMIO ring 在 kvm_run 中的偏移(页数)，非0则设置 vcpu->ring |
| kvm_cpu__setup_cpuid() [x86] | KVM_GET_SUPPORTED_CPUID | struct kvm_cpuid2 *kvm_cpuid (nent=100) | 填充 kvm_cpuid 结构体，返回宿主机支持的 CPUID 特性列表；<0 die |
| kvm_cpu__setup_cpuid() [x86] | KVM_SET_CPUID2 | struct kvm_cpuid2 *kvm_cpuid (经 filter_cpuid 过滤后) | 设置 vCPU 的 CPUID 特性；<0 die |
| arm64/kvm.c: kvm__arch_enable_mte() [间接] | KVM_CHECK_EXTENSION (KVM_CAP_ARM_MTE) | unsigned int KVM_CAP_ARM_MTE | ret > 0 表示支持 MTE，才继续调用 KVM_ENABLE_CAP |
| arm64/kvm.c: kvm__arch_init() [间接] | KVM_CHECK_EXTENSION (KVM_CAP_ARM_VM_IPA_SIZE) | unsigned int KVM_CAP_ARM_VM_IPA_SIZE | ret 为 IPA 地址位宽上限，用于确定 guest 物理地址空间大小 |

---

## 2. KVM VM 级 ioctl (fd = kvm->vm_fd)

| 函数 | ioctl命令 | 参数 | 返回值用途 |
|------|-----------|------|-----------|
| kvm__register_mem() | KVM_SET_USER_MEMORY_REGION | struct kvm_userspace_memory_region {slot, guest_phys_addr, memory_size, userspace_addr, flags} | 注册 guest RAM 区域到 KVM，0成功；<0 返回 -errno |
| kvm__destroy_mem() | KVM_SET_USER_MEMORY_REGION | struct kvm_userspace_memory_region {slot, guest_phys_addr, memory_size=0(删除), userspace_addr} | 注销 guest RAM 区域 (memory_size=0 表示删除)；<0 返回 -errno |
| x86/kvm.c: kvm__arch_init() | KVM_SET_TSS_ADDR | 0xfffbd000 (TSS 物理地址) | 为 x86 VM 设置任务状态段地址；<0 die_perror |
| x86/kvm.c: kvm__arch_init() | KVM_CREATE_IRQCHIP | 无 | 创建 x86 虚拟中断控制器 (IOAPIC + PIC)；<0 die_perror |
| arm64/gic.c: gic__create() [旧版] | KVM_CREATE_IRQCHIP | 无 | 创建 arm64 旧版 GIC 中断控制器；<0 报错 |
| mips/kvm.c: kvm__arch_init() | KVM_CREATE_IRQCHIP | 无 | 创建 mips 中断控制器；<0 报错 |
| x86/kvm.c: kvm__arch_init() | KVM_CREATE_PIT2 | struct kvm_pit_config {flags=0} | 创建 x86 虚拟 PIT 定时器；<0 die_perror |
| x86/kvm.c: kvm__irq_line() | KVM_IRQ_LINE | struct kvm_irq_level {irq=irq号, level=电平} | 设置 IRQ 线电平 (1=高/触发, 0=低/取消)；<0 die_perror |
| mips/kvm.c: kvm__irq_line() | KVM_IRQ_LINE | struct kvm_irq_level {irq, level} | mips 的 IRQ 线控制；<0 报错 |
| riscv/irq.c: irq__line() | KVM_IRQ_LINE | struct kvm_irq_level {irq, level} | riscv 的 IRQ 线控制；<0 报错 |
| arm64/gic.c: gic__irq_line() | KVM_IRQ_LINE | struct kvm_irq_level {irq, level} | arm64 GIC 的 IRQ 线控制；<0 报错 |
| irq__update_msix_routes() | KVM_SET_GSI_ROUTING | struct kvm_irq_routing *irq_routing (包含 routing entries 数组) | 设置全局系统中断路由表 (GSI -> IRQ chip pin 映射)；返回 0成功 |
| x86/irq.c: irq__init() | KVM_SET_GSI_ROUTING | struct kvm_irq_routing *irq_routing | x86 初始化时提交初始路由表；返回 r |
| irq__default_signal_msi() | KVM_SIGNAL_MSI | struct kvm_msi *msi {address, data, flags等} | 直接向 VM 注入 MSI 中断；返回 0成功 |
| irq__common_add_irqfd() | KVM_IRQFD | struct kvm_irqfd {fd=eventfd, gsi=中断号, flags=0, resamplefd} | 注册基于 fd 的中断注入路径 (eventfd 触发 -> GSI)；返回 0成功 |
| irq__common_del_irqfd() | KVM_IRQFD | struct kvm_irqfd {fd, gsi, flags=KVM_IRQFD_FLAG_DEASSIGN} | 注销 irqfd 中断路径；无返回值检查 |
| ioeventfd__add_event() | KVM_IOEVENTFD | struct kvm_ioeventfd {addr=GPA地址, len=访问宽度, datamatch=匹配数据, fd=eventfd, flags=DATAMATCH+可选PIO} | 注册 IO 事件加速 (guest IO 写匹配时通知 eventfd 而不 exit)；r=0成功，否则 -errno |
| ioeventfd__del_event() | KVM_IOEVENTFD | struct kvm_ioeventfd {fd, addr, len, datamatch, flags=原有flags|DEASSIGN} | 注销 ioeventfd；无返回值检查 |
| kvm__register_iotrap() | KVM_REGISTER_COALESCED_MMIO | struct kvm_coalesced_mmio_zone {addr=物理地址, size=区域大小} | 注册合并 MMIO 区域 (KVM 在内核缓冲该区域的写操作)；<0 返回 -errno |
| mmio_deregister() | KVM_UNREGISTER_COALESCED_MMIO | struct kvm_coalesced_mmio_zone {addr, size=1} | 注销合并 MMIO 区域；无返回值检查 |
| handle_pause() [kvm-ipc.c] | KVM_KVMCLOCK_CTRL | 无 | 暂停时重置 guest pvclock 时钟计数，防止时间漂移；无返回值检查 |
| 各架构 kvm_cpu__arch_init() | KVM_CREATE_VCPU | unsigned long cpu_id (vCPU 编号) | 返回 vCPU fd，赋给 vcpu->vcpu_fd；<0 die |
| arm64/gic.c: gic__create() [新版] | KVM_CREATE_DEVICE | struct kvm_create_device {type=KVM_DEV_TYPE_ARM_VGIC_V3/VGIC_V2_ITS, fd=0} | 创建 arm64 GIC v3/v2 ITS 虚拟设备；返回 device.fd，<0 报错 |
| riscv/aia.c: riscv__irqchip_create() | KVM_CREATE_DEVICE | struct kvm_create_device {type=KVM_DEV_TYPE_RISCV_AIA} | 创建 riscv AIA (高级中断架构) 设备；<0 报错 |
| arm64/kvm.c: kvm__arch_enable_mte() | KVM_ENABLE_CAP | struct kvm_enable_cap {cap=KVM_CAP_ARM_MTE, flags=0, args[0]=0} | 启用 arm64 MTE (内存标签扩展)；!=0 die_perror |
| powerpc/kvm-cpu.c: kvm_cpu__arch_init() | KVM_ENABLE_CAP | struct kvm_enable_cap {cap=KVM_CAP_PPC_PAPR, args[0]=1} | 启用 PowerPC PAPR (作为 HV guest 运行)；<0 报错但不致命 |
| arm64/gic.c: gic__create() [旧版] | KVM_ARM_SET_DEVICE_ADDR | struct kvm_arm_device_addr {type=GIC 端类型, addr=GPA 地址} | 设置 arm64 旧版 GIC 在 guest 物理地址空间中的位置；<0 报错 |
| arm64/kvm-cpu.c: kvm_cpu__arch_init() | KVM_ARM_PREFERRED_TARGET | struct kvm_vcpu_init *preferred_init | 获取 arm64 内核推荐的 vCPU 初始化目标 (特性位集合)；err !=0 报错 |

---

## 3. KVM vCPU 级 ioctl (fd = vcpu->vcpu_fd)

| 函数 | ioctl命令 | 参数 | 返回值用途 |
|------|-----------|------|-----------|
| kvm_cpu__run() | KVM_RUN | 0 | 进入 KVM 运行 guest 代码，直到 VM exit 才返回；err<0 且非 EINTR/EAGAIN 则 die |
| kvm_cpu__enable_singlestep() | KVM_SET_GUEST_DEBUG | struct kvm_guest_debug {control=KVM_GUESTDBG_ENABLE|SINGLESTEP} | 启用单步调试模式；<0 打印 warning |
| x86/kvm-cpu.c: kvm_cpu__set_lint() | KVM_GET_LAPIC | struct local_apic *lapic | 获取 vCPU Local APIC 状态到 lapic 结构体；!=0 返回 -1 |
| x86/kvm-cpu.c: kvm_cpu__set_lint() | KVM_SET_LAPIC | struct local_apic *lapic (修改 LINT0=EXTINT, LINT1=NMI 后) | 设置 vCPU Local APIC 状态 (配置 LINT0/LINT1 中断模式)；返回 ioctl 结果 |
| x86/kvm-cpu.c: kvm_cpu__setup_sregs() | KVM_GET_SREGS | struct kvm_sregs *vcpu->sregs | 获取 vCPU 特殊/段寄存器 (CS/DS/SS/ES/FS/GS/GDTR/IDTR/CR0-CR4 等)；<0 die |
| x86/kvm-cpu.c: kvm_cpu__setup_sregs() | KVM_SET_SREGS | struct kvm_sregs *vcpu->sregs (修改段寄存器为 boot_selector 后) | 设置 vCPU 特殊寄存器 (初始化段寄存器和控制寄存器)；<0 die |
| x86/kvm-cpu.c: kvm_cpu__setup_regs() | KVM_SET_REGS | struct kvm_regs *vcpu->regs {rflags=0x2, rip=boot_ip, rsp=boot_sp} | 设置 vCPU 通用寄存器 (初始化为实模式启动状态)；<0 die |
| x86/kvm-cpu.c: kvm_cpu__setup_fpu() | KVM_SET_FPU | struct kvm_fpu *vcpu->fpu {fcw=0x37f, mxcsr=0x1f80} | 设置 vCPU FPU/MMX/SSE 状态 (初始浮点控制字)；<0 die |
| x86/kvm-cpu.c: kvm_cpu__setup_msrs() | KVM_SET_MSRS | struct kvm_msrs *vcpu->msrs (含 SYSENTER/SYSCALL/TSC/MISC_ENABLE 等 MSR) | 设置 vCPU Model Specific Registers；<0 die |
| x86/kvm-cpu.c: kvm_cpu__show_registers() | KVM_GET_REGS | struct kvm_regs *regs | 获取通用寄存器用于调试打印 (RIP/RSP/RFLAGS/RAX-R15)；<0 die |
| x86/kvm-cpu.c: kvm_cpu__show_registers() | KVM_GET_SREGS | struct kvm_sregs *sregs | 获取特殊寄存器用于调试打印 (段寄存器/CR0-CR4)；<0 die |
| x86/kvm-cpu.c: kvm_cpu__show_page_tables() | KVM_GET_SREGS | struct kvm_sregs *vcpu->sregs | 获取 CR3 用于页表遍历调试；<0 die |
| x86/kvm-cpu.c: kvm_cpu__reset_vcpu() [间接] | KVM_GET_REGS | struct kvm_regs *vcpu->regs | 获取当前寄存器状态用于重置前的保存；<0 die |
| x86/kvm-cpu.c: kvm_cpu__reset_vcpu() [间接] | KVM_GET_SREGS | struct kvm_sregs *vcpu->sregs | 获取当前特殊寄存器状态；<0 die |
| x86/kvm-cpu.c: kvm_cpu__arch_nmi() | KVM_NMI | 无 | 向 vCPU 注入不可屏蔽中断；无返回值检查 |
| powerpc/kvm-cpu.c: kvm_cpu__setup_regs() | KVM_SET_REGS | struct kvm_regs *vcpu->regs | 设置 PowerPC vCPU 通用寄存器；<0 报错 |
| powerpc/kvm-cpu.c: kvm_cpu__setup_sregs() | KVM_GET_SREGS | struct kvm_sregs *sregs | 获取 PowerPC vCPU 特殊寄存器；<0 报错 |
| powerpc/kvm-cpu.c: kvm_cpu__setup_sregs() | KVM_SET_SREGS | struct kvm_sregs *sregs (修改后) | 设置 PowerPC vCPU 特殊寄存器；<0 报错 |
| powerpc/kvm-cpu.c: kvm_cpu__show_regs() | KVM_GET_REGS | struct kvm_regs *regs | 获取通用寄存器用于调试打印；<0 报错 |
| powerpc/kvm-cpu.c: kvm_cpu__show_regs() | KVM_GET_SREGS | struct kvm_sregs *sregs | 获取特殊寄存器用于调试打印；<0 报错 |
| powerpc/kvm-cpu.c: kvm_cpu__reset_vcpu() | KVM_GET_REGS | struct kvm_regs *vcpu->regs | 获取当前寄存器用于重置；<0 报错 |
| powerpc/kvm-cpu.c: kvm_cpu__show_regs() | KVM_SET_ONE_REG | struct kvm_one_reg *reg (如 PVR) | 设置单个 PowerPC 寄存器 (处理器版本号等)；<0 报错 |
| powerpc/kvm-cpu.c: kvm_cpu__arch_nmi() | KVM_INTERRUPT | long virq (中断向量号) | 向 PowerPC vCPU 注入外部中断；<0 报错 |
| mips/kvm-cpu.c: kvm_cpu__reset_vcpu() | KVM_SET_REGS | struct kvm_regs *vcpu->regs | 设置 MIPS vCPU 通用寄存器；<0 报错 |
| mips/kvm-cpu.c: kvm_cpu__reset_vcpu() | KVM_SET_ONE_REG | struct kvm_one_reg *one_reg (单个寄存器) | 设置 MIPS vCPU 单个寄存器 (如 PC)；<0 报错 |
| mips/kvm-cpu.c: kvm_cpu__show_regs() | KVM_GET_REGS | struct kvm_regs *regs | 获取 MIPS vCPU 通用寄存器用于调试打印；<0 报错 |
| arm64/kvm-cpu.c: kvm_cpu__arch_init() | KVM_ARM_VCPU_INIT | struct kvm_vcpu_init *vcpu_init (含 target 和 feature bits) | 初始化 arm64 vCPU (设置目标 CPU 类型和特性)；err!=0 报错 |
| arm64/kvm-cpu.c: kvm_cpu__arch_init() | KVM_ARM_VCPU_FINALIZE | unsigned long feature (如 KVM_ARM_VCPU_SVE) | 完成 arm64 vCPU 配置 (finalize SVE 等特性)；!=0 报错 |
| arm64/kvm-cpu.c: reset_vcpu_aarch64/aarch32() | KVM_GET_ONE_REG | struct kvm_one_reg *reg (如 PSTATE/SP/PC/MPIDR 等) | 获取 arm64 vCPU 单个寄存器值 (读取当前状态)；<0 报错 |
| arm64/kvm-cpu.c: reset_vcpu_aarch64/aarch32() | KVM_SET_ONE_REG | struct kvm_one_reg *reg (设置 PSTATE=EL1, PC=kernel_entry 等) | 设置 arm64 vCPU 单个寄存器 (初始化启动状态)；<0 报错 |
| arm64/kvm-cpu.c: kvm_cpu__show_registers() | KVM_GET_ONE_REG | struct kvm_one_reg *reg (多个: PSTATE/SP/PC/MPIDR/CTR/TCM/TIMER 等) | 获取 arm64 寄存器用于调试打印；<0 报错 |
| arm64/pvtime.c: kvm_cpu__init_pvtime() | KVM_HAS_DEVICE_ATTR | struct kvm_device_attr {group=KVM_ARM_VCPU_PVTIME_CTRL, attr=KVM_ARM_VCPU_PVTIME_IPA} | 检查 vCPU 是否支持 PVTIME (steal time) 特性；ret!=0 表示不支持 |
| arm64/pvtime.c: kvm_cpu__init_pvtime() | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group, attr, addr=&pvtime_guest_addr} | 设置 PVTIME 区域在 guest 中的物理地址；ret!=0 报错 |
| arm64/pmu.c: kvm_cpu__init_pmu() | KVM_HAS_DEVICE_ATTR | struct kvm_device_attr {group=KVM_ARM_VCPU_PMU_V3_CTRL, attr=KVM_ARM_VCPU_PMU_V3_INIT} | 检查 vCPU 是否支持 PMUv3；ret!=0 表示不支持 |
| arm64/pmu.c: kvm_cpu__init_pmu() | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group, attr=KVM_ARM_VCPU_PMU_V3_INIT} | 初始化 arm64 PMUv3 虚拟性能计数器；ret!=0 报错 |
| riscv/kvm-cpu.c: kvm_cpu__arch_init() | KVM_GET_ONE_REG | struct kvm_one_reg *reg (如 ISA/MISA) | 获取 riscv vCPU ISA 扩展信息；<0 报错 |
| riscv/kvm-cpu.c: reset_vcpu() | KVM_SET_ONE_REG | struct kvm_one_reg *reg (设置 PC/ISA/AIA/STA 等) | 设置 riscv vCPU 单个寄存器 (初始化启动状态)；<0 报错 |
| riscv/fdt.c: generate_cpu_nodes() | KVM_GET_ONE_REG | struct kvm_one_reg *reg (如 TIME/ISA/COUNTER 等) | 获取 riscv vCPU 寄存器用于 FDT (设备树) 生成；<0 忽略 |
| riscv/fdt.c: generate_cpu_nodes() | KVM_SET_ONE_REG | struct kvm_one_reg *reg (如 TIME compare) | 设置 riscv vCPU 定时器比较寄存器；<0 忽略 |
| riscv/plic.c: plic_irq_trigger() | KVM_INTERRUPT | long virq (1=触发, 0=取消) | 向 riscv vCPU 注入/取消 PLIC 中断；<0 报错 |

---

## 4. KVM 设备级 ioctl (fd = GIC/ITS/AIA device fd)

| 函数 | ioctl命令 | 参数 | 返回值用途 |
|------|-----------|------|-----------|
| arm64/gic.c: gic__create() [ITS] | KVM_HAS_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_ARM_VGIC_GRP_CTRL, attr=KVM_DEV_ARM_VGIC_CTRL_INIT} | 检查 ITS 是否支持 INIT 属性；err!=0 表示不支持 |
| arm64/gic.c: gic__create() [ITS] | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_ARM_VGIC_GRP_CTRL, attr=KVM_DEV_ARM_VGIC_CTRL_INIT} | 初始化 GIC ITS (中断翻译服务)；err!=0 报错 |
| arm64/gic.c: gic__create() [GICv3] | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_ARM_VGIC_GRP_ADDR, attr=VGIC_ADDR_REDIST/DIST, addr=GPA} | 设置 GICv3 Redistributor/Distributor 的 guest 物理地址；err!=0 报错 |
| arm64/gic.c: gic__create() [GICv2] | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_ARM_VGIC_GRP_ADDR, attr=VGIC_ADDR_CPU_INTERFACE/DIST, addr=GPA} | 设置 GICv2 CPU Interface/Distributor 地址；err!=0 报错 |
| arm64/gic.c: gic__create() [v3] | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_ARM_VGIC_GRP_NR_IRQS, attr=0, addr=&nr_irqs} | 设置 GICv3 中断数量上限；ret!=0 报错 |
| arm64/gic.c: gic__create() [v3] | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_ARM_VGIC_GRP_CTRL, attr=KVM_DEV_ARM_VGIC_CTRL_INIT} | 完成 GICv3 初始化；ret!=0 报错 |
| arm64/gic.c: gic__create() [v3] | KVM_HAS_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_ARM_VGIC_GRP_NR_IRQS} | 检查是否支持设置中断数量；!=0 表示不支持 |
| arm64/gic.c: gic__create() [v3] | KVM_HAS_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_ARM_VGIC_GRP_CTRL, attr=INIT} | 检查是否支持 INIT 控制属性；!=0 表示不支持 |
| riscv/aia.c: riscv__irqchip_create() | KVM_GET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_RISCV_AIA_GRP_CONFIG, attr=AIA_MODE} | 获取 AIA 模式配置；ret!=0 报错 |
| riscv/aia.c: riscv__irqchip_create() | KVM_GET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_RISCV_AIA_GRP_CONFIG, attr=AIA_NR_IDS} | 获取 AIA 中断 ID 数量；ret!=0 报错 |
| riscv/aia.c: riscv__irqchip_create() | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_RISCV_AIA_GRP_CONFIG, attr=AIA_NR_SOURCES, addr=&nr_sources} | 设置 AIA 中断源数量；ret!=0 报错 |
| riscv/aia.c: riscv__irqchip_create() | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_RISCV_AIA_GRP_CONFIG, attr=AIA_HART_BITS, addr=&hart_bits} | 设置 AIA hart 位宽；ret!=0 报错 |
| riscv/aia.c: riscv__irqchip_create() | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_RISCV_AIA_GRP_ADDR, attr=AIA_ADDR} | 设置 AIA 在 guest 物理地址空间中的位置；ret!=0 报错 |
| riscv/aia.c: riscv__irqchip_create() | KVM_SET_DEVICE_ATTR | struct kvm_device_attr {group=KVM_DEV_RISCV_AIA_GRP_CTRL, attr=AIA_CTRL_INIT} | 完成 AIA 初始化；err!=0 报错 |

---

## 5. VHOST ioctl (fd = vhost_fd, /dev/vhost-net/scsi/vsock)

| 函数 | ioctl命令 | 参数 | 返回值用途 |
|------|-----------|------|-----------|
| virtio_vhost_init() | VHOST_SET_OWNER | 无 | 声明当前进程为 vhost 设备所有者 (必须第一个调用)；r!=0 die |
| virtio/net.c: virtio_net__vhost_init() | VHOST_RESET_OWNER | 无 | 重置 vhost-net 设备所有者 (错误恢复时)；无返回值检查 |
| virtio_vhost_init() | VHOST_SET_MEM_TABLE | struct vhost_memory *mem {nregions, regions[]{guest_phys_addr, memory_size, userspace_addr}} | 传递 guest 内存映射表给 vhost (使 vhost 能直接访问 guest 内存)；r!=0 die |
| virtio/net.c: virtio_net__vhost_init() | VHOST_GET_FEATURES | u64 *vhost_features | 获取 vhost-net 支持的特性位掩码；!=0 报错 |
| virtio/scsi.c: virtio_scsi_vhost_init() | VHOST_GET_FEATURES | u64 *features | 获取 vhost-scsi 支持的特性位；r!=0 报错 |
| virtio/vsock.c: virtio_vsock_vhost_init() | VHOST_GET_FEATURES | u64 *features | 获取 vhost-vsock 支持的特性位；r!=0 报错 |
| virtio_vhost_set_features() | VHOST_SET_FEATURES | u64 *masked_feat (features & ~VIRTIO_F_ACCESS_PLATFORM) | 设置 vhost 特性位 (去除 ACCESS_PLATFORM)；返回 ioctl 结果 |
| virtio_vhost_set_vring() | VHOST_SET_VRING_NUM | struct vhost_vring_state {index=vq编号, num=vring大小} | 设置 vring 描述符数量；r<0 die |
| virtio_vhost_set_vring() | VHOST_SET_VRING_BASE | struct vhost_vring_state {index, num=0} | 设置 vring available ring 的起始 index；r<0 die |
| virtio_vhost_set_vring() | VHOST_SET_VRING_ADDR | struct vhost_vring_addr {index, desc_user_addr, avail_user_addr, used_user_addr} | 设置 vring 三个环形缓冲区在用户空间的地址；r<0 die |
| virtio_vhost_set_vring() | VHOST_SET_VRING_CALL | struct vhost_vring_file {index, fd=irqfd} | 设置 vring 中断通知 fd (guest 向 vhost 发中断)；r<0 die |
| virtio_vhost_set_vring_kick() | VHOST_SET_VRING_KICK | struct vhost_vring_file {index, fd=event_fd} | 设置 vring IO 通知 fd (guest 向 vhost 发 IO 请求)；r<0 die |
| virtio_vhost_reset_vring() | VHOST_SET_VRING_CALL | struct vhost_vring_file {index, fd=-1} | 断开 vring 中断通知 fd；!=0 打印 perror 但不致命 |
| virtio/net.c: virtio_net__vhost_init() | VHOST_NET_SET_BACKEND | struct vhost_vring_file {index, fd=tap_fd} | 将 TAP 网络设备 fd 连接到 vhost-net 后端；r!=0 报错 |
| virtio/scsi.c: virtio_scsi_vhost_init() | VHOST_SCSI_SET_ENDPOINT | struct vhost_scsi_target {vhostfd, target, subgroup} | 将 vhost-scsi 连接到 SCSI 目标端点；r!=0 报错 |
| virtio/scsi.c: virtio_scsi_vhost_exit() | VHOST_SCSI_CLEAR_ENDPOINT | struct vhost_scsi_target *sdev->target | 断开 vhost-scsi 目标端点；r!=0 报错 |
| virtio/vsock.c: virtio_vsock_start() | VHOST_VSOCK_SET_RUNNING | int *start (=1) | 启动 vhost-vsock 数据传输；r!=0 报错 |
| virtio/vsock.c: virtio_vsock_stop() [间接] | VHOST_VSOCK_SET_RUNNING | int *start (=0) | 停止 vhost-vsock 数据传输 |
| virtio/vsock.c: virtio_vsock_vhost_init() | VHOST_VSOCK_SET_GUEST_CID | u32 *vdev->guest_cid | 设置 vsock guest 的 Context ID；r!=0 报错 |

---

## 6. VFIO 容器级 ioctl (fd = vfio_container, /dev/vfio/vfio)

| 函数 | ioctl命令 | 参数 | 返回值用途 |
|------|-----------|------|-----------|
| vfio_container_init() | VFIO_GET_API_VERSION | 无 | 返回 VFIO API 版本号，须等于 VFIO_API_VERSION，否则报错退出 |
| vfio_get_iommu_type() | VFIO_CHECK_EXTENSION (VFIO_TYPE1v2_IOMMU) | unsigned int VFIO_TYPE1v2_IOMMU | 返回非0表示支持 Type1v2 IOMMU (带 DMA 映射缓存)；优先使用此类型 |
| vfio_get_iommu_type() | VFIO_CHECK_EXTENSION (VFIO_TYPE1_IOMMU) | unsigned int VFIO_TYPE1_IOMMU | 返回非0表示支持 Type1 IOMMU (基本 DMA 映射)；作为降级选择 |
| vfio_container_init() | VFIO_SET_IOMMU | unsigned int iommu_type (VFIO_TYPE1v2_IOMMU 或 VFIO_TYPE1_IOMMU) | 为 VFIO 容器设置 IOMMU 类型 (启用 DMA 地址转换和隔离)；!=0 报错退出 |
| vfio_map_mem_bank() | VFIO_IOMMU_MAP_DMA | struct vfio_iommu_type1_dma_map {argsz, flags=READ|WRITE, vaddr=HVA, iova=GPA, size} | 将 guest 物理地址 (GPA) 映射到 host 虚拟地址 (HVA)，使 VFIO 设备能做 DMA；!=0 返回 -errno |
| vfio_unmap_mem_bank() | VFIO_IOMMU_UNMAP_DMA | struct vfio_iommu_type1_dma_unmap {argsz, size, iova=GPA} | 注销 VFIO DMA 映射；无返回值检查 |

---

## 7. VFIO 组级 ioctl (fd = group->fd, /dev/vfio/groupN)

| 函数 | ioctl命令 | 参数 | 返回值用途 |
|------|-----------|------|-----------|
| vfio_group_get() | VFIO_GROUP_GET_STATUS | struct vfio_group_status *group_status | 获取 IOMMU 组状态 (检查 VIABLE 标志位)；!=0 报错退出 |
| vfio_group_get() | VFIO_GROUP_SET_CONTAINER | int *vfio_container (容器 fd) | 将此 IOMMU 组添加到 VFIO 容器 (使组内设备共享 IOMMU 隔离)；!=0 报错 |
| vfio_group_exit() | VFIO_GROUP_UNSET_CONTAINER | 无 | 将此 IOMMU 组从 VFIO 容器移除；无返回值检查 |
| vfio_configure_device() | VFIO_GROUP_GET_DEVICE_FD | char *vdev->params->name (设备名如 "0000:03:00.0") | 获取 VFIO 组中指定设备的操作 fd，赋给 vdev->fd；<0 表示设备可能为桥设备 |

---

## 8. VFIO 设备级 ioctl (fd = vdev->fd)

| 函数 | ioctl命令 | 参数 | 返回值用途 |
|------|-----------|------|-----------|
| vfio_configure_device() | VFIO_DEVICE_GET_INFO | struct vfio_device_info *vdev->info {argsz=sizeof(info)} | 获取设备基本信息 (flags=PCI标志, num_regions=区域数, num_irqs=中断数)；!=0 报错 |
| vfio_configure_device() | VFIO_DEVICE_RESET | 无 | 重置 VFIO PCI 设备到初始状态；<0 打印 warning 但不致命 |
| vfio_pci_setup_device() | VFIO_DEVICE_GET_REGION_INFO | struct vfio_region_info *info {argsz, index=CONFIG/BAR0-5/ROM} | 获取设备区域 (PCI 配置空间/BAR/ROM) 的 offset、size、flags；!=0 报错 |
| vfio_pci_get_region_info() | VFIO_DEVICE_GET_REGION_INFO | struct vfio_region_info *info {argsz, index=BAR编号} | 获取单个 BAR 区域信息 (大小须为 2 的幂)；ret!=0 返回 -errno |
| vfio_pci_init_msis() (MSI/MSI-X) | VFIO_DEVICE_GET_IRQ_INFO | struct vfio_irq_info *msis->info {argsz, index=MSI/MSI-X_IRQ_INDEX} | 获取 MSI/MSI-X 中断信息 (count=向量数, flags=EVENTFD 能力)；ret!=0 或 count=0 报错 |
| vfio_pci_init_intx() | VFIO_DEVICE_GET_IRQ_INFO | struct vfio_irq_info {argsz, index=INTX_IRQ_INDEX} | 获取 INTx 中断信息 (须 EVENTFD+AUTOMASKED)；ret!=0 或 count=0 报错 |
| vfio_pci_enable_msis() (批量) | VFIO_DEVICE_SET_IRQS | struct vfio_irq_set *msis->irq_set (DATA_EVENTFD+ACTION_TRIGGER, 含全部向量 eventfd) | 批量启用 MSI/MSI-X 中断 (注册所有向量的 eventfd)；ret<0 报错 |
| vfio_pci_enable_msis() (单向量) | VFIO_DEVICE_SET_IRQS | struct vfio_irq_set *single (DATA_EVENTFD+ACTION_TRIGGER, start=i, count=1) | 单独更新某个 MSI 向量的 eventfd；ret<0 报错 |
| vfio_pci_disable_msis() | VFIO_DEVICE_SET_IRQS | struct vfio_irq_set {DATA_NONE+ACTION_TRIGGER, count=0} | 禁用 MSI/MSI-X 中断 (清零所有向量)；ret<0 报错 |
| vfio_pci_disable_intx() | VFIO_DEVICE_SET_IRQS | struct vfio_irq_set {DATA_NONE+ACTION_TRIGGER, index=INTX, count=0} | 禁用 INTx 中断；无返回值检查 |
| vfio_pci_enable_intx() (trigger) | VFIO_DEVICE_SET_IRQS | struct vfio_irq_set {DATA_EVENTFD+ACTION_TRIGGER, index=INTX, count=1, eventfd=trigger_fd} | 注册 INTx 触发 eventfd (host -> guest 中断信号)；ret<0 报错 |
| vfio_pci_enable_intx() (unmask) | VFIO_DEVICE_SET_IRQS | struct vfio_irq_set {DATA_EVENTFD+ACTION_UNMASK, index=INTX, count=1, eventfd=unmask_fd} | 注册 INTx 解掩 eventfd (guest -> host 中断确认)；ret<0 报错 |
| vfio_pci_enable_intx() (错误恢复) | VFIO_DEVICE_SET_IRQS | struct vfio_irq_set {DATA_NONE+ACTION_TRIGGER, count=0} | 错误恢复时清除 trigger 注册；无返回值检查 |

---

## 9. TUN/TAP 与网络 ioctl (fd = tap_fd / socket fd)

| 函数 | ioctl命令 | 参数 | 返回值用途 |
|------|-----------|------|-----------|
| virtio_net__tap_init() | TUNSETIFF | struct ifreq *ifr {ifr_name="tapN", ifr_flags=IFF_TAP|IFF_NO_PI|IFF_VNET_HDR} | 创建/配置 TAP 网络接口；ret<0 报错 |
| virtio_net__tap_init() | TUNSETVNETHDRSZ | int *hdr_len (=sizeof(struct virtio_net_hdr_v1)) | 设置 TAP vnet header 大小 (用于合并帧/校验卸载)；<0 报错 |
| virtio_net__tap_init() | TUNSETOFFLOAD | unsigned int offload (TUN_F_CSUM|TUN_F_TSO4|TUN_F_TSO6|TUN_F_UFO 等标志) | 启用 TAP 卸载特性 (校验和/TCO/UFO 等)；<0 报错，降级重试 |
| virtio_net__tap_init() | TUNSETVNETLE / TUNSETVNETBE | int *val (=1 启用, =0 禁用) | 设置 TAP vnet header 端序 (LE=小端, BE=大端)；<0 报错 |
| virtio_net__tap_init() | SIOCSIFADDR | struct ifreq *ifr {ifr_name, ifr_addr=IP地址} | 设置 TAP 接口的 IP 地址；<0 报错 |
| virtio_net__tap_init() | SIOCGIFFLAGS | struct ifreq *ifr {ifr_name} | 获取 TAP 接口标志位 (UP/PROMISC 等)；用于后续修改前读取 |
| virtio_net__tap_init() | SIOCSIFFLAGS | struct ifreq *ifr {ifr_name, ifr_flags=IFF_UP|IFF_RUNNING} | 设置 TAP 接口标志位 (启动接口)；<0 报错 |

---

## 统计

| 类别 | ioctl 命令数 | fd 类型 |
|------|-------------|---------|
| KVM 系统级 | 7 | sys_fd (/dev/kvm) |
| KVM VM 级 | 19 | vm_fd |
| KVM vCPU 级 | 25+ | vcpu_fd |
| KVM 设备级 | 14 | gic_fd / aia_fd |
| VHOST | 16 | vhost_fd |
| VFIO 容器级 | 5 | vfio_container_fd |
| VFIO 组级 | 3 | group_fd |
| VFIO 设备级 | 8 | vdev->fd |
| TUN/TAP+网络 | 7 | tap_fd / socket_fd |
| **合计** | **~90** | 9 种 fd 类型 |

```

---

## 1. 主入口与命令分发

```
main()
  ├── kvm__set_dir()
  │     └── set_dir()              [创建/获取 kvm 运行目录]
  └── handle_kvm_command()
        └── handle_command()
              ├── kvm_get_command() [查找匹配的命令]
              └── p->fn()           [函数指针分发，指向以下各命令]

  命令分发表:
  ├── kvm_cmd_run()        -> 见第2节 VM生命周期
  ├── kvm_cmd_stop()       -> 见第4节 IPC控制
  ├── kvm_cmd_pause()      -> 见第4节 IPC控制
  ├── kvm_cmd_resume()     -> 见第4节 IPC控制
  ├── kvm_cmd_debug()      -> 见第4节 IPC控制
  ├── kvm_cmd_stat()       -> 见第4节 IPC控制
  ├── kvm_cmd_balloon()    -> 见第4节 IPC控制
  ├── kvm_cmd_list()       -> 见第4节 IPC控制
  ├── kvm_cmd_version()    -> printf(VERSION)
  ├── kvm_cmd_help()
  │     ├── kvm_help()
  │     │     └── list_common_cmds_help()
  │     └── help_cmd()
  │           ├── kvm_get_command()
  │           └── p->help()           [各命令的 help 函数指针]
  ├── kvm_cmd_setup()      -> 见第2节 do_setup 流程
  └── kvm_cmd_sandbox()
        ├── kvm_run_set_wrapper_sandbox()
        └── kvm_cmd_run()             [sandbox 委托给 run]
```

---

## 2. VM 生命周期 (init / run / exit)

### 2.1 启动阶段: kvm_cmd_run_init()

```
kvm_cmd_run()
  ├── kvm_cmd_run_init()
  │     ├── kvm__new()                    [分配 kvm 结构体]
  │     ├── parse_options()               [解析命令行参数]
  │     ├── kvm_run_validate_cfg()
  │     │     ├── host_ram_size()
  │     │     │     ├── host_page_size()
  │     │     │     └── host_ram_nrpages()
  │     │     └── kvm__arch_validate_cfg()
  │     ├── find_kernel()                 [定位内核映像文件]
  │     ├── find_vmlinux()                [定位 vmlinux 符号文件]
  │     ├── get_ram_size()
  │     ├── kvm_setup_create_new()        [创建 guest rootfs]
  │     │     └── do_setup()
  │     │           ├── make_dir()
  │     │           ├── make_guestfs_dir()
  │     │           ├── make_guestfs_symlink()
  │     │           ├── kvm_setup_guest_init()
  │     │           │     └── extract_file()
  │     │           └── copy_passwd()
  │     ├── kvm_setup_resolv()
  │     │     └── copy_file()             [拷贝 DNS 配置到 guest]
  │     ├── virtio_9p__register()         [注册 9p 共享目录]
  │     ├── kvm_run_set_sandbox()
  │     │     └── kvm__get_dir()
  │     ├── kvm_run_set_real_cmdline()
  │     │     └── kvm__arch_set_cmdline()
  │     ├── kvm_run_write_sandbox_cmd()
  │     │     ├── resolve_program()
  │     │     └── kvm_write_sandbox_cmd_exactly()
  │     └── init_list__init()             [按优先级依次初始化各子系统]
  │           ├── [core_init] kvm__init()
  │           │     ├── kvm__arch_cpu_supports_vm()  [检查 CPU 虚拟化支持]
  │           │     │     └── host_cpuid()           [x86; arm64/riscv 为空]
  │           │     ├── kvm__check_extensions()
  │           │     │     └── kvm__supports_extension()  [ioctl 查询 KVM 扩展]
  │           │     ├── kvm__arch_init()              [架构特定初始化]
  │           │     │     ├── mmap_anon_or_hugetlbfs()
  │           │     │     ├── mprotect() / madvise()
  │           │     │     ├── [x86] 无额外调用
  │           │     │     ├── [arm64] kvm__arch_enable_mte() + gic__create()
  │           │     │     └── [riscv] riscv__irqchip_create()
  │           │     ├── kvm__init_ram()
  │           │     │     └── kvm__register_ram()   [注册内存区域到 KVM]
  │           │     ├── kvm__load_kernel()
  │           │     │     └── kvm__arch_load_kernel_image()
  │           │     │           ├── load_bzimage()   [x86: 加载 bzImage]
  │           │     │           │     └── guest_real_to_host()
  │           │     │           └── load_flat_binary() [x86: 加载 flat binary]
  │           │     │                 └── guest_real_to_host()
  │           │     ├── kvm__load_firmware()        [arm64: 加载固件]
  │           │     │     └── read_file()
  │           │     └── kvm__arch_setup_firmware()
  │           │           └── setup_bios()           [x86; 见第7节]
  │           │
  │           ├── [base_init] kvm_cpu__init()
  │           │     ├── kvm__max_cpus()
  │           │     │     └── kvm__recommended_cpus()
  │           │     ├── kvm_cpu__arch_init()
  │           │     │     ├── kvm_cpu__new()
  │           │     │     ├── kvm_cpu__set_lint()     [x86]
  │           │     │     └── vcpu_configure_sve()    [arm64]
  │           │     └── kvm_cpu__reset_vcpu()
  │           │           ├── kvm_cpu__setup_cpuid()  -> filter_cpuid()  [x86]
  │           │           ├── kvm_cpu__setup_sregs()                  [x86]
  │           │           ├── kvm_cpu__setup_regs()                   [x86]
  │           │           ├── kvm_cpu__setup_fpu()                    [x86]
  │           │           └── kvm_cpu__setup_msrs()                  [x86]
  │           │           └── reset_vcpu_aarch32/aarch64()           [arm64]
  │           │
  │           ├── [base_init] kvm_ipc__init()          -> 见第4节 IPC
  │           ├── [dev_base_init] pci__init()           -> 见第5节 PCI
  │           ├── [dev_base_init] irq__init()           -> 见第5节 IRQ
  │           ├── [dev_init] term_init()                -> 见第8节 Terminal
  │           ├── [firmware_init] fb__init()            -> 见第8节 FB
  │           ├── [base_init] ioeventfd__init()         -> 见第5节 IOEVENTFD
  │           ├── [dev_init] virtio_blk__init()         -> 见第6节 Virtio
  │           ├── [dev_init] virtio_net__init()         -> 见第6节 Virtio
  │           ├── [dev_init] virtio_console__init()     -> 见第6节 Virtio
  │           ├── [dev_init] virtio_rng__init()         -> 见第6节 Virtio
  │           ├── [dev_init] virtio_bln__init()         -> 见第6节 Virtio
  │           ├── [dev_init] virtio_9p__init()          -> 见第6节 Virtio
  │           ├── [dev_init] virtio_scsi__init()        -> 见第6节 Virtio
  │           ├── [dev_init] virtio_vsock__init()       -> 见第6节 Virtio
  │           ├── [late_init] symbol_init()             -> 见第8节 Symbol
  │           └── [其他] ioport__setup_arch()           [x86; 见第7节]
```

### 2.2 运行阶段: kvm_cmd_run_work()

```
kvm_cmd_run_work()
  ├── pthread_create(kvm_cpu_thread)    [为每个 vCPU 创建线程]
  │     └── kvm_cpu_thread()
  │           ├── kvm__set_thread_name()
  │           └── kvm_cpu__start()      -> 见第3节 CPU主循环
  ├── pthread_join()                    [等待所有 vCPU 线程结束]
  └── kvm_cpu__exit()
        ├── kvm_cpu__delete()           [释放 vCPU 结构体]
        ├── kvm__pause()                [暂停所有 vCPU]
        ├── pthread_kill()              [终止线程]
        ├── pthread_join()
        └── kvm__continue()
```

### 2.3 退出阶段: kvm_cmd_run_exit()

```
kvm_cmd_run_exit()
  ├── compat__print_all_messages()      [输出兼容性警告]
  │     └── compat__free()
  └── init_list__exit()                 [按优先级逆序依次退出各子系统]
        ├── [core_exit] kvm__exit()
        │     └── kvm__arch_delete_ram()  [munmap 释放内存]
        ├── [base_exit] kvm_ipc__exit()    -> 见第4节 IPC
        ├── [dev_base_exit] pci__exit()    -> 见第5节 PCI
        ├── [dev_base_exit] irq__exit()
        ├── [dev_exit] term_exit()
        ├── [firmware_exit] fb__exit()
        ├── [base_exit] ioeventfd__exit()
        ├── [dev_exit] 各 virtio 设备 exit
        ├── [late_exit] symbol_exit()
        └── [其他] mptable__exit()         [x86]
```

---

## 3. CPU 执行主循环

```
kvm_cpu__start()                        [主循环入口]
  ├── signal(SIGKVMPAUSE, kvm_cpu_signal_handler)
  ├── kvm_cpu__enable_singlestep()      [单步调试模式]
  └── 主循环:
        ├── kvm_cpu__run()
        │     └── ioctl(KVM_RUN)        [进入 KVM，直到 VM exit]
        │
        ├── 根据 exit_reason 分发:
        │
        ├── KVM_EXIT_IO:
        │     └── kvm_cpu__emulate_io()
        │           └── kvm__emulate_io()
        │                 ├── mmio_get()      [查找 IO trap 回调]
        │                 │     └── mmio_search()
        │                 ├── mmio->mmio_fn() [回调: IO 处理函数]
        │                 │     ├── pci_config_address_mmio()
        │                 │     ├── pci_config_data_mmio()
        │                 │     ├── serial8250 io/mmio handler
        │                 │     ├── i8042 handler
        │                 │     ├── virtio_pci config/io handler
        │                 │     └── virtio_mmio handler
        │                 └── mmio_put()
        │                       └── mmio_deregister() -> mmio_remove()
        │
        ├── KVM_EXIT_MMIO:
        │     └── kvm_cpu__emulate_mmio()
        │           └── kvm__emulate_mmio()
        │                 ├── mmio_get()
        │                 ├── mmio->mmio_fn() [回调: MMIO 处理函数]
        │                 │     ├── pci_config_mmio_access()
        │                 │     ├── virtio_mmio handler
        │                 │     └── 其他 MMIO 设备
        │                 └── mmio_put()
        │
        ├── KVM_EXIT_COALECED_MMIO:
        │     └── kvm_cpu__handle_coalesced_mmio()
        │           └── kvm_cpu__emulate_mmio()  [同上]
        │
        ├── KVM_EXIT_FAIL_EMULATION:
        │     ├── kvm_cpu__show_registers()
        │     │     ├── ioctl(KVM_GET_REGS)
        │     │     ├── print_segment()
        │     │     └── print_dtable()
        │     ├── kvm_cpu__show_code()
        │     │     ├── ioctl(KVM_GET_REGS)
        │     │     ├── guest_flat_to_host()
        │     │     ├── symbol_lookup() -> lookup()
        │     │     └── kvm__dump_mem()
        │     └── kvm_cpu__show_page_tables()     [x86]
        │           ├── is_in_protected_mode()
        │           ├── guest_flat_to_host()
        │
        ├── KVM_EXIT_SYSTEM_EVENT (reboot/shutdown):
        │     └── kvm__reboot()
        │           └── pthread_kill(main_thread)
        │
        ├── KVM_EXIT_DEBUG:
        │     └── kvm_cpu__handle_exit()
        │
        ├── KVM_EXIT_IRQ_WINDOW_OPEN:
        │     └── kvm_cpu__run_task()             [处理待执行的 task]
        │           └── task->func() 回调
        │
        └── 其他:
              └── kvm_cpu__arch_nmi()
              └── kvm__notify_paused()            [收到暂停信号]
```

### 3.1 PCI 配置空间处理链路

```
kvm__emulate_io/mmio
  └── mmio_fn 回调
      ├── pci_config_data_mmio()
      │     ├── ioport__read32()
      │     ├── pci__config_wr()
      │     │     ├── pci_device_exists()
      │     │     ├── device__find_dev()
      │     │     ├── pci_hdr->cfg_ops.write()     [设备自定义配置写]
      │     │     ├── pci_config_command_wr()
      │     │     │     ├── pci_bar_is_implemented()
      │     │     │     ├── pci_activate_bar()
      │     │     │     │     ├── pci_bar_is_active()
      │     │     │     │     └── pci_hdr->bar_activate_fn() 回调
      │     │     │     └── pci_deactivate_bar()
      │     │     │           ├── pci_bar_is_active()
      │     │     │           └── pci_hdr->bar_deactivate_fn() 回调
      │     │     └── pci_config_bar_wr()
      │     │           ├── pci_toggle_bar_regions()
      │     │           │     ├── device__first_dev()
      │     │           │     ├── device__next_dev()
      │     │           │     ├── pci_activate_bar()
      │     │           │     └── pci_deactivate_bar()
      │     │           ├── pci_activate_bar_regions()
      │     │           └── pci_deactivate_bar_regions()
      │     └── pci__config_rd()
      │           ├── pci_device_exists()
      │           ├── device__find_dev()
      │           └── pci_hdr->cfg_ops.read()      [设备自定义配置读]
      │
      └── pci_config_mmio_access()
            ├── pci__config_wr()  [同上]
            └── pci__config_rd()  [同上]
```

---

## 4. IPC 与外部控制命令

### 4.1 IPC 服务端 (VM 进程内)

```
kvm_ipc__init()
  ├── kvm__create_socket()              [创建 Unix domain socket]
  │     └── kvm__get_dir()
  ├── epoll__init()                     [启动 epoll 事件循环]
  │     ├── epoll_create()
  │     ├── eventfd()
  │     ├── epoll_ctl()
  │     └── pthread_create(epoll__thread)
  │           └── epoll__thread()
  │                 ├── kvm__set_thread_name()
  │                 ├── epoll_wait()
  │                 └── epoll->handle_event() 回调
  │                       └── kvm_ipc__handle_event()
  │                             ├── kvm_ipc__new_conn()   [accept 新连接]
  │                             │     └── epoll_ctl()
  │                             ├── kvm_ipc__receive()
  │                             │     ├── read_in_full()
  │                             │     └── kvm_ipc__handle()
  │                             │           ├── down_read()
  │                             │           ├── cb() 函数指针回调:
  │                             │           │     ├── handle_stop()
  │                             │           │     │     └── kvm__reboot()
  │                             │           │     ├── handle_pause()
  │                             │           │     │     ├── kvm__continue()
  │                             │           │     │     └── kvm__pause()
  │                             │           │     ├── handle_vmstate()
  │                             │           │     ├── handle_debug()
  │                             │           │     │     ├── serial8250__inject_sysrq()
  │                             │           │     │     ├── pthread_kill(SIGUSR1)
  │                             │           │     │     └── kvm_cpu__set_debug_fd()
  │                             │           │     ├── virtio_bln__print_stats()
  │                             │           │     ├── handle_mem()
  │                             │           │     │     └── bdev->vdev.ops->signal_config()
  │                             │           │     └── kvm__pid()
  │                             │           └── up_read()
  │                             └── kvm_ipc__close_conn()
  │                                   ├── epoll_ctl()
  │                                   └── close()
  ├── kvm_ipc__register_handler()       [注册各类消息处理回调]
  │     ├── down_write()
  │     └── up_write()
  └── signal(SIGUSR1, handle_sigusr1)
        └── handle_sigusr1()
              ├── kvm_cpu__get_debug_fd()
              ├── kvm_cpu__show_registers()
              ├── kvm_cpu__show_code()
              └── kvm_cpu__show_page_tables()  [x86]
```

### 4.2 IPC 客户端 (外部命令)

```
各外部命令的通用流程:
  kvm_cmd_stop/pause/resume/debug/stat/balloon/list()
    ├── parse_xxx_options()              [解析命令选项]
    │     └── parse_options()
    │     └── xxx_help() -> usage_with_options()
    ├── kvm__get_sock_by_instance()      [连接目标 VM 的 socket]
    │     ├── kvm__get_dir()
    │     ├── socket() + connect()
    ├── kvm__enumerate_instances()        [枚举所有运行中的 VM]
    │     ├── kvm__get_dir()
    │     ├── opendir()
    │     └── is_socket()
    └── do_xxx()                         [执行具体操作]

  具体操作:
  ├── do_stop()
  │     └── kvm_ipc__send(KVM_IPC_CMD_STOP)
  ├── do_pause()
  │     ├── get_vmstate() -> kvm_ipc__send()
  │     └── kvm_ipc__send(KVM_IPC_CMD_PAUSE)
  ├── do_resume()
  │     ├── get_vmstate() -> kvm_ipc__send()
  │     └── kvm_ipc__send(KVM_IPC_CMD_RESUME)
  ├── do_debug()
  │     └── kvm_ipc__send_msg(KVM_IPC_CMD_DEBUG)
  ├── do_memstat()
  │     └── kvm_ipc__send(KVM_IPC_CMD_STAT)
  ├── kvm_cmd_balloon()
  │     └── kvm_ipc__send_msg(KVM_IPC_CMD_BALLOON)
  └── kvm_cmd_list()
        ├── kvm_list_running_instances()
        │     └── kvm__enumerate_instances(callback=print_guest)
        │           └── print_guest()
        │                 ├── get_pid()     -> kvm_ipc__send()
        │                 └── get_vmstate() -> kvm_ipc__send()
        └── kvm_list_rootfs()
              ├── kvm__get_dir()
              └── opendir() + readdir()
```

### 4.3 IPC 退出

```
kvm_ipc__exit()
  ├── epoll__exit()
  │     ├── write(stop_fd)
  │     ├── read(stop_fd)
  │     └── close()
  ├── close(socket_fd)
  └── kvm__remove_socket()
        ├── kvm__get_dir()
        └── unlink()
```

---

## 5. 设备基础设施

### 5.1 PCI 子系统

```
pci__init()
  ├── kvm__register_pio(pci_config_address_mmio)  [注册 PIO 端口 0xCF8]
  ├── kvm__register_pio(pci_config_data_mmio)     [注册 PIO 端口 0xCFC]
  └── kvm__register_mmio(pci_config_mmio_access)  [注册 MMIO 区域]

pci__exit()
  ├── kvm__deregister_pio(0xCF8)
  ├── kvm__deregister_pio(0xCFC)
  └── kvm__deregister_mmio(pci_config_mmio)

设备注册 PCI 设备时的流程:
  virtio_blk/net/console/rng/balloon/9p__init_one()
    ├── pci__assign_irq()
    │     └── irq__alloc_line()
    ├── virtio_pci__init()
    │     ├── pci_get_io_port_block()
    │     └── pci_get_mmio_block()
    ├── pci__register_bar_regions()
    │     ├── pci_bar_is_implemented()
    │     ├── pci_bar_is_active()
    │     └── pci_activate_bar()
    │           └── pci_hdr->bar_activate_fn() 回调
    └── device__register()
          ├── rb_link_node()
          └── rb_insert_color()
```

### 5.2 MMIO/IO Trap 子系统

```
kvm__register_mmio/mmio_handler(addr, len, mmio_fn_cb)
  └── kvm__register_iotrap(addr, len, mmio_fn_cb, is_mmio=true)
        ├── malloc()
        ├── ioctl(KVM_SET_USER_MEMORY_REGION) 或 ioctl(KVM_SET_BPF)
        ├── mutex_lock()
        └── mmio_insert()
              └── rb_int_insert()

kvm__deregister_mmio/pio(addr)
  └── kvm__deregister_iotrap(addr, is_mmio=true/false)
        ├── mutex_lock()
        ├── mmio_search_single()
        └── mmio_deregister()
              ├── ioctl(KVM_SET_USER_MEMORY_REGION)
              ├── mmio_remove() -> rb_int_erase()
              └── free()

kvm__register_mem(kvm, mem_region)
  ├── mutex_lock()
  ├── ioctl(KVM_SET_USER_MEMORY_REGION)
  ├── kvm_mem_type_to_string()
  └── mutex_unlock()
```

### 5.3 IRQ 子系统

```
irq__init()  [x86 版本]
  ├── irq__add_routing()
  │     └── irq__allocate_routing_entry()
  └── ioctl(KVM_SET_GSI_ROUTING)

irq__add_msix_route()
  ├── check_for_irq_routing()
  │     └── kvm__supports_extension()
  ├── irq__allocate_routing_entry()
  └── msi_routing_ops->update_route()     [函数指针: irq__update_msix_route]

irq__can_signal_msi()
  └── msi_routing_ops->can_signal_msi()   [函数指针]
      └── irq__default_can_signal_msi()
            └── kvm__supports_extension()

irq__common_add_irqfd()
  ├── msi_routing_ops->translate_gsi()    [函数指针]
  └── ioctl(KVM_IRQFD)

irq__common_del_irqfd()
  ├── msi_routing_ops->translate_gsi()    [函数指针]
  └── ioctl(KVM_IRQFD)

kvm__irq_line(pin, level)                 [x86; 设置 IRQ 线级别]
  └── ioctl(KVM_IRQ_LINE)

kvm__irq_trigger(pin)                     [x86; 触发 IRQ 线脉冲]
  └── kvm__irq_line(pin, 1)
  └── kvm__irq_line(pin, 0)
```

### 5.4 IOEVENTFD 子系统

```
ioeventfd__init()
  ├── kvm__supports_extension()
  └── epoll__init()                       [启动独立 epoll 线程]

ioeventfd__add_event(addr, dat, fn_cb)
  ├── eventfd()
  ├── ioctl(KVM_IOEVENTFD)               [注册到 KVM 内核]
  ├── epoll_ctl(EPOLL_CTL_ADD)
  └── list_add_tail()

ioeventfd__del_event(addr, dat)
  ├── ioctl(KVM_IOEVENTFD)               [从 KVM 内核移除]
  ├── epoll_ctl(EPOLL_CTL_DEL)
  ├── list_del()
  ├── close()
  └── free()

ioeventfd__handle_event()
  ├── read()                              [读取 eventfd]
  └── ioevent->fn() 回调                  [触发 virtio 设备 I/O 处理]
      ├── virtio_pci__ioevent_callback()
      │     └── vdev->ops->notify_vq()   [如: virtio_blk notify_vq]
      │           └── thread_pool__do_job()
      └── virtio_mmio_ioevent_callback()
            └── vdev->ops->notify_vq()
```

### 5.5 EPOLL 子系统

```
epoll__init()
  ├── epoll_create()
  ├── eventfd()                           [创建 stop 信号 fd]
  ├── epoll_ctl(EPOLL_CTL_ADD)            [注册 stop fd + 主 fd]
  └── pthread_create(epoll__thread)

epoll__thread()
  ├── kvm__set_thread_name("kvm-epoll")
  └── 循环:
        ├── epoll_wait()
        └── epoll->handle_event() 回调    [如 kvm_ipc__handle_event 或 ioeventfd__handle_event]

epoll__exit()
  ├── write(stop_fd)                      [通知线程停止]
  ├── read(stop_fd)
  └── close()
```

### 5.6 Device Registry

```
device__register(dev)
  ├── rb_link_node()
  └── rb_insert_color()

device__unregister(dev)
  └── rb_erase()

device__find_dev(device_id)
  └── rb_entry()                          [红黑树查找]

device__first_dev() / device__next_dev()
  ├── rb_first() / rb_next()
  └── rb_entry()                          [遍历所有设备]
```

---

## 6. Virtio 设备子系统

### 6.1 Virtio Core (队列操作)

```
virtio_init_device_vq()                   [初始化 virtqueue 的端序和 event_idx]

virt_queue__get_iov(queue, iov, out, in)
  ├── virt_queue__pop()                   [从 available ring 取出一个描述符]
  └── virt_queue__get_head_iov()
        ├── virt_desc__test_flag()
        ├── virtio_guest_to_host_u32/u64()
        ├── guest_flat_to_host()          [GPA -> HVA 转换]
        └── next_desc()

virt_queue__set_used_elem(queue, head, len)
  ├── virt_queue__set_used_elem_no_update()
  │     ├── virtio_guest_to_host_u16/u32()
  │     └── virtio_host_to_guest_u32()
  └── virt_queue__used_idx_advance()
        ├── virtio_guest_to_host_u16()
        ├── virtio_host_to_guest_u16()
        └── wmb()

virtio_queue__should_signal(queue)
  └── virtio_guest_to_host_u16()
```

### 6.2 Virtio PCI Transport

```
virtio_pci__init(vdev)                    [分配 PCI 资源]
  ├── pci__assign_irq()
  ├── pci_get_io_port_block()             [分配 IO 端口范围]
  ├── pci_get_mmio_block()                [分配 MMIO 范围]

virtio_pci_init_vq(vdev, vq)
  ├── virtio_pci__init_ioeventfd()        [注册 ioeventfd 加速]
  │     ├── virtio_pci__mmio_addr/port_addr()
  │     ├── eventfd()
  │     ├── ioeventfd__add_event()
  │     └── vdev->ops->notify_vq_eventfd() 回调
  ├── virtio_pci__add_msix_route()        [分配 MSI-X 向量]
  │     └── irq__add_msix_route()
  └── vdev->ops->init_vq() 回调           [设备特定的 vq 初始化]

virtio_pci__signal_vq(vdev, vq)
  ├── irq__can_signal_msi()
  ├── irq__signal_msi()                   [MSI 中断]
  └── kvm__irq_line()                     [INTx 中断 (x86)]

virtio_pci__signal_config(vdev)
  └── kvm__irq_trigger()                  [配置空间变化中断]

virtio_pci_exit_vq(vdev, vq)
  ├── virtio_pci__del_msix_route()
  ├── ioeventfd__del_event()
  └── virtio_exit()
```

### 6.3 Virtio MMIO Transport

```
virtio_mmio_init_device(vdev)
  ├── pci_get_mmio_block()                [分配 MMIO 范围]
  └── kvm__register_mem()                 [注册到 KVM]

virtio_mmio_init_vq(vdev, vq)
  ├── virtio_mmio_init_ioeventfd()
  │     ├── ioeventfd__add_event()
  │     └── vdev->ops->notify_vq_eventfd() 回调
  └── vdev->ops->init_vq() 回调

virtio_mmio_signal_vq(vdev, vq)
  └── kvm__irq_trigger()

virtio_mmio_exit_vq(vdev, vq)
  ├── ioeventfd__del_event()
  └── virtio_exit()
```

### 6.4 virtio-blk (块设备)

```
virtio_blk__init()
  └── virtio_blk__init_one()
        ├── disk_image__open()
        │     ├── raw_image__open()       [raw 格式]
        │     └── qcow2_image__open()     [qcow2 格式]
        ├── virtio_pci__init()
        ├── pci__register_bar_regions()
        ├── device__register()
        └── compat__add_message()

virtio_blk init_vq() 回调
  ├── virtio_init_device_vq()
  └── thread_pool__init_job()

virtio_blk notify_vq() 回调              [ioeventfd 触发]
  └── thread_pool__do_job()               [提交到线程池]

virtio_blk_do_io()                        [线程池执行]
  ├── virt_queue__available()
  ├── virt_queue__pop()
  ├── virt_queue__get_head_iov()
  └── virtio_blk_do_io_request()
        ├── memcpy_fromiovec_safe()
        ├── disk_image__read() / write() / flush()
        └── virtio_blk_complete()
              ├── virt_queue__set_used_elem()
              ├── virtio_queue__should_signal()
              └── vdev->ops->signal_vq() 回调
                    └── virtio_pci__signal_vq() 或 virtio_mmio_signal_vq()
```

### 6.5 virtio-net (网络设备)

```
virtio_net__init()
  └── virtio_net__init_one()
        ├── virtio_net__tap_init()
        │     ├── uip_ops_tx/rx()         [用户态网络栈模式]
        │     │     └── uip_tx/rx() -> uip_buf_set_used()
        │     └── tap_ops_tx/rx()         [TAP 模式]
        │           └── writev() / readv()
        ├── virtio_net__tap_create()
        ├── virtio_pci__init()
        ├── pci__register_bar_regions()
        ├── device__register()
        ├── compat__add_message()
        ├── pthread_create(virtio_net_rx_thread)
        └── pthread_create(virtio_net_tx_thread)

virtio_net_rx_thread()                    [独立接收线程]
  ├── virt_queue__get_iov()
  ├── ndev->ops->rx() 回调
  │     ├── uip_ops_rx() -> uip_rx()
  │     └── tap_ops_rx() -> readv()
  ├── virt_queue__set_used_elem()
  ├── virtio_queue__should_signal()
  └── vdev->ops->signal_vq() 回调

virtio_net_tx_thread()                    [独立发送线程]
  ├── virt_queue__get_iov()
  ├── ndev->ops->tx() 回调
  │     ├── uip_ops_tx() -> uip_tx()
  │     └── tap_ops_tx() -> writev()
  ├── virt_queue__set_used_elem()
  ├── virtio_queue__should_signal()
  └── vdev->ops->signal_vq() 回调
```

### 6.6 virtio-console

```
virtio_console__init()
  ├── virtio_pci__init()
  ├── pci__register_bar_regions()
  └── device__register()

virtio_console__inject_interrupt()        [term_poll_thread 触发]
  └── thread_pool__do_job()

virtio_console__inject_interrupt_callback() [线程池回调: 从终端读取 -> 写入 vq]
  ├── term_readable()
  ├── virt_queue__get_iov()
  ├── term_getc_iov() -> term_getc()
  ├── virt_queue__set_used_elem()
  └── vdev->ops->signal_vq() 回调

virtio_console_handle_callback()          [线程池回调: 从 vq 读取 -> 写入终端]
  ├── virt_queue__get_iov()
  ├── term_putc_iov() -> writev()
  ├── virt_queue__set_used_elem()
  └── vdev->ops->signal_vq() 回调
```

### 6.7 virtio-rng

```
virtio_rng__init()
  ├── virtio_pci__init()
  ├── pci__register_bar_regions()
  └── device__register()

virtio_rng_do_io()                         [线程池回调]
  ├── virt_queue__available()
  ├── virtio_rng_do_io_request()
  │     ├── virt_queue__get_iov()
  │     ├── readv()                        [从 /dev/urandom 读取]
  │     └── virt_queue__set_used_elem()
  └── vdev->ops->signal_vq() 回调
```

### 6.8 virtio-balloon

```
virtio_bln__init()
  ├── kvm_ipc__register_handler()          [注册 IPC 处理: stats/mem]
  ├── virtio_pci__init()
  ├── pci__register_bar_regions()
  └── device__register()

virtio_bln_do_io()                         [线程池回调]
  ├── virtio_bln_do_io_request()           [处理 inflate/deflate 请求]
  │     ├── virt_queue__get_iov()
  │     ├── guest_flat_to_host()
  │     ├── madvise()                      [释放/回收内存页]
  │     └── virt_queue__set_used_elem()
  ├── virtio_bln_do_stat_request()         [处理统计请求]
  └── vdev->ops->signal_vq() 回调

virtio_bln__print_stats()                  [IPC 回调: 输出 balloon 统计]
virtio_bln__collect_stats()
  └── virt_queue__set_used_elem()

handle_mem()                               [IPC 回调: 通知 guest 内存变化]
  └── bdev->vdev.ops->signal_config()
        └── virtio_pci__signal_config()
```

### 6.9 virtio-9p

```
virtio_9p__register()                      [在 kvm_cmd_run_init 时注册共享目录]
  └── kvm__register_mem()

virtio_9p__init()
  ├── virtio_pci__init() 或 virtio_mmio_init_device()
  ├── pci__register_bar_regions()
  └── device__register()

virtio_9p 处理流程:
  [9p 协议消息通过 virtqueue 传递]
  ├── virt_queue__get_iov()
  ├── guest_flat_to_host()
  ├── 9p 协议处理 (walk/open/read/write/stat/clunk...)
  ├── virt_queue__set_used_elem()
  └── vdev->ops->signal_vq() 回调
```

### 6.10 virtio-vhost (内核加速)

```
virtio_vhost_init()
  ├── virtio_vhost_start_poll()
  │     └── epoll__init()
  ├── ioctl(VHOST_SET_OWNER)
  └── ioctl(VHOST_SET_MEM_TABLE)

virtio_vhost_set_features()
  └── ioctl(VHOST_SET_FEATURES)

virtio_vhost_set_vring()
  ├── ioctl(VHOST_SET_VRING_NUM)
  ├── ioctl(VHOST_SET_VRING_BASE)
  ├── ioctl(VHOST_SET_VRING_ADDR)

virtio_vhost_set_vring_kick()
  └── ioctl(VHOST_SET_VRING_KICK)

virtio_vhost_signal_vq()                   [epoll 回调]
  ├── read()
  └── vdev->ops->signal_vq() 回调
```

---

## 7. 架构特定模块

### 7.1 x86 架构

```
x86/kvm.c:
  kvm__arch_cpu_supports_vm()
    └── host_cpuid()                       [检查 VMX/SVM 支持]

  kvm__arch_init()
    ├── mmap_anon_or_hugetlbfs()           [分配 RAM 区域]
    ├── mprotect()                         [设置 RAM 访问权限]
    └── madvise()                          [设置内存建议]

  kvm__init_ram()
    └── kvm__register_ram()                [注册多个 RAM bank]

  kvm__arch_load_kernel_image()
    ├── load_bzimage()
    │     ├── guest_real_to_host()
    │     ├── lseek() / read_file()
    │     └── setup_bios() [间接]
    └── load_flat_binary()
          ├── guest_real_to_host()
          └── lseek() / read_file()

  kvm__arch_setup_firmware()
    └── setup_bios()                       [见下方 BIOS]

  kvm__arch_read_term()
    ├── serial8250__update_consoles()
    └── virtio_console__inject_interrupt()

x86/bios.c:
  setup_bios()
    ├── guest_flat_to_host()               [映射 BIOS 区域]
    ├── e820_setup()
    │     └── guest_flat_to_host()         [设置 E820 内存表]
    ├── setup_vga_rom()
    │     └── guest_flat_to_host()         [设置 VGA ROM]
    ├── interrupt_table__setup()
    ├── setup_irq_handler()
    │     ├── guest_flat_to_host()
    │     └── interrupt_table__set()
    └── interrupt_table__copy()

x86/kvm-cpu.c:
  kvm_cpu__arch_init()
    ├── kvm_cpu__new()
    ├── ioctl(KVM_CREATE_VCPU)
    ├── mmap()                             [映射 vCPU KVM 运行区域]
    └── kvm_cpu__set_lint()

  kvm_cpu__reset_vcpu()
    ├── kvm_cpu__setup_cpuid() -> filter_cpuid()
    ├── kvm_cpu__setup_sregs() -> selector_to_base()
    ├── kvm_cpu__setup_regs()
    ├── kvm_cpu__setup_fpu()
    └── kvm_cpu__setup_msrs()

  kvm_cpu__show_code()
    ├── guest_flat_to_host()
    ├── symbol_lookup() -> lookup()
    └── kvm__dump_mem() -> host_ptr_in_ram()

  kvm_cpu__show_page_tables()
    ├── is_in_protected_mode()
    ├── guest_flat_to_host()
    └── host_ptr_in_ram()

x86/ioport.c:
  ioport__setup_arch()
    ├── kvm__register_pio(0x0080, dummy_io)
    ├── kvm__register_pio(0x0080, debug_io)
    ├── kvm__register_pio(0x0402, seabios_debug_io)
    └── kvm__register_pio(0x0064, ps2_control_io)

x86/irq.c:
  irq__init()
    ├── irq__add_routing() -> irq__allocate_routing_entry()
    └── ioctl(KVM_SET_GSI_ROUTING)

x86/mptable.c:
  mptable__init()
    ├── device__first_dev() / device__next_dev()
    ├── mptable_add_irq_src()
    ├── guest_flat_to_host()
    └── mpf_checksum()
```

### 7.2 arm64 架构

```
arm64/kvm.c:
  kvm__arch_init()
    ├── mmap_anon_or_hugetlbfs()
    ├── kvm__arch_enable_mte()
    └── gic__create()                      [创建 GIC 中断控制器]

  kvm__init_ram()
    └── kvm__register_ram()

  kvm__load_firmware()
    ├── stat() + open() + lseek()
    └── read_file()

arm64/kvm-cpu.c:
  kvm_cpu__arch_init()
    ├── kvm_cpu__select_features()
    ├── vcpu_configure_sve()
    └── kvm_arm_targets()

  kvm_cpu__reset_vcpu()
    └── reset_vcpu_aarch32() 或 reset_vcpu_aarch64()
```

### 7.3 riscv 架构

```
riscv/kvm.c:
  kvm__arch_init()
    ├── mmap_anon_or_hugetlbfs()
    └── riscv__irqchip_create()            [创建 IRQ 芯片]

  kvm__init_ram()
    └── kvm__register_ram()
```

---

## 8. 辅助子系统

### 8.1 Terminal

```
term_init()
  ├── tcgetattr()                          [保存原始终端属性]
  ├── tcsetattr()                          [设置 raw 模式]
  ├── pthread_create(term_poll_thread_loop)
  │     └── term_poll_thread_loop()
  │           ├── kvm__set_thread_name("kvm-term-poll")
  │           ├── poll()
  │           └── kvm__arch_read_term()
  │                 ├── serial8250__update_consoles()
  │                 └── virtio_console__inject_interrupt()
  ├── signal(SIGTERM, term_sig_cleanup)
  └── atexit(term_cleanup)

term_getc()
  └── read_in_full()                       [从 stdin 读取字符]

term_getc_iov()
  └── term_getc()                          [填充 iov 结构]

term_putc_iov()
  └── writev()                             [向 stdout 写入 iov]

term_readable()
  └── poll(stdin, POLLIN)                  [检查是否有输入]
```

### 8.2 Framebuffer

```
fb__register(ops)
  ├── INIT_LIST_HEAD()
  └── list_add()

fb__attach(fb)
  └── [关联 framebuffer 到目标]

fb__init()
  └── start_targets()
        └── ops->start() 回调              [如 sdl__init / vnc__init / gtk__init]

fb__exit()
  ├── ops->stop() 回调
  └── munmap()
```

### 8.3 Disk

```
disk_image__open(filename, flags)
  ├── raw_image__open()                    [raw 格式后端]
  │     └── open() + stat()
  └── qcow2_image__open()                  [qcow2 格式后端]
        ├── open() + stat()
        └── qcow2_parse_header()

disk_image__read/write/flush(disk, sector, iov)
  ├── [raw] pread/pwrite()
  └── [qcow2] qcow2_disk__read/write()
        └── qcow2_cluster_read/write()
```

### 8.4 VFIO

```
vfio_device_init(group_id, device_id)
  ├── vfio_group_get()                     [获取 VFIO 组]
  └── vfio_pci_setup_device()
        ├── device__find_dev()
        ├── pci__assign_irq()
        └── pci__register_bar_regions()

vfio_pci_enable_msis(vdev)
  ├── irq__add_msix_route()
  └── irq__update_msix_route()

vfio_pci_init_intx(vdev)
  └── irq__alloc_line()
```

### 8.5 UI (显示前端)

```
sdl__init() / vnc__init() / gtk__init()
  ├── fb__register(ops)                    [注册显示操作]
  └── fb__attach(fb)                       [关联 framebuffer]

vesa__init()                               [VESA framebuffer 设备]
  ├── guest_flat_to_host()
  ├── pci__assign_irq()
  ├── pci_get_io_port_block()
  ├── pci__register_bar_regions()
  └── device__register()
```

### 8.6 Symbol (调试符号)

```
symbol_init()
  ├── bfd_init()
  └── bfd_openr(vmlinux_path)

symbol_lookup(ip)
  ├── bfd_check_format()
  ├── bfd_get_symtab_upper_bound() + malloc()
  ├── bfd_canonicalize_symtab()
  ├── bfd_find_nearest_line()
  └── lookup()

symbol_exit()
  └── bfd_close()
```

### 8.7 Guest Compatibility

```
compat__add_message(msg)                   [各 virtio 设备注册兼容性警告]
  ├── malloc() + strdup()
  └── mutex_lock / mutex_unlock

compat__remove_message(msg)                [设备就绪后移除警告]
  ├── mutex_lock
  ├── list_del()
  └── compat__free()

compat__print_all_messages()               [VM 退出时输出所有残留警告]
  ├── mutex_lock
  ├── pr_warning()
  ├── list_del()
  └── compat__free()
```

---

## 跨模块关键调用路径速查

| 路径 | 关键链路 |
|------|----------|
| 启动VM | main -> handle_kvm_command -> kvm_cmd_run -> kvm_cmd_run_init -> init_list__init -> kvm__init + kvm_cpu__init + 各设备init -> kvm_cmd_run_work -> kvm_cpu_thread -> kvm_cpu__start |
| CPU主循环 | kvm_cpu__start -> kvm_cpu__run -> ioctl(KVM_RUN) -> 根据 exit_reason 分发 -> kvm__emulate_io/mmio -> mmio_fn 回调 -> PCI/Virtio 设备处理 |
| IPC控制 | kvm_cmd_stop/pause/resume/debug/stat -> kvm__get_sock_by_instance -> kvm_ipc__send/send_msg -> VM 内 kvm_ipc__handle_event -> cb 回调 -> handle_stop/pause/debug -> kvm__reboot/pause/continue |
| Virtio IO | ioeventfd 回调/线程池回调 -> virtio_blk/net/console/rng/balloon_do_io -> virt_queue__get_iov -> guest_flat_to_host -> 设备操作 -> virt_queue__set_used_elem -> signal_vq 回调 -> virtio_pci__signal_vq/mmio_signal_vq -> kvm__irq_line/irq_trigger |
| PCI配置 | kvm__emulate_io/mmio -> pci_config_data_mmio/mmio_access -> pci__config_wr/rd -> pci_config_command_wr/bar_wr -> pci_activate/deactivate_bar -> bar_activate/deactivate_fn 回调 |
