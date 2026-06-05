# Asterinas VirtIO-Block 驱动完整流程分析

## 总览

```
┌────────────────────────────────────────────────┐
│           Component 初始化框架                   │
│   kernel/libs/comp-sys/component/src/lib.rs    │
│   通过 #[init_component] 宏标记各阶段入口，        │
│   按 Bootstrap → KThread → Process 顺序执行      │
└──────────┬─────────────────────────────────────┘
           │
           ▼
┌──────────────────────┐    ┌──────────────────────────┐
│ pci_init()           │    │ virtio_component_init()  │
│ [kernel/comps/pci/   │    │ [kernel/comps/virtio/    │
│  src/lib.rs]         │───▶│  src/lib.rs]             │
│ 阶段: Bootstrap       │    │ 阶段: Bootstrap           │
└──────────┬───────────┘    └──────────┬────────────────┘
           │                           │
           ▼                           ▼
┌──────────────────────┐    ┌──────────────────────────────┐
│ PCI 总线枚举          │    │ Virtio 设备发现 & 驱动绑定      │
│ 扫描所有 Bus/Dev/Func │    │ PCI 传输层：                   │
│ 创建 PciCommonDevice  │    │   VirtioPciDriver.probe()    │
│ 存入 PCI_BUS 公共设备池│    │ MMIO 传输层：                  │
│                      │    │   VirtioMmioDriver.probe()   │
│                      │    │ 生成 Box<dyn VirtioTransport> │
└──────────────────────┘    └──────────┬───────────────────┘
                                       │
                                       ▼
                              ┌──────────────────────────┐
                              │ 设备初始化 (virtio/src/    │
                              │ lib.rs: 主循环)           │
                              │ Reset → Negotiate →      │
                              │ 匹配 device_type 分发:     │
                              │ VirtioDeviceType::Block   │
                              │   → BlockDevice::init()   │
                              └──────────┬────────────────┘
                                         │
                                         ▼
                              ┌───────────────────────────┐
                              │ BlockDevice::init()       │
                              │ [virtio/src/device/       │
                              │  block/device.rs]         │
                              │ DeviceInner::init():      │
                              │   读配置 → 创建VirtQueue    │
                              │   → 注册IRQ → DRIVER_OK    │
                              │ → aster_block::register() │
                              └──────────┬────────────────┘
                                         │
                                         ▼
                       ┌───────────────────────────────────┐
                       │ Kernel kthread 阶段                │
                       │ [kernel/src/device/registry/       │
                       │  block.rs]                         │
                       │ Spawn kthread: handle_requests()   │
                       │ loop: queue.dequeue → read/write/  │
                       │ flush                              │
                       └──────────┬────────────────────────┘
                                  │
                                  ▼
                       ┌───────────────────────────────────┐
                       │ Kernel process 阶段                │
                       │ 创建 /dev/vdX 设备节点              │
                       │ aster_block: 解析分区表             │
                       │ 注册 PartitionNode, 创建 /dev/vdX1  │
                       └────────────────────────────────────┘
```

---

## 第一阶段：PCI 总线枚举

### 入口

**文件**: `kernel/comps/pci/src/lib.rs:84-88`

```rust
#[init_component]
fn pci_init() -> Result<(), ComponentInitError> {
    init();
    Ok(())
}
```

`pci_init()` 在 `Bootstrap` 阶段执行。

### 架构层初始化

**文件**: `kernel/comps/pci/src/arch/x86/mod.rs:100-128`

```
arch::init() -> Option<RangeInclusive<u8>>
```

两种方式访问 PCI 配置空间：

1. **ECAM (MMIO)**：优先，从 ACPI 信息中解析 `pci_ecam_region`，映射 MMIO 区域
2. **PIO (I/O 端口)**：后备，使用端口 `0xCF8`/`0xCFC`

返回枚举到的总线号范围。

### 全总线扫描

**文件**: `kernel/comps/pci/src/lib.rs:93-129`

```rust
fn init() {
    // 对每个 bus:
    for bus in all_bus {
        // 对每个 device (0..31):
        for device in all_dev.clone() {
            // 对 function 0:
            let first_function_device = PciCommonDevice::new(device_location);
            let has_multi_function = first_function_device.has_multi_funcs();
            lock.register_common_device(first_function_device);
            // 若支持多功能，继续扫描 function 1..7
        }
    }
}
```

### PciCommonDevice 创建

**文件**: `kernel/comps/pci/src/common_device.rs:97-139`

```rust
pub(super) fn new(location: PciDeviceLocation) -> Option<Self> {
    // 读取 Vendor/Device ID，0xFFFF 表示无设备
    // 读取 Header Type (设备类型/多功能标志)
    // 解析 BAR (Base Address Register) 空间，最多6个
    // 解析 Capabilities 链表 (MSI-X, Vendor-Specific, etc.)
}
```

