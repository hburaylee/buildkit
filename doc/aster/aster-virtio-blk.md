# Virtio Block 设备与驱动匹配机制分析

> 分析基于 Asterinas 内核源码，梳理从 PCI/MMIO 设备枚举到 virtio-block 驱动绑定、设备注册的完整流程。

---

## 1. 整体架构概览

Asterinas 采用**两级匹配**的方式将 virtio block 设备绑定到驱动：

1. **总线级匹配** —— PCI 总线或 MMIO 总线通过 `probe()` 识别 virtio 设备，生成统一抽象 `VirtioTransport`。
2. **设备类型分发** —— virtio 组件根据 `VirtioDeviceType::Block` 分发到 `BlockDevice::init()`。

```
PCI 枚举 / MMIO 扫描
       │
       ▼
PCI_BUS / MMIO_BUS  (存放未认领设备)
       │
       ▼  register_driver(VirtioPciDriver / VirtioMmioDriver)
driver.probe(device)
       │
       ▼  匹配 vendor/device ID，创建 VirtioTransport
VirtioTransport (PCI Modern/Legacy 或 MMIO)
       │
       ▼  pop_device_transport() 循环
按 VirtioDeviceType 分发
       │
       ▼  VirtioDeviceType::Block
BlockDevice::init(transport)
       │
       ▼
aster_block::register() → DEVICE_REGISTRY
       │
       ▼
Kthread 阶段:  spawn 请求处理线程
Process 阶段:  创建 /dev/vdX 设备节点
```

---

## 2. 文件索引

| 领域 | 文件路径 | 作用 |
|------|----------|------|
| Virtio 组件入口 | `kernel/comps/virtio/src/lib.rs` | 组件初始化，遍历 transport 按类型分发 |
| Virtio 设备类型 | `kernel/comps/virtio/src/device/mod.rs` | `VirtioDeviceType` 枚举 |
| VirtioTransport trait | `kernel/comps/virtio/src/transport/mod.rs` | 统一抽象 PCI/MMIO 传输层 |
| PCI 传输层 | `kernel/comps/virtio/src/transport/pci/mod.rs` | PCI virtio 初始化 |
| PCI 驱动 probe | `kernel/comps/virtio/src/transport/pci/driver.rs` | `VirtioPciDriver::probe()` — 按 vendor/device ID 匹配 |
| PCI Modern 设备 | `kernel/comps/virtio/src/transport/pci/device.rs` | `VirtioPciModernTransport` |
| PCI Legacy 设备 | `kernel/comps/virtio/src/transport/pci/legacy.rs` | `VirtioPciLegacyTransport` |
| MMIO 传输层 | `kernel/comps/virtio/src/transport/mmio/mod.rs` | MMIO virtio 初始化 |
| MMIO 驱动 probe | `kernel/comps/virtio/src/transport/mmio/driver.rs` | `VirtioMmioDriver::probe()` |
| MMIO 设备实现 | `kernel/comps/virtio/src/transport/mmio/device.rs` | `VirtioMmioTransport` |
| MMIO 总线 | `kernel/comps/virtio/src/transport/mmio/bus/bus.rs` | `MmioBus` |
| PCI 总线 | `kernel/comps/pci/src/bus.rs` | `PciBus` |
| PCI 设备枚举 | `kernel/comps/pci/src/lib.rs` | `pci_init()` — 扫描 PCI 拓扑 |
| 块设备注册 | `kernel/comps/block/src/lib.rs` | `BlockDevice` trait + `DEVICE_REGISTRY` |
| 块设备内核注册 | `kernel/src/device/registry/block.rs` | 创建 kthread 和 `/dev/vdX` |
| 总线错误类型 | `ostd/src/bus.rs` | `BusProbeError` |
| Virtio Block 设备 | `kernel/comps/virtio/src/device/block/device.rs` | `BlockDevice` 结构体 |
| Virtio Block 配置 | `kernel/comps/virtio/src/device/block/mod.rs` | Feature 协商 + 配置解析 |

---

## 3. 数据结构

### 3.1 总线层