### PciBus 结构

**文件**: `kernel/comps/pci/src/bus.rs:42-104`

```rust
pub struct PciBus {
    common_devices: VecDeque<PciCommonDevice>,  // 未匹配的公共设备
    devices: Vec<Arc<dyn PciDevice>>,            // 已匹配的设备
    drivers: Vec<Arc<dyn PciDriver>>,            // 已注册的驱动
}

// 注册公共设备: 遍历已有驱动 probe
fn register_common_device(&mut self, common_device) {
    for driver in self.drivers.iter() {
        common_device = match driver.probe(common_device) {
            Ok(device) => { self.devices.push(device); return; }
            Err((_, device)) => device  // 继续尝试下一个驱动
        };
    }
    self.common_devices.push_back(common_device);  // 未匹配, 入 FIFO 队列
}

// 注册驱动: 遍历未被认领的公共设备 probe
fn register_driver(&mut self, driver) {
    for _ in (0..length).rev() {
        let common_device = self.common_devices.pop_front().unwrap();
        match driver.probe(common_device) {
            Ok(device) => self.devices.push(device),  // 匹配成功
            Err((_, device)) => self.common_devices.push_back(device),  // 放回队尾
        };
    }
    self.drivers.push(driver);
}
```

---

## 第二阶段：Virtio 组件初始化

### 入口

**文件**: `kernel/comps/virtio/src/lib.rs:43-99`

```rust
#[init_component]
fn virtio_component_init() -> Result<(), ComponentInitError> {
    // 1. 分配块设备主设备号
    VIRTIO_BLOCK_MAJOR_ID.call_once(|| aster_block::allocate_major().unwrap());

    // 2. 初始化运输层 (PCI + MMIO)
    transport::init();

    // 3. 弹出设备运输层，逐个初始化
    while let Some(mut transport) = pop_device_transport() {
        // Reset → ACKNOWLEDGE|DRIVER → NegotiateFeatures → FEATURES_OK → 按类型分发
        BlockDevice::init(transport)
    }
}
```

### 运输层初始化

**文件**: `kernel/comps/virtio/src/transport/mod.rs:256-259`

```rust
pub fn init() {
    virtio_pci_init();   // 注册 VirtioPciDriver 到 PCI_BUS
    virtio_mmio_init();  // 扫描 MMIO 区域 + 注册 VirtioMmioDriver
}
```

---

## 第三-A节：PCI 运输层

### VirtioPciDriver 注册

**文件**: `kernel/comps/virtio/src/transport/pci/mod.rs:18-23`

```rust
pub fn virtio_pci_init() {
    // 创建驱动实例，注册到全局 PCI_BUS
    VIRTIO_PCI_DRIVER.call_once(|| Arc::new(VirtioPciDriver::new()));
    PCI_BUS.lock().register_driver(VIRTIO_PCI_DRIVER.get().unwrap().clone());
}
```

**此时 `PCI_BUS.register_driver()` 会立即对每个未匹配的 `PciCommonDevice` 调用 `VirtioPciDriver.probe()`**。

### VirtioPciDriver::probe()

**文件**: `kernel/comps/virtio/src/transport/pci/driver.rs:34-68`

```rust
impl PciDriver for VirtioPciDriver {
    fn probe(&self, device: PciCommonDevice)
        -> Result<Arc<dyn PciDevice>, (BusProbeError, PciCommonDevice)>
    {
        // 1. 检查 Vendor ID == 0x1af4 (Red Hat, Inc.)
        if device.device_id().vendor_id != 0x1af4 {
            return Err((BusProbeError::DeviceNotMatch, device));
        }

        // 2. 根据 Device ID 范围决定运输层类型:
        let transport = match device_id.device_id {
            // transitional devices (0x1000-0x103f):
            //   有 vendor cap → Modern; 无 → Legacy
            0x1000..0x1040 if revision == 0 => {
                if has_vendor_cap { Box::new(VirtioPciModernTransport::new(device)?) }
                else { Box::new(VirtioPciLegacyTransport::new(device)?) }
            }
            // modern-only devices (0x1040-0x107f):
            //   必须有 vendor cap
            0x1040..0x107f => {
                Box::new(VirtioPciModernTransport::new(device)?)
            }
            _ => return Err(DeviceNotMatch)
        };

        // 3. 存入驱动设备队列
        self.devices.lock().push_back(transport);
        Ok(Arc::new(VirtioPciDevice::new(device_id)))
    }
}
```

### VirtioPciModernTransport::new()

**文件**: `kernel/comps/virtio/src/transport/pci/device.rs:265-327`

```rust
pub(super) fn new(common_device: PciCommonDevice) -> Result<Self, ...> {
    // 1. 从 device_id 计算设备类型:
    //    transitional: device_type = device_id - 0x1000
    //    modern:       device_type = device_id - 0x1040

    // 2. 遍历 Vendor-Specific Capabilities:
    //    CommonCfg  → VirtioPciCommonCfg (队列配置空间)
    //    NotifyCfg  → VirtioPciNotify (通知偏移/乘数/内存BAR)
    //    DeviceCfg  → 设备特定配置 (block config 所在区域)
    //    IsrCfg, PciCfg → 跳过

    // 3. 获取 MSI-X Capability → VirtioMsixManager

    Self { common_device, common_cfg, device_cfg, notify, msix_manager, device_type }
}
```

**关联文件**: `kernel/comps/virtio/src/transport/pci/common_cfg.rs` — 定义 CommonCfg 结构体布局。

### VirtioPciLegacyTransport::new()

**文件**: `kernel/comps/virtio/src/transport/pci/legacy.rs:76-129`

```rust
pub(super) fn new(common_device: PciCommonDevice) -> Result<Self, ...> {
    // 1. 硬编码 device_id → VirtioDeviceType 映射:
    //    0x1001 → Block, 0x1000 → Network, 0x1002 → MemoryBalloon, etc.

    // 2. 获取 BAR0 (Legacy 配置空间映射在此)

    // 3. 遍历队列选择寄存器直到 queue_size == 0，获取 num_queues

    // 4. 获取 MSI-X Capability
    Self { device_type, common_device, config_bar, num_queues, msix_manager }
}
```

### VirtioPciModernTransport 实现的 VirtioTransport trait

**关键方法**:

| 方法 | 文件 | 实现 |
|---|---|---|
| `device_type()` | `device.rs:70` | 返回构造函数解析的值 |
| `set_queue()` | `device.rs:74-112` | 通过 CommonCfg 写入 queue_select/size/desc/driver/device/enable |
| `read_device_features()` | `device.rs:146-162` | 通过 CommonCfg 高低32位选择器读64位 |
| `write_device_features()` | `device.rs:164-180` | 通过 CommonCfg 写高低32位 |
| `read/write_device_status()` | `device.rs:182-194` | 通过 CommonCfg device_status 字段 |
| `register_queue_callback()` | `device.rs:212-248` | 通过 MSI-X 分配 IRQ 向量, 写 queue_msix_vector |
| `register_cfg_callback()` | `device.rs:250-257` | 通过 MSI-X config_msix_irq |
| `notify_config()` | `device.rs:114-122` | 返回 Notify 配置管理器 (offset + multiplier * idx) |
| `finish_init()` | transport/mod.rs:50-57 | 设置 DRIVER_OK 状态 |
| `device_config_mem()` | `device.rs:130-140` | 返回 DeviceCfg capability 对应的 IoMem 切片 |
| `is_legacy_version()` | `device.rs:259-262` | `false` |

**文件**: `kernel/comps/virtio/src/transport/pci/capability.rs` — 解析 Vendor-Specific Capability 结构。

**文件**: `kernel/comps/virtio/src/transport/pci/msix.rs` — MSI-X 向量管理。

---

## 第三-B节：MMIO 运输层

### MMIO 设备扫描

**文件**: `kernel/comps/virtio/src/transport/mmio/bus/arch/x86.rs:8-47`

```rust
pub(super) fn probe_for_device() {
    // 扫描 QEMU MicroVM MMIO 区域 0xFEB0_0000
    // 每个设备占用 512 字节，共 24 个槽位 (IOAPIC 2) 或 8 个 (IOAPIC 1)
    // 对每个槽位:
    for index in 0..num_trans {
        let mmio_base = QEMU_MMIO_BASE + index * QEMU_MMIO_SIZE;
        super::try_register_mmio_device(mmio_base..mmio_base + QEMU_MMIO_SIZE, ...);
        // fatal error (MMIO unavailable 或 magic 不匹配) 时 break
    }
}
```

**文件**: `kernel/comps/virtio/src/transport/mmio/bus/mod.rs:46-98`

```rust
fn try_register_mmio_device<F>(mmio_range, map_irq_line) -> Result<(), MmioRegisterError> {
    // 1. IoMem::acquire(mmio_range) — 获取 MMIO 区域
    // 2. mmio_check_magic() — 检查 MagicValue == 0x74726976
    // 3. mmio_read_device_id() — 读取 DeviceID != 0
    // 4. IrqLine::alloc() + map_irq_line — 分配并映射 IRQ 线
    // 5. MmioCommonDevice::new(io_mem, mapped_irq_line)
    // 6. MMIO_BUS.lock().register_mmio_device(device)
}
```

**文件**: `kernel/comps/virtio/src/transport/mmio/bus/common_device.rs:17-57`