#### `PciBus` (`kernel/comps/pci/src/bus.rs:42`)

```rust
pub struct PciBus {
    common_devices: VecDeque<PciCommonDevice>,  // 未匹配的设备
    devices: Vec<Arc<dyn PciDevice>>,           // 已匹配的设备
    drivers: Vec<Arc<dyn PciDriver>>,           // 已注册的驱动
}
```

#### `MmioBus` (`kernel/comps/virtio/src/transport/mmio/bus/bus.rs:34`)

```rust
pub struct MmioBus {
    common_devices: VecDeque<MmioCommonDevice>,
    devices: Vec<Arc<dyn MmioDevice>>,
    drivers: Vec<Arc<dyn MmioDriver>>,
}
```

#### `PciDriver` trait (`kernel/comps/pci/src/bus.rs:21`)

```rust
pub trait PciDriver: Sync + Send + Debug {
    fn probe(
        &self,
        device: PciCommonDevice,
    ) -> Result<Arc<dyn PciDevice>, (BusProbeError, PciCommonDevice)>;
}
```

#### `MmioDriver` trait (`kernel/comps/virtio/src/transport/mmio/bus/bus.rs:18`)

```rust
pub trait MmioDriver: Sync + Send + Debug {
    fn probe(
        &self,
        device: MmioCommonDevice,
    ) -> Result<Arc<dyn MmioDevice>, (BusProbeError, MmioCommonDevice)>;
}
```

#### `BusProbeError` (`ostd/src/bus.rs:9`)

```rust
pub enum BusProbeError {
    DeviceNotMatch,
    ConfigurationSpaceError,
}
```

### 3.2 Transport 层

#### `VirtioTransport` trait (`kernel/comps/virtio/src/transport/mod.rs:31`)

```rust
pub trait VirtioTransport: Sync + Send + Debug {
    fn device_type(&self) -> VirtioDeviceType;
    fn read_device_features(&self) -> u64;
    fn write_driver_features(&mut self, features: u64) -> Result<(), VirtioTransportError>;
    fn read_device_status(&self) -> DeviceStatus;
    fn write_device_status(&mut self, status: DeviceStatus) -> Result<(), VirtioTransportError>;
    fn finish_init(&mut self);
    fn device_config_mem(&self) -> Option<IoMem>;
    fn device_config_bar(&self) -> Option<(BarAccess, usize)>;
    fn num_queues(&self) -> u16;
    fn set_queue(...) -> Result<(), VirtioTransportError>;
    fn max_queue_size(&self, idx: u16) -> Result<u16, VirtioTransportError>;
    fn notify_config(&self, idx: usize) -> ConfigManager<u32>;
    fn is_legacy_version(&self) -> bool;
    fn register_queue_callback(...) -> Result<(), VirtioTransportError>;
    fn register_cfg_callback(...) -> Result<(), VirtioTransportError>;
}
```

### 3.3 Virtio 设备类型

#### `VirtioDeviceType` (`kernel/comps/virtio/src/device/mod.rs:16`)

```rust
pub(crate) enum VirtioDeviceType {
    Invalid   = 0,
    Network   = 1,
    Block     = 2,
    Console   = 3,
    Entropy   = 4,
    // ...
    FileSystem = 26,
}
```

---

## 4. 匹配流程详解

### 阶段一：PCI 设备枚举

在 `InitStage::Bootstrap` 阶段，PCI 组件的 `pci_init()` (`kernel/comps/pci/src/lib.rs:84`) 被执行：

1. 调用 `arch::init()`：x86 上通过 ACPI 获取 ECAM (MMCONFIG) 地址，或回退到 I/O 端口 0xCF8/0xCFC。
2. 遍历所有 `bus:device:function` 组合，读取 vendor ID、device ID、BAR、capability 等信息。
3. 为每个合法的 PCI function 创建 `PciCommonDevice`，调用 `PCI_BUS.lock().register_common_device(device)`。

`PciBus::register_common_device()` 的执行逻辑：