`MmioCommonDevice` 持有 `IoMem` + `MappedIrqLine`，提供 `read_device_id()` 和 `read_version()` 方法。

### MMIO Bus 注册驱动

**文件**: `kernel/comps/virtio/src/transport/mmio/bus/bus.rs:34-93`

`MmioBus` 结构与 `PciBus` 类似，有 `register_driver()` 和 `register_mmio_device()` 方法。

### virtio_mmio_init()

**文件**: `kernel/comps/virtio/src/transport/mmio/mod.rs:18-25`

```rust
pub fn virtio_mmio_init() {
    bus::init();  // 扫描 MMIO 区域，注册发现为 MmioCommonDevice
    VIRTIO_MMIO_DRIVER.call_once(|| Arc::new(VirtioMmioDriver::new()));
    MMIO_BUS.lock().register_driver(VIRTIO_MMIO_DRIVER.get().unwrap().clone());
    // register_driver 会遍历公共设备调用 VirtioMmioDriver::probe()
}
```

### VirtioMmioDriver::probe()

**文件**: `kernel/comps/virtio/src/transport/mmio/driver.rs:32-41`

```rust
impl MmioDriver for VirtioMmioDriver {
    fn probe(&self, device: MmioCommonDevice)
        -> Result<Arc<dyn MmioDevice>, (BusProbeError, MmioCommonDevice)>
    {
        let device = VirtioMmioTransport::new(device);
        let mmio_device = device.mmio_device().clone();
        self.devices.lock().push(device);
        Ok(mmio_device)
    }
}
```

### VirtioMmioTransport::new()

**文件**: `kernel/comps/virtio/src/transport/mmio/device.rs:60-88`

```rust
pub(super) fn new(device: MmioCommonDevice) -> Self {
    // 1. 从 IoMem 创建 SafePtr<VirtioMmioLayout> 访问寄存器
    // 2. 读取 device_id → VirtioDeviceType 映射
    // 3. MultiplexIrq::new() — 创建共享 IRQ 管理器
    // 4. 若 legacy (version 1): 设置 legacy_guest_page_size = PAGE_SIZE
    Self { layout, device, common_device, multiplex }
}
```

**文件**: `kernel/comps/virtio/src/transport/mmio/layout.rs` — `VirtioMmioLayout` 结构体定义 MMIO 寄存器布局。

### VirtioMmioTransport 实现的 VirtioTransport trait

| 方法 | 文件 | 实现 |
|---|---|---|
| `device_type()` | `device.rs:92-94` | device_id → VirtioDeviceType::try_from() |
| `set_queue()` | `device.rs:96-173` | 通过 MMIO 寄存器 queue_sel/queue_num/queue_desc_low&high 等配置 |
| `read_device_features()` | `device.rs:212-228` | 通过 device_features_select 切换高低32位 |
| `register_queue_callback()` | `device.rs:277-291` | 委托给 MultiplexIrq |
| `register_cfg_callback()` | `device.rs:293-299` | 委托给 MultiplexIrq |
| `num_queues()` | `device.rs:182-201` | 轮询 queue_sel/queue_num_max 直到为0 |
| `device_config_mem()` | `device.rs:203-206` | 返回 IoMem 切片 0x100..0x200 |

**文件**: `kernel/comps/virtio/src/transport/mmio/multiplex.rs` — `MultiplexIrq` 共享 IRQ 路由：队列 IRQ 和配置变更 IRQ 共用一个物理 IRQ 线。

---

## 第四阶段：设备初始化和分发

### 弹出运输层

**文件**: `kernel/comps/virtio/src/lib.rs:101-109`

```rust
fn pop_device_transport() -> Option<Box<dyn VirtioTransport>> {
    // 先 PCI, 后 MMIO
    VIRTIO_PCI_DRIVER.pop_device_transport()?  // VecDeque 出队
    VIRTIO_MMIO_DRIVER.pop_device_transport()  // Vec 弹出
}
```

### 标准 Virtio 设备初始化流程

**文件**: `kernel/comps/virtio/src/lib.rs:54-97`

```rust
while let Some(mut transport) = pop_device_transport() {
    // 1. Reset: 写 DeviceStatus::empty()，等待确认
    transport.write_device_status(DeviceStatus::empty())?;
    while transport.read_device_status() != DeviceStatus::empty() { spin_loop(); }

    // 2. ACKNOWLEDGE | DRIVER
    transport.write_device_status(DeviceStatus::ACKNOWLEDGE | DeviceStatus::DRIVER)?;

    // 3. 协商功能位 (Features Negotiation)
    negotiate_features(&mut transport);

    // 4. 现代设备需要 FEATURES_OK
    if !transport.is_legacy_version() {
        transport.write_device_status(... | DeviceStatus::FEATURES_OK)?;
    }

    // 5. 匹配设备类型分发
    match transport.device_type() {
        VirtioDeviceType::Block    => BlockDevice::init(transport),
        VirtioDeviceType::Console  => ConsoleDevice::init(transport),
        VirtioDeviceType::Entropy  => EntropyDevice::init(transport),
        VirtioDeviceType::Input    => InputDevice::init(transport),
        VirtioDeviceType::Network  => NetworkDevice::init(transport),
        VirtioDeviceType::Socket   => SocketDevice::init(transport),
        VirtioDeviceType::FileSystem => FileSystemDevice::init(transport),
        _ => warn!("Unimplemented device: {:?}", device_type),
    };
}
```

### 功能位协商

**文件**: `kernel/comps/virtio/src/lib.rs:111-131`

```rust
fn negotiate_features(transport: &mut Box<dyn VirtioTransport>) {
    let features = transport.read_device_features();
    // 低24位 + 高14位 (50-63) 是设备特定功能位
    let device_specified_features = features & mask;
    // 调用设备特定协商:
    let device_support_features = match transport.device_type() {
        VirtioDeviceType::Block => BlockDevice::negotiate_features(device_specified_features),
        ...
    };
    // 写回协商后的功能位
    transport.write_driver_features(features & (support_feature.bits | device_support_features))?;
}
```

`BlockDevice::negotiate_features()` 会移除 `MQ` (Multi-Queue) 功能位，因为当前仅支持单队列。

---

## 第五阶段：VirtIO-Block 设备初始化

### BlockDevice::init()

**文件**: `kernel/comps/virtio/src/device/block/device.rs:85-112`

```rust
pub(crate) fn init(transport: Box<dyn VirtioTransport>) -> Result<(), VirtioDeviceError> {
    // Step 1: 创建 DeviceInner
    let device = DeviceInner::init(transport)?;

    // Step 2: 分配设备索引和 ID (major, minor)
    let index = NR_BLOCK_DEVICE.fetch_add(1, Ordering::Relaxed);
    let id = DeviceId::new(
        VIRTIO_BLOCK_MAJOR_ID.get().unwrap().get(),
        MinorId::new(index * VIRTIO_DEVICE_MINORS),  // 每设备16个minor
    );

    // Step 3: 生成设备名: vda, vdb, ..., vdz, vdaa, ...
    let name = Self::formatted_device_name(index);

    // Step 4: 创建 BlockDevice (Arc::new_cyclic)
    let block_device = Arc::new_cyclic(|weak_self| BlockDevice {
        device,
        queue: BioRequestSingleQueue::with_max_nr_segments_per_bio(
            (DeviceInner::QUEUE_SIZE - 2) as usize,
        ),
        id, name,
        partitions: SpinLock::new(None),
        weak_self: weak_self.clone(),
    });

    // Step 5: 注册到 aster_block 全局设备注册表
    aster_block::register(block_device).unwrap();

    // Step 6: 初始化 bio segment pool
    bio_segment_pool_init();
    Ok(())
}
```

### DeviceInner::init()

**文件**: `kernel/comps/virtio/src/device/block/device.rs:215-279`

```rust
fn init(mut transport: Box<dyn VirtioTransport>) -> Result<Arc<Self>, VirtioDeviceError> {
    // 1. 创建 ConfigManager<VirtioBlockConfig>, 读取设备配置
    //    capacity, block_size, geometry, topology, num_queues, etc.
    let config_manager = VirtioBlockConfig::new_manager(transport.as_ref());

    // 2. 检查 block_size == 512 (SECTOR_SIZE)
    // 3. 检测功能位 (如 VIRTIO_BLK_F_FLUSH)
    let features = VirtioBlockFeature::new(transport.as_ref());

    // 4. 创建单个 VirtQueue (idx=0, size=64)
    //    分配 DMA 一致性内存 (descriptor table, avail ring, used ring)
    //    调用 transport.set_queue() 配置队列
    let queue = VirtQueue::new(0, Self::QUEUE_SIZE, transport.as_mut())?;

    // 5. 分配 DMA stream 用于请求 (BlockReq) 和响应 (BlockResp)
    let block_requests  = Arc::new(DmaStream::alloc(1, false)?);
    let block_responses = Arc::new(DmaStream::alloc(1, false)?);

    // 6. 注册 IRQ 回调:
    //    register_queue_callback(0, handle_irq, false) — 队列 "完成" 中断
    //    register_cfg_callback(handle_config_change)   — 配置空间变更中断
    transport.register_cfg_callback(Box::new(handle_config_change))?;
    transport.register_queue_callback(0, Box::new(handle_irq), false)?;

    // 7. finish_init(): 设置 DRIVER_OK — 设备开始运作
    transport.finish_init();

    // 8. 返回 Arc<DeviceInner>
    Arc::new(Self { config_manager, features, queue, transport,
                    block_requests, block_responses, id_allocator, submitted_requests })
}
```