```
register_common_device(device):
    for each registered driver:
        match driver.probe(device):
            Ok(pci_device) → 加入 self.devices，返回
            Err((DeviceNotMatch, device)) → 继续尝试下一个驱动
    所有驱动都未匹配 → 留在 self.common_devices 等待未来驱动
```

### 阶段二：PCI virtio 驱动注册与 probe

在 Bootstrap 阶段稍后，virtio 组件初始化 (`kernel/comps/virtio/src/lib.rs:43`)：

#### `virtio_pci_init() (kernel/comps/virtio/src/transport/pci/mod.rs:18)`

1. 创建 `VirtioPciDriver` 实例。
2. 调用 `PCI_BUS.register_driver(driver)`。
3. `PciBus::register_driver()` 遍历所有 `self.common_devices` 中未匹配的设备，对每个设备调用 `driver.probe()`。

#### `VirtioPciDriver::probe() (kernel/comps/virtio/src/transport/pci/driver.rs:34)`

匹配条件：

| 条件 | 值 | 说明 |
|------|----|------|
| vendor ID | `0x1af4` | Virtio 标准 PCI Vendor ID |
| device ID 范围 | `0x1000..0x1040` | Transitional 设备（支持 legacy 和 modern），revision_id == 0 |
| device ID 范围 | `0x1040..0x107f` | Modern-only 设备，必须包含 Vendor Capability |

真实设备类型由 `device_id - 0x1000` 计算得出（例如 Block=2 对应 device_id=0x1002）。

Probe 成功后：
- 检测是否有 Vendor Capability → 决定创建 `VirtioPciModernTransport` 或 `VirtioPciLegacyTransport`
- 将 transport 压入 `self.devices` 队列（`VecDeque<Box<dyn VirtioTransport>>`）
- 返回 `Ok(Arc::new(VirtioPciDevice::new(device_id)))` 给 PCI 总线

### 阶段三：MMIO virtio（备选路径）

如果平台使用 MMIO virtio（如 QEMU microvm），同样在 Bootstrap 阶段执行：

#### `virtio_mmio_init()` (`kernel/comps/virtio/src/transport/mmio/mod.rs:18`)

1. 调用 `bus::init()`：扫描设备所在物理地址（x86: `0xFEB0_0000+`，riscv: 设备树 `"virtio,mmio"` 节点），验证 magic number，读取 device ID，分配 IRQ。
2. 为每个合法设备创建 `MmioCommonDevice`，调用 `MMIO_BUS.register_mmio_device()`。
3. 创建 `VirtioMmioDriver`，调用 `MMIO_BUS.register_driver()`。

#### `VirtioMmioDriver::probe()` (`kernel/comps/virtio/src/transport/mmio/driver.rs:32`)

MMIO 驱动接受所有已验证 virtio MMIO 设备（不做额外 vendor/device 过滤），直接创建 `VirtioMmioTransport` 并压入 `self.devices` 队列。















### 阶段四：Virtio 设备类型分发

回到 `virtio_component_init()` (`kernel/comps/virtio/src/lib.rs:54-97`)，注册完 PCI 和 MMIO 驱动后：

```rust
while let Some(mut transport) = pop_device_transport() {
    // Reset device, 设置 ACKNOWLEDGE | DRIVER 状态
    // negotiate_features() — 读取设备特性，与驱动特性求与
    let device_type = transport.device_type();
    let res = match device_type {
        VirtioDeviceType::Block => BlockDevice::init(transport),
        VirtioDeviceType::Console => ConsoleDevice::init(transport),
        VirtioDeviceType::Entropy => EntropyDevice::init(transport),
        VirtioDeviceType::Input => InputDevice::init(transport),
        VirtioDeviceType::Network => NetworkDevice::init(transport),
        VirtioDeviceType::Socket => SocketDevice::init(transport),
        VirtioDeviceType::FileSystem => FileSystemDevice::init(transport),
        _ => {
            warn!("Found unimplemented device: {:?}", device_type);
            Ok(())
        }
    };
}
```

`pop_device_transport()` 同时从 PCI 和 MMIO 驱动的内部队列中弹出 transport，因此两种传输方式统一处理。

### 阶段五：Block 设备初始化