### VirtQueue::new() — 队列创建

**文件**: `kernel/comps/virtio/src/queue.rs:106-237`

根据运输层 legacy/modern 标志采用不同分配策略：

- **Modern**: 分别为 Descriptor Table/Avail Ring/Used Ring 分配 3 个独立的 `DmaCoherent` 页面。每个队列最多 256 个描述符。
- **Legacy**: 按 VirtIO 0.9.5 规范，物理连续页面分配：Descriptor Table + Avail Ring 在一段连续区域，Used Ring 在下一段连续区域。调用 `VirtioPciLegacyTransport::calc_virtqueue_size_aligned()` 计算大小。

初始化后构建 Descriptor 空闲链表，写 AvailRing flags，返回 `VirtQueue` 实例。

### IRQ 处理 — handle_irq()

**文件**: `kernel/comps/virtio/src/device/block/device.rs:282-333`

```rust
fn handle_irq(&self) {
    loop {
        // 1. pop_used(): 从 VirtQueue Used Ring 获取已完成的请求 token
        let (token, _) = queue.pop_used_with_min_bytes(RESP_SIZE);

        // 2. 从 submitted_requests BTreeMap 中移除对应请求
        let submitted = self.submitted_requests.lock().remove(&token);

        // 3. 读取 BlockResp 状态
        //    若 RespStatus::Ok → 完成 bio (必要时 sync DMA)
        //    否则 → bio.complete(IoError)
    }
}
```

### IRQ 处理 — handle_config_change()

**文件**: `kernel/comps/virtio/src/device/block/device.rs:335-337`

当前仅记录日志，未实现容量热变更等逻辑。

### 读写流程

**文件**: `kernel/comps/virtio/src/device/block/device.rs:340-527`

`read()`/`write()`/`flush()` 的通用模式：

```
1. id = id_allocator.alloc()                    // 分配请求槽位
2. 构造 BlockReq (type, sector) → 写入 block_requests DMA 区域
3. 准备 DMA 切片: req_slice (输入), data segments, resp_slice (输出)
4. queue.add_dma_bufs(inputs, outputs)           // 提交到 VirtQueue
5. if queue.should_notify(): queue.notify()     // 通知设备
6. 记录 submitted_request 到 BTreeMap<token, SubmittedRequest>
```

---

## 第六阶段：Block 子系统注册

### aster_block::register()

**文件**: `kernel/comps/block/src/lib.rs:123-132`

```rust
pub fn register(device: Arc<dyn BlockDevice>) -> Result<(), Error> {
    let mut registry = DEVICE_REGISTRY.lock();
    let id = device.id().to_raw();
    if registry.contains_key(&id) { return Err(Error::Registered); }
    registry.insert(id, device);
    Ok(())
}

static DEVICE_REGISTRY: Mutex<BTreeMap<u32, Arc<dyn BlockDevice>>> = ...;
```

`BlockDevice` trait 定义:

**文件**: `kernel/comps/block/src/lib.rs:64-89`

```rust
pub trait BlockDevice: Send + Sync + Any + Debug {
    fn enqueue(&self, bio: SubmittedBio) -> Result<(), BioEnqueueError>;
    fn metadata(&self) -> BlockDeviceMeta;     // max_segments, nr_sectors
    fn name(&self) -> &str;
    fn id(&self) -> DeviceId;
    fn is_partition(&self) -> bool;
    fn set_partitions(&self, infos: Vec<Option<PartitionInfo>>);
    fn partitions(&self) -> Option<Vec<Arc<dyn BlockDevice>>>;
}
```

---

## 第七阶段：Kernel KThread 阶段 — 请求处理线程

### 入口

**文件**: `kernel/src/init.rs:150-160`

```rust
fn init_in_first_kthread(path_resolver: &PathResolver) {
    crate::device::init_in_first_kthread();
    // ...
}
```

### device → registry → block

**文件**: `kernel/src/device/registry/block.rs:22-53`

```rust
pub(super) fn init_in_first_kthread() {
    for device in aster_block::collect_all() {
        if device.is_partition() { continue; }

        // VirtIO-Block 设备: spawn handle_requests 线程
        if device.downcast_ref::<VirtIoBlockDevice>().is_some() {
            let virtio_block_device = device_clone.downcast_ref::<VirtIoBlockDevice>().unwrap();
            ThreadOptions::new(move || loop {
                virtio_block_device.handle_requests();
            }).spawn();
        }
        // NVMe 设备同理...
    }
}
```

### handle_requests() 循环

**文件**: `kernel/comps/virtio/src/device/block/device.rs:116-124`

```rust
pub fn handle_requests(&self) {
    let request = self.queue.dequeue();  // BioRequestSingleQueue 阻塞出队
    match request.type_() {
        BioType::Read  => self.device.read(request),
        BioType::Write => self.device.write(request),
        BioType::Flush => self.device.flush(request),
    }
}
```

---

## 第八阶段：Kernel Process 阶段 — 设备节点创建

### 入口

**文件**: `kernel/src/init.rs:169-170`

```rust
fn init_in_first_process(ctx: &Context) {
    crate::device::init_in_first_process(ctx).unwrap();
}
```

### device → registry → block

**文件**: `kernel/src/device/registry/block.rs:55-65`

```rust
pub(super) fn init_in_first_process(path_resolver: &PathResolver) -> Result<()> {
    for device in aster_block::collect_all() {
        let device = Arc::new(BlockFile::new(device));
        if let Some(devtmpfs_meta) = device.devtmpfs_meta() {
            let dev_id = device.id().as_encoded_u64();
            add_node(DeviceType::Block, dev_id, &devtmpfs_meta, path_resolver)?;
            // 创建 /dev/vda, /dev/vdb, ...
        }
    }
    Ok(())
}
```

`BlockFile` 实现了 `Device` trait，提供 `read_at`/`write_at`/`ioctl` 接口，将文件系统请求转发到 `BlockDevice`。

### 分区表解析

**文件**: `kernel/comps/block/src/lib.rs:161-173` (经由 `#[init_component(process)]`)

```rust
fn init_in_first_process() -> Result<(), ComponentInitError> {
    let devices = collect_all();
    for device in devices {
        if let Some(partition_info) = partition::parse(&device) {
            device.set_partitions(partition_info);
        }
    }
}
```

**文件**: `kernel/comps/block/src/partition.rs:150-161`

```rust
pub(super) fn parse(device: &Arc<dyn BlockDevice>) -> Option<Vec<Option<PartitionInfo>>> {
    let mbr = device.read_val::<MbrHeader>(0).unwrap();
    // 0xEE = GPT Protective MBR → parse_gpt()
    // otherwise → parse_mbr()
}
```

`set_partitions()` (在 `block/device.rs:154-186`) 创建 `PartitionNode` 实例并注册到 `aster_block::register()`:

```
vda1: minor = minor_base + 1, name = "vda1"
vda2: minor = minor_base + 2, name = "vda2"
...
超过15个分区时使用 EXTENDED_DEVICE_ID_ALLOCATOR
```

`PartitionNode` 实现了 `BlockDevice` trait，`enqueue()` 会添加 `sid_offset` 将分区 LBA 转换为设备 LBA。

---

## 关键数据结构关系图

```
VirtioPciDriver (devices: VecDeque<Box<dyn VirtioTransport>>)
  │
  ├── VirtioPciModernTransport
  │     ├── common_device: PciCommonDevice
  │     ├── common_cfg: SafePtr<VirtioPciCommonCfg, IoMem>
  │     ├── device_cfg: VirtioPciCapabilityData
  │     ├── notify: VirtioPciNotify
  │     └── msix_manager: VirtioMsixManager
  │
  └── VirtioPciLegacyTransport
        ├── config_bar: BarAccess  (BAR0, legacy config space)
        ├── num_queues: u16
        └── msix_manager: VirtioMsixManager

VirtioMmioDriver (devices: Vec<VirtioMmioTransport>)
  │
  └── VirtioMmioTransport
        ├── layout: SafePtr<VirtioMmioLayout, IoMem>
        ├── common_device: MmioCommonDevice
        └── multiplex: Arc<RwLock<MultiplexIrq>>

        ↓ pop_device_transport()

BlockDevice
  ├── device: Arc<DeviceInner>
  │     ├── config_manager: ConfigManager<VirtioBlockConfig>
  │     ├── features: VirtioBlockFeature
  │     ├── queue: SpinLock<VirtQueue>
  │     │     ├── descs: Vec<DescriptorSlot>
  │     │     ├── avail: SafePtr<AvailRing, Arc<DmaCoherent>>
  │     │     └── used: SafePtr<UsedRing, Arc<DmaCoherent>>
  │     ├── transport: SpinLock<Box<dyn VirtioTransport>>
  │     ├── block_requests: Arc<DmaStream>
  │     ├── block_responses: Arc<DmaStream>
  │     ├── id_allocator: SyncIdAlloc
  │     └── submitted_requests: BTreeMap<u16, SubmittedRequest>
  │
  ├── queue: BioRequestSingleQueue
  ├── id: DeviceId (major + minor)
  ├── name: String ("vda", "vdb", ...)
  └── partitions: SpinLock<Option<Vec<Arc<PartitionNode>>>>
        └── PartitionNode { id, name, device: Arc<dyn BlockDevice>, info }
```