`BlockDevice::init()` (`kernel/comps/virtio/src/device/block/device.rs:85`)：

1. `DeviceInner::init()`：
   - 读取设备配置（capacity, block size 等）
   - Feature 协商（`BlockFeatures::FLUSH`, `BLK_SIZE` 等）
   - 创建 `VirtQueue`（队列深度 64）
   - 分配 DMA 缓冲区
   - 注册 IRQ 回调
   - `transport.finish_init()` → 设置 `DRIVER_OK` 状态
2. 生成 `DeviceId`（major = `VIRTIO_BLOCK_MAJOR_ID`）
3. 命名设备（`vda`, `vdb`, ..., `vdz`, `vdaa`, ...）
4. `aster_block::register(device)` → 插入 `DEVICE_REGISTRY` (`kernel/comps/block/src/lib.rs:123`)

### 阶段六：内核线程与设备节点

- **Kthread 阶段** (`kernel/src/device/registry/block.rs:22`)：
  - `collect_all()` 获取所有已注册块设备
  - 对每个 virtio block 设备：spawn 一个内核线程，循环调用 `handle_requests()`

- **Process 阶段** (`kernel/src/device/registry/block.rs:55`)：
  - 遍历所有设备，在 devtmpfs 中创建设备节点（如 `/dev/vda`）

---

## 5. 启动时序总览

```
kernel/src/init.rs:main()
  │
  ├── component::init_all(InitStage::Bootstrap)
  │     │
  │     ├── [PCI 组件] pci_init()
  │     │     ├── arch::init()   ── ECAM / PIO 探测
  │     │     ├── 遍历 B:D:F，读取 vendor/device ID、BAR、Capability
  │     │     └── PCI_BUS.register_common_device(device)
  │     │
  │     └── [Virtio 组件] virtio_component_init()
  │           │
  │           ├── transport::init()
  │           │     ├── virtio_pci_init()
  │           │     │     ├── 创建 VirtioPciDriver
  │           │     │     └── PCI_BUS.register_driver()
  │           │     │           └── probe() → VirtioTransport
  │           │     │
  │           │     └── virtio_mmio_init()
  │           │           ├── bus::init() 扫描 MMIO 地址
  │           │           ├── MMIO_BUS.register_mmio_device()
  │           │           ├── 创建 VirtioMmioDriver
  │           │           └── MMIO_BUS.register_driver()
  │           │                 └── probe() → VirtioTransport
  │           │
  │           └── pop_device_transport() 循环
  │                 └── match VirtioDeviceType::Block
  │                       └── BlockDevice::init(transport)
  │                             ├── 创建 VirtQueue、DMA 缓冲区
  │                             ├── 注册 IRQ 回调
  │                             ├── transport.finish_init() (DRIVER_OK)
  │                             └── aster_block::register()
  │                                   └── DEVICE_REGISTRY.insert()
  │
  ├── InitStage::Kthread
  │     └── block::init_in_first_kthread()
  │           └── spawn kthread → handle_requests() 循环
  │
  └── InitStage::Process
        └── block::init_in_first_process()
              └── 创建 /dev/vdX 节点
```

---

## 6. 关键设计要点

1. **无传统 match table**：不像 Linux 有 `struct virtio_device_id` 匹配表，Asterinas 通过 PCI vendor/device ID 范围匹配（`0x1af4` + `0x1000-0x107f`），device type 由 `device_id - 0x1000` 计算。

2. **Transport 抽象**：PCI Modern、PCI Legacy、MMIO 三种传输层统一为 `VirtioTransport` trait，上层设备驱动不感知传输细节。

3. **内部 transport 队列**：PCI 和 MMIO 驱动各维护一个 `VecDeque<Box<dyn VirtioTransport>>` 作为匹配结果的暂存区，由主初始化循环统一消费。

4. **组件化初始化**：利用 `#[init_component]` 声明式组件系统，Bootstrap 阶段按依赖顺序依次初始化 PCI → Virtio。

5. **热插拔支持**：总线模型设计上支持设备后到（先注册驱动、后注册设备）和驱动后到（先注册设备、后注册驱动）两种场景。