---

## 文件索引

| 阶段 | 文件 | 关键函数/结构 |
|---|---|---|
| PCI 枚举 | `kernel/comps/pci/src/lib.rs` | `pci_init()`, `init()` |
| PCI 架构 | `kernel/comps/pci/src/arch/x86/mod.rs` | `init()` ECAM/PIO |
| PCI 总线 | `kernel/comps/pci/src/bus.rs` | `PciBus`, `PciDriver`, `PciDevice` |
| PCI 公共设备 | `kernel/comps/pci/src/common_device.rs` | `PciCommonDevice::new()` |
| PCI 设备信息 | `kernel/comps/pci/src/device_info.rs` | `PciDeviceLocation`, `PciDeviceId` |
| Virtio 组件 | `kernel/comps/virtio/src/lib.rs` | `virtio_component_init()` |
| Virtio 运输层 | `kernel/comps/virtio/src/transport/mod.rs` | `VirtioTransport` trait, `init()` |
| PCI 运输层 | `kernel/comps/virtio/src/transport/pci/mod.rs` | `virtio_pci_init()` |
| PCI 驱动 | `kernel/comps/virtio/src/transport/pci/driver.rs` | `VirtioPciDriver::probe()` |
| PCI Modern | `kernel/comps/virtio/src/transport/pci/device.rs` | `VirtioPciModernTransport` |
| PCI Legacy | `kernel/comps/virtio/src/transport/pci/legacy.rs` | `VirtioPciLegacyTransport` |
| PCI Cap | `kernel/comps/virtio/src/transport/pci/capability.rs` | Vendor Capability 解析 |
| PCI CommonCfg | `kernel/comps/virtio/src/transport/pci/common_cfg.rs` | CommonCfg 结构体 |
| PCI MSI-X | `kernel/comps/virtio/src/transport/pci/msix.rs` | `VirtioMsixManager` |
| MMIO 运输层 | `kernel/comps/virtio/src/transport/mmio/mod.rs` | `virtio_mmio_init()` |
| MMIO 驱动 | `kernel/comps/virtio/src/transport/mmio/driver.rs` | `VirtioMmioDriver::probe()` |
| MMIO 设备 | `kernel/comps/virtio/src/transport/mmio/device.rs` | `VirtioMmioTransport` |
| MMIO 布局 | `kernel/comps/virtio/src/transport/mmio/layout.rs` | `VirtioMmioLayout` |
| MMIO 总线 | `kernel/comps/virtio/src/transport/mmio/bus/mod.rs` | `try_register_mmio_device()` |
| MMIO Bus | `kernel/comps/virtio/src/transport/mmio/bus/bus.rs` | `MmioBus`, `MmioDriver` |
| MMIO Common | `kernel/comps/virtio/src/transport/mmio/bus/common_device.rs` | `MmioCommonDevice` |
| MMIO 架构 | `kernel/comps/virtio/src/transport/mmio/bus/arch/x86.rs` | `probe_for_device()` |
| MMIO Multiplex | `kernel/comps/virtio/src/transport/mmio/multiplex.rs` | 共享 IRQ 路由 |
| VirtQueue | `kernel/comps/virtio/src/queue.rs` | `VirtQueue::new()` |
| Block 设备 | `kernel/comps/virtio/src/device/block/device.rs` | `BlockDevice`, `DeviceInner` |
| Block 配置 | `kernel/comps/virtio/src/device/block/mod.rs` | `VirtioBlockConfig`, Feature 定义 |
| 设备类型 | `kernel/comps/virtio/src/device/mod.rs` | `VirtioDeviceType` 枚举 |
| DMA 缓冲区 | `kernel/comps/virtio/src/dma_buf.rs` | `DmaBuf` trait |
| ID 分配器 | `kernel/comps/virtio/src/id_alloc.rs` | `SyncIdAlloc` |
| Block 子系统 | `kernel/comps/block/src/lib.rs` | `BlockDevice` trait, `register()` |
| Block 分区 | `kernel/comps/block/src/partition.rs` | MBR/GPT 解析, `PartitionNode` |
| Block 请求队列 | `kernel/comps/block/src/request_queue.rs` | `BioRequestSingleQueue` |
| Block BIO | `kernel/comps/block/src/bio.rs` | `Bio`, `SubmittedBio` |
| Block 设备ID | `kernel/comps/block/src/device_id.rs` | `MajorIdOwner`, `allocate_major()` |
| 内核注册表 | `kernel/src/device/registry/block.rs` | `init_in_first_kthread()`, `init_in_first_process()` |
| 内核注册表 | `kernel/src/device/registry/mod.rs` | 子模块编排 |
