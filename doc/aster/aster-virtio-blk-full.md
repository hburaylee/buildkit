# Asterinas Virtio Block 设备实现原理与代码流程详解

## 目录

1. [整体架构概览](#1-整体架构概览)
2. [核心数据结构](#2-核心数据结构)
3. [设备驱动模型与匹配机制](#3-设备驱动模型与匹配机制)
4. [完整初始化流程](#4-完整初始化流程)
5. [Virtqueue 机制详解](#5-virtqueue-机制详解)
6. [I/O 请求处理全流程](#6-io-请求处理全流程)
7. [中断处理机制](#7-中断处理机制)
8. [块设备抽象层](#8-块设备抽象层)
9. [传输层实现](#9-传输层实现)
10. [关键代码索引](#10-关键代码索引)

---

## 1. 整体架构概览

Asterinas 的 Virtio Block 设备实现采用分层架构，自底向上分为以下几层：

```
┌─────────────────────────────────────────────────────┐
│              用户进程 (User Process)                  │
│         通过 syscall read/write 访问块设备            │
├─────────────────────────────────────────────────────┤
│            VFS / 文件系统层 (Ext2, etc.)              │
│         通过 BlockDevice trait 的 VmIo 接口读写       │
├─────────────────────────────────────────────────────┤
│         块设备抽象层 (aster_block crate)              │
│    BlockDevice trait / Bio / BioRequest / 注册表     │
├─────────────────────────────────────────────────────┤
│       Virtio Block 驱动 (aster_virtio crate)         │
│    BlockDevice 实现 / DeviceInner / 软件暂存队列      │
├─────────────────────────────────────────────────────┤
│          Virtqueue 层 (VirtQueue)                    │
│    描述符表 / Available Ring / Used Ring              │
├──────────────┬──────────────────────────────────────┤
│  PCI 传输层   │           MMIO 传输层                 │
│ (Modern/Legacy)│         (VirtioMmioTransport)       │
├──────────────┴──────────────────────────────────────┤
│              硬件设备 (QEMU virtio-blk)               │
└─────────────────────────────────────────────────────┘
```

### 各层职责

| 层级 | 代码位置 | 职责 |
|------|---------|------|
| 块设备抽象层 | `kernel/comps/block/` | 定义 `BlockDevice` trait、`Bio`/`BioSegment`/`BioRequest` 数据结构、设备注册表、分区解析 |
| Virtio Block 驱动 | `kernel/comps/virtio/src/device/block/` | 实现 `BlockDevice` trait，将 I/O 请求转化为 virtio 协议格式并提交到 virtqueue |
| Virtqueue 层 | `kernel/comps/virtio/src/queue.rs` | 实现 virtio 规范中的 virtqueue 环形缓冲区机制 |
| 传输层 | `kernel/comps/virtio/src/transport/` | 抽象 PCI 和 MMIO 两种传输方式，提供统一的 `VirtioTransport` trait |
| 设备注册层 | `kernel/src/device/registry/block.rs` | 启动块设备处理线程，创建 `/dev` 设备节点 |

---

## 2. 核心数据结构

### 2.1 Virtio Block 配置空间 (`VirtioBlockConfig`)

**文件**: `kernel/comps/virtio/src/device/block/mod.rs:62-96`

```rust
struct VirtioBlockConfig {
    capacity: u64,               // 512字节扇区总数
    size_max: u32,               // 最大段大小
    seg_max: u32,                // 最大段数
    geometry: VirtioBlockGeometry, // 设备几何信息
    blk_size: u32,               // 块大小（默认512字节）
    topology: VirtioBlockTopology, // 拓扑信息
    writeback: u8,               // 回写模式
    num_queues: u16,             // virtqueue 数量
    max_discard_sectors: u32,    // 最大丢弃扇区数
    // ... 更多字段
}
```

这是设备端提供的只读配置空间，驱动通过 `ConfigManager` 读取。capacity 字段表示设备的总容量（以 512 字节扇区为单位），是块设备元数据的核心来源。

### 2.2 Virtio Block 请求与响应

**文件**: `kernel/comps/virtio/src/device/block/device.rs:544-569`

```rust
// 请求头 - 由驱动写入，设备读取
struct BlockReq {
    type_: u32,    // 请求类型: In(0)/Out(1)/Flush(4)/GetId(8)/Discard(11)/WriteZeroes(13)
    reserved: u32, // 保留字段
    sector: u64,   // 起始扇区号
}

// 响应 - 由设备写入，驱动读取
struct BlockResp {
    status: u8,    // 响应状态: Ok(0)/IoErr(1)/Unsupported(2)/NotReady(3)
}
```

每次 I/O 操作至少需要 2 个描述符：一个用于请求（driver → device），一个用于响应（device → driver）。读写操作还需要额外的描述符来传递数据缓冲区。

### 2.3 BlockDevice (外层)

**文件**: `kernel/comps/virtio/src/device/block/device.rs:50-59`

```rust
pub struct BlockDevice {
    device: Arc<DeviceInner>,          // 内部设备实现
    queue: BioRequestSingleQueue,      // 软件暂存队列
    id: DeviceId,                      // 设备 ID (major:minor)
    name: String,                      // 设备名称 (如 "vda")
    partitions: SpinLock<Option<Vec<Arc<PartitionNode>>>>, // 分区信息
    weak_self: Weak<Self>,             // 自引用弱引用
}
```

外层 `BlockDevice` 是面向块设备框架的公共接口，实现了 `aster_block::BlockDevice` trait。它持有一个 `BioRequestSingleQueue` 作为软件暂存队列，将上层的 `SubmittedBio` 聚合为 `BioRequest` 后再由驱动处理线程消费。

### 2.4 DeviceInner (内层)

**文件**: `kernel/comps/virtio/src/device/block/device.rs:199-209`

```rust
struct DeviceInner {
    config_manager: ConfigManager<VirtioBlockConfig>, // 配置空间管理器
    features: VirtioBlockFeature,                     // 协商后的特性
    queue: SpinLock<VirtQueue>,                       // virtqueue (与硬件共享)
    transport: SpinLock<Box<dyn VirtioTransport>>,     // 传输层
    block_requests: Arc<DmaStream>,                   // DMA 内存: 存放 BlockReq 数组
    block_responses: Arc<DmaStream>,                  // DMA 内存: 存放 BlockResp 数组
    id_allocator: SyncIdAlloc,                        // 请求 ID 分配器
    submitted_requests: SpinLock<BTreeMap<u16, SubmittedRequest>>, // 已提交请求追踪
}
```

`DeviceInner` 是与硬件交互的核心，所有 virtio 协议相关的操作都在此完成。`block_requests` 和 `block_responses` 是预分配的 DMA 内存页，用于存放请求和响应数组，每个请求/响应通过 `id` 索引定位。

### 2.5 Bio / BioSegment / BioRequest

**文件**: `kernel/comps/block/src/bio.rs`

```
Bio (未提交)
  ├── metadata: Arc<BioMetadata>   // 类型、扇区范围、状态、等待队列
  ├── segments: Vec<BioSegment>    // 数据段（DMA 缓冲区）
  └── complete_fn: Option<BioCompleteFn> // 完成回调

SubmittedBio (已提交)
  ├── metadata: Arc<BioMetadata>
  ├── segments: Vec<BioSegment>
  ├── sid_offset: u64              // 分区偏移（分区设备使用）
  └── complete_fn: Option<BioCompleteFn>

BioRequest (合并后的请求)
  ├── type_: BioType               // Read/Write/Flush
  ├── sid_range: Range<Sid>        // 物理扇区范围
  ├── num_segments: usize          // 段总数
  └── bios: VecDeque<SubmittedBio> // 包含的 Bio 列表
```

`BioRequest` 是驱动实际处理的单位，它可能合并了多个扇区连续、类型相同的 `SubmittedBio`，从而减少 I/O 请求次数。

### 2.6 VirtQueue

**文件**: `kernel/comps/virtio/src/queue.rs:30-60`

```rust
pub struct VirtQueue {
    descs: Vec<DescriptorSlot>,     // 描述符表
    avail: SafePtr<AvailRing>,      // Available Ring (驱动写，设备读)
    used: SafePtr<UsedRing>,        // Used Ring (设备写，驱动读)
    notify_config: ConfigManager<u32>, // 通知设备配置
    queue_idx: u32,                 // 队列索引
    device_queue_size: u16,         // 队列大小
    num_used: u16,                  // 已用描述符数
    free_head: Option<u16>,         // 空闲链表头
    avail_idx: u16,                 // 下一个 available 槽位索引
    last_used_idx: u16,             // 上一次处理的 used 槽位索引
    is_callback_enabled: bool,      // 回调是否启用
}
```

每个 `DescriptorSlot` 包含一个 DMA 一致性内存中的 `Descriptor` 和驱动侧的链表管理信息：

```rust
struct Descriptor {
    addr: u64,     // DMA 地址
    len: u32,      // 缓冲区长度
    flags: DescFlags, // NEXT | WRITE | INDIRECT
    next: u16,     // 下一个描述符索引
}
```

---

## 3. 设备驱动模型与匹配机制

Asterinas 采用**总线（Bus）驱动的设备-驱动匹配模型**，与 Linux 的设备驱动模型类似。Virtio Block 设备通过两条总线进行发现和匹配：**PCI 总线**和 **MMIO 总线**。

### 3.1 总线核心抽象

#### 3.1.1 BusProbeError

**文件**: `ostd/src/bus.rs`

当驱动 probe 失败时，返回此错误枚举：

```rust
pub enum BusProbeError {
    DeviceNotMatch,           // 设备不匹配该驱动
    ConfigurationSpaceError,  // 访问配置空间出错
}
```

`DeviceNotMatch` 是匹配流程的关键信号：驱动在 `probe()` 中判断设备是否属于自己，不属于则返回此错误，总线会将设备传给下一个驱动尝试。

#### 3.1.2 PCI 总线：Device 与 Driver Trait

**文件**: `kernel/comps/pci/src/bus.rs`

```rust
/// PCI 设备 trait
pub trait PciDevice: Sync + Send + Debug {
    fn device_id(&self) -> PciDeviceId;
}

/// PCI 驱动 trait
pub trait PciDriver: Sync + Send + Debug {
    /// 探测一个未声明的 PCI 设备
    /// 成功 → 返回被声明的设备实例 (Ok)
    /// 失败 → 返回错误码和原始设备 (Err)
    fn probe(
        &self,
        device: PciCommonDevice,
    ) -> Result<Arc<dyn PciDevice>, (BusProbeError, PciCommonDevice)>;
}
```

#### 3.1.3 MMIO 总线：Device 与 Driver Trait

**文件**: `kernel/comps/virtio/src/transport/mmio/bus/bus.rs`

```rust
/// MMIO 设备 trait
pub trait MmioDevice: Sync + Send + Debug {
    fn device_id(&self) -> u32;
}

/// MMIO 驱动 trait
pub trait MmioDriver: Sync + Send + Debug {
    fn probe(
        &self,
        device: MmioCommonDevice,
    ) -> Result<Arc<dyn MmioDevice>, (BusProbeError, MmioCommonDevice)>;
}
```

### 3.2 总线匹配核心算法

#### 3.2.1 PCI 总线 (PciBus)

**文件**: `kernel/comps/pci/src/bus.rs`

PCI 总线维护三个集合：

| 集合 | 类型 | 说明 |
|------|------|------|
| `common_devices` | `VecDeque<PciCommonDevice>` | 未被任何驱动声明（claim）的设备 |
| `devices` | `Vec<Arc<dyn PciDevice>>` | 已被驱动声明的设备 |
| `drivers` | `Vec<Arc<dyn PciDriver>>` | 已注册的驱动 |

**驱动注册时的匹配流程** (`register_driver`)：

```
PciBus::register_driver(driver)
  │
  └── 遍历所有 common_devices（从后向前，逐个弹出）
      │
      ├── driver.probe(device)
      │   ├── Ok(claimed_device)  → 设备被声明，加入 devices 列表，不再放回
      │   └── Err(DeviceNotMatch, device) → 设备不匹配，放回 common_devices 尾部
      │
      └── 遍历完毕后，将 driver 加入 drivers 列表
```

**设备注册时的匹配流程** (`register_common_device`)：

```
PciBus::register_common_device(device)
  │
  └── 遍历所有已注册的 drivers（按注册顺序）
      │
      ├── driver.probe(device)
      │   ├── Ok(claimed_device)  → 设备被第一个匹配的驱动声明，直接返回
      │   └── Err(DeviceNotMatch, device) → 继续尝试下一个驱动
      │
      └── 所有驱动都不匹配 → 设备放入 common_devices 等待后续驱动
```

**关键匹配语义**：
- **先到先得**：第一个 `probe()` 返回 `Ok` 的驱动获得设备
- **双向触发**：注册驱动时扫描已有设备；注册设备时扫描已有驱动
- **设备一旦被声明，不会被其他驱动再次探测**

#### 3.2.2 MMIO 总线 (MmioBus)

**文件**: `kernel/comps/virtio/src/transport/mmio/bus/bus.rs`

MMIO 总线的匹配算法与 PCI 总线完全一致，同样维护 `common_devices`、`devices`、`drivers` 三个集合，匹配逻辑也相同。

### 3.3 PCI 设备发现与注册

**文件**: `kernel/comps/pci/src/lib.rs`

PCI 组件初始化时，枚举所有 PCI 设备并注册到总线：

```
pci_init()
  │
  ├── arch::init()                         // 获取 PCI 总线号列表
  │
  └── 遍历所有 bus/device/function 组合
      │
      ├── PciCommonDevice::new(location)   // 读取配置空间创建设备
      │
      └── PCI_BUS.lock().register_common_device(device)
          │
          └── 此时无驱动注册 → 设备全部进入 common_devices 队列
```

```rust
// pci/src/lib.rs - PCI 设备枚举核心循环
for bus in all_bus {
    for device in all_dev.clone() {
        let first_function_device = PciCommonDevice::new(device_location)?;
        let has_multi_function = first_function_device.has_multi_funcs();
        lock.register_common_device(first_function_device);  // 注册 function 0

        if has_multi_function {
            for function in all_func.clone().skip(1) {
                if let Some(common_device) = PciCommonDevice::new(device_location) {
                    lock.register_common_device(common_device);
                }
            }
        }
    }
}
```

### 3.4 MMIO 设备发现与注册

**文件**: `kernel/comps/virtio/src/transport/mmio/bus/mod.rs`

MMIO 设备通过架构特定的探测机制发现：

#### x86_64 平台

**文件**: `kernel/comps/virtio/src/transport/mmio/bus/arch/x86.rs`

扫描 QEMU MicroVM 的 MMIO 区域（基地址 `0xFEB00000`，每槽 512 字节），逐个验证 magic number：

```
probe_for_device()
  │
  └── 遍历 MMIO 槽位 (0xFEB00000 起，步长 512 字节)
      │
      ├── 读取 magic number
      │   ├── == 0x74726976 ("virt") → 有效的 VirtIO MMIO 设备
      │   └── 其他 → 跳过
      │
      ├── 读取 device_id (偏移 0x08)
      │   └── == 0 → 无效设备，跳过
      │
      └── try_register_mmio_device(range, irq_fn)
          └── MMIO_BUS.lock().register_mmio_device(device)
              └── 此时无驱动 → 设备进入 common_devices
```

#### RISC-V 平台

**文件**: `kernel/comps/virtio/src/transport/mmio/bus/arch/riscv.rs`

通过设备树（Device Tree）发现 MMIO 设备：

```rust
fn probe_for_device() {
    let device_tree = DEVICE_TREE.get().unwrap();
    let mmio_nodes = device_tree.all_nodes().filter(|node| {
        node.compatible().is_some_and(|compatibles| {
            compatibles.all().any(|compatible| compatible == "virtio,mmio")
        })
    });
    mmio_nodes.for_each(|node| {
        let mmio_region = node.reg().unwrap().next().unwrap();
        // ... 解析 IRQ 映射 ...
        try_register_mmio_device(mmio_start..mmio_end, |irq_line| { ... });
    });
}
```

### 3.5 VirtIO PCI 驱动注册与匹配

**文件**: `kernel/comps/virtio/src/transport/pci/mod.rs`

```rust
pub static VIRTIO_PCI_DRIVER: Once<Arc<VirtioPciDriver>> = Once::new();

pub fn virtio_pci_init() {
    VIRTIO_PCI_DRIVER.call_once(|| Arc::new(VirtioPciDriver::new()));
    PCI_BUS.lock().register_driver(VIRTIO_PCI_DRIVER.get().unwrap().clone());
}
```

当 `register_driver` 被调用时，PCI 总线遍历所有未声明的设备，调用 `VirtioPciDriver::probe()`。

### 3.6 VirtIO PCI 驱动 Probe（核心匹配逻辑）

**文件**: `kernel/comps/virtio/src/transport/pci/driver.rs`

这是 PCI 设备与 VirtIO 驱动匹配的核心实现：

```
VirtioPciDriver::probe(device)
  │
  ├── STEP 1: 检查 Vendor ID
  │   └── vendor_id != 0x1AF4 → Err(DeviceNotMatch)  // 非 VirtIO 设备
  │
  ├── STEP 2: 检查 Device ID 确定传输类型
  │   │
  │   ├── 0x1000..0x1040 且 revision_id == 0 (过渡设备)
  │   │   ├── 有 Vendor Capability → VirtioPciModernTransport::new(device)
  │   │   └── 无 Vendor Capability → VirtioPciLegacyTransport::new(device)
  │   │
  │   ├── 0x1040..0x107f (非过渡 Modern 设备)
  │   │   ├── 无 Vendor Capability → Err(DeviceNotMatch)
  │   │   └── 有 → VirtioPciModernTransport::new(device)
  │   │
  │   └── 其他 → Err(DeviceNotMatch)
  │
  ├── STEP 3: 创建传输对象成功
  │   └── self.devices.lock().push_back(transport)  // 存入驱动的设备队列
  │
  └── STEP 4: 返回 Ok(VirtioPciDevice)
      └── 设备被声明，从 PCI 总线 common_devices 中移除
```

**PCI VirtIO 匹配条件总结**：

| 条件 | 值 | 说明 |
|------|-----|------|
| Vendor ID | `0x1AF4` | Red Hat / VirtIO 厂商 ID |
| Device ID | `0x1000..0x107f` | VirtIO 设备 ID 范围 |
| Vendor Capability | Modern 设备必须 | 用于发现配置寄存器 |

**VirtIO PCI Device ID 含义**：

| Device ID 范围 | 类型 | 传输方式 |
|----------------|------|---------|
| `0x1000..0x1040` | 过渡设备 (Transitional) | Modern（有 Vendor Cap）或 Legacy（无 Vendor Cap） |
| `0x1040..0x107f` | 非过渡 Modern 设备 | 仅 Modern |
| `0x1040 + N` | 设备类型 = N | 例如 `0x1042` = Block 设备 |

### 3.7 VirtIO MMIO 驱动注册与匹配

**文件**: `kernel/comps/virtio/src/transport/mmio/mod.rs`

```rust
pub static VIRTIO_MMIO_DRIVER: Once<Arc<VirtioMmioDriver>> = Once::new();

pub fn virtio_mmio_init() {
    bus::init();  // 先探测 MMIO 设备并注册到总线
    VIRTIO_MMIO_DRIVER.call_once(|| Arc::new(VirtioMmioDriver::new()));
    MMIO_BUS.lock().register_driver(VIRTIO_MMIO_DRIVER.get().unwrap().clone());
}
```

**文件**: `kernel/comps/virtio/src/transport/mmio/driver.rs`

MMIO 驱动的 probe **始终匹配**（因为 MMIO 总线上的设备已经通过 magic number 过滤，全部是 VirtIO 设备）：

```rust
impl MmioDriver for VirtioMmioDriver {
    fn probe(&self, device: MmioCommonDevice)
        -> Result<Arc<dyn MmioDevice>, (BusProbeError, MmioCommonDevice)>
    {
        let device = VirtioMmioTransport::new(device);  // 直接创建传输对象
        let mmio_device = device.mmio_device().clone();
        self.devices.lock().push(device);  // 存入驱动的设备队列
        Ok(mmio_device)                    // 始终返回 Ok
    }
}
```

### 3.8 两阶段绑定模型

Asterinas 的 VirtIO 设备-驱动绑定分为**两个阶段**：

```
┌──────────────────────────────────────────────────────────────┐
│                  第一阶段：总线级匹配                          │
│                                                              │
│  PCI/MMIO 总线通过 probe() 将设备与 VirtIO 传输驱动绑定      │
│  结果：创建 VirtioTransport 对象，存入驱动的 devices 队列     │
│  此时只知道传输方式，不知道具体设备类型（Block/Net/Console）    │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                第二阶段：设备类型级初始化                      │
│                                                              │
│  virtio_component_init() 从驱动中取出 Transport 对象         │
│  读取 device_type 分派到具体设备驱动：                        │
│    VirtioDeviceType::Block → BlockDevice::init(transport)    │
│    VirtioDeviceType::Network → NetworkDevice::init(...)      │
│    ...                                                       │
│  此时完成特性协商、VirtQueue 创建、DMA 分配、中断注册等       │
└──────────────────────────────────────────────────────────────┘
```

这种设计的优势在于：
- **传输层与设备类型解耦**：同一套 Block 驱动代码可运行在 PCI Modern、PCI Legacy 或 MMIO 之上
- **简化驱动开发**：总线级匹配只需关注传输细节，设备类型逻辑完全独立

---

## 4. 完整初始化流程

### 4.1 从系统启动到设备可用的全链路

```
┌─────────────────────────────────────────────────────────────────┐
│  1. PCI 组件初始化 (Bootstrap 阶段)                              │
│     pci_init()                                                  │
│     ├── arch::init() 发现 PCI 总线号                             │
│     └── 扫描所有 bus/device/function                             │
│         └── register_common_device() → 设备进入未声明队列         │
├─────────────────────────────────────────────────────────────────┤
│  2. VirtIO 组件初始化 (Bootstrap 阶段)                           │
│     virtio_component_init()                                     │
│     │                                                           │
│     ├── allocate_major()           // 分配块设备主设备号         │
│     │                                                           │
│     ├── transport::init()                                        │
│     │   ├── virtio_pci_init()                                    │
│     │   │   ├── 创建 VirtioPciDriver                             │
│     │   │   └── register_driver() 到 PCI_BUS                    │
│     │   │       └── 遍历未声明设备，probe 匹配 VirtIO 设备       │
│     │   │           └── 匹配成功 → 创建 Transport 存入驱动队列    │
│     │   │                                                        │
│     │   └── virtio_mmio_init()                                   │
│     │       ├── bus::init() → arch::probe_for_device()           │
│     │       │   └── 扫描 MMIO 区域，register_mmio_device()       │
│     │       ├── 创建 VirtioMmioDriver                            │
│     │       └── register_driver() 到 MMIO_BUS                   │
│     │           └── 遍历未声明设备，probe 匹配                    │
│     │               └── 匹配成功 → 创建 Transport 存入驱动队列    │
│     │                                                            │
│     └── 循环: pop_device_transport()   // 逐个取出已发现的设备    │
│         │                                                        │
│         ├── 重置设备 (write status = 0)                           │
│         ├── 设置 ACKNOWLEDGE | DRIVER 状态                       │
│         ├── negotiate_features()        // 特性协商               │
│         ├── 设置 FEATURES_OK 状态 (modern only)                  │
│         │                                                        │
│         └── match device_type                                    │
│             └── VirtioDeviceType::Block => BlockDevice::init()   │
├─────────────────────────────────────────────────────────────────┤
│  3. 块设备组件初始化 (Bootstrap 阶段)                             │
│     device_id::init()                                            │
├─────────────────────────────────────────────────────────────────┤
│  4. 内核设备初始化 (Kthread 阶段)                                 │
│     registry::block::init_in_first_kthread()                     │
│     └── 为每个 virtio-block 设备 spawn 内核线程                   │
│         └── loop { device.handle_requests() }                   │
├─────────────────────────────────────────────────────────────────┤
│  5. 块设备分区解析 (Process 阶段)                                 │
│     解析 MBR/GPT 分区表，创建 PartitionNode                      │
├─────────────────────────────────────────────────────────────────┤
│  6. 设备节点创建 (Process 阶段)                                   │
│     registry::block::init_in_first_process()                     │
│     └── 创建 /dev/vda, /dev/vda1 等设备节点                      │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 特性协商详解

**文件**: `kernel/comps/virtio/src/lib.rs`

```rust
fn negotiate_features(transport: &mut Box<dyn VirtioTransport>) {
    let features = transport.read_device_features();          // 读取设备支持特性
    let mask = ((1u64 << 24) - 1) | (((1u64 << 24) - 1) << 50);
    let device_specified_features = features & mask;
    // 根据设备类型调用对应的 negotiate_features
    let device_support_features = match transport.device_type() {
        VirtioDeviceType::Block => BlockDevice::negotiate_features(device_specified_features),
        // ...
    };
    // 移除 RING_EVENT_IDX 特性（Asterinas 暂不支持）
    support_feature.remove(Feature::RING_EVENT_IDX);
    transport.write_driver_features(features & (support_feature.bits | device_support_features));
}
```

对于 Block 设备，`BlockDevice::negotiate_features` 会移除 `MQ`（多队列）特性：

```rust
// kernel/comps/virtio/src/device/block/device.rs:127-131
pub(crate) fn negotiate_features(features: u64) -> u64 {
    let mut support_features = BlockFeatures::from_bits_truncate(features);
    support_features.remove(BlockFeatures::MQ); // 暂不支持多队列
    support_features.bits
}
```

### 4.3 BlockDevice::init 详细流程

**文件**: `kernel/comps/virtio/src/device/block/device.rs`

```
BlockDevice::init(transport)
  │
  ├── DeviceInner::init(transport)              // 初始化内部设备
  │   │
  │   ├── VirtioBlockConfig::new_manager()      // 创建配置空间管理器
  │   ├── config_manager.read_config()          // 读取设备配置 (容量、块大小等)
  │   ├── 检查 block_size == 512               // 目前仅支持 512 字节扇区
  │   ├── VirtioBlockFeature::new()             // 检查 FLUSH 特性支持
  │   ├── VirtQueue::new(0, 64, transport)      // 创建 virtqueue (索引0, 大小64)
  │   ├── DmaStream::alloc() × 2               // 分配请求/响应 DMA 内存页
  │   ├── SyncIdAlloc::with_capacity(64)        // 创建 ID 分配器
  │   │
  │   ├── 注册 IRQ 回调 (handle_irq)           // virtqueue 中断
  │   ├── 注册配置变更回调 (handle_config_change)
  │   └── transport.finish_init()               // 设置 DRIVER_OK 状态
  │
  ├── 分配设备号 (major:minor)
  ├── 生成设备名称 ("vda", "vdb", ...)
  ├── 创建 BioRequestSingleQueue
  ├── aster_block::register(block_device)       // 注册到块设备注册表
  └── bio_segment_pool_init()                   // 初始化 Bio 段内存池
```

**VirtQueue::new 的关键步骤** (`kernel/comps/virtio/src/queue.rs:106-237`):

1. 根据传输层版本（legacy/modern）分配 DMA 一致性内存
2. 将描述符表、Available Ring、Used Ring 的物理地址设置到传输层
3. 初始化空闲描述符链表
4. 设置 Available Ring 的 flags 为空（启用中断）

### 4.4 设备状态机

VirtIO 规范定义了设备初始化过程中的状态机，Asterinas 严格按照此状态机执行：

```
         write(0)
            │
            ▼
    ┌──────────────┐
    │   Reset (0)   │  ← 设备刚被发现或被重置
    └──────┬───────┘
           │ write(ACKNOWLEDGE)
           ▼
    ┌──────────────┐
    │ ACKNOWLEDGE   │  ← 驱动已发现设备
    └──────┬───────┘
           │ write(ACKNOWLEDGE | DRIVER)
           ▼
    ┌──────────────┐
    │    DRIVER     │  ← 驱动知道如何使用设备
    └──────┬───────┘
           │ negotiate_features()
           │ write(ACKNOWLEDGE | DRIVER | FEATURES_OK)  [Modern only]
           ▼
    ┌──────────────┐
    │ FEATURES_OK   │  ← 特性协商完成
    └──────┬───────┘
           │ write(ACKNOWLEDGE | DRIVER | FEATURES_OK | DRIVER_OK)
           ▼
    ┌──────────────┐
    │   DRIVER_OK   │  ← 驱动已初始化完成，设备可正常使用
    └──────────────┘

    任何阶段出错 → write(FAILED)
```

Asterinas 中对应的状态转换代码：

```rust
// virtio/src/lib.rs - virtio_component_init()

// 重置设备
transport.write_device_status(DeviceStatus::empty())?;
while transport.read_device_status() != DeviceStatus::empty() {
    spin_loop();
}

// 设置 ACKNOWLEDGE | DRIVER
transport.write_device_status(DeviceStatus::ACKNOWLEDGE | DeviceStatus::DRIVER)?;

// 特性协商
negotiate_features(&mut transport);

// Modern 设备设置 FEATURES_OK
if !transport.is_legacy_version() {
    transport.write_device_status(
        DeviceStatus::ACKNOWLEDGE | DeviceStatus::DRIVER | DeviceStatus::FEATURES_OK
    )?;
}

// BlockDevice::init() 内部调用 transport.finish_init() 设置 DRIVER_OK
BlockDevice::init(transport)?;
```

### 4.5 内核线程与设备节点创建

**文件**: `kernel/src/device/registry/block.rs`

#### 内核线程阶段 (init_in_first_kthread)

为每个 VirtIO Block 设备创建专用内核线程来处理 I/O 请求：

```rust
pub(super) fn init_in_first_kthread() {
    for device in aster_block::collect_all() {
        if device.is_partition() { continue; }

        // VirtIO Block 设备
        if device.downcast_ref::<VirtIoBlockDevice>().is_some() {
            let device_clone = device.clone();
            let task_fn = move || {
                let virtio_block_device = device_clone
                    .downcast_ref::<VirtIoBlockDevice>().unwrap();
                loop {
                    virtio_block_device.handle_requests();  // 阻塞式循环
                }
            };
            ThreadOptions::new(task_fn).spawn();
        }
    }
}
```

#### 进程阶段 (init_in_first_process)

在 `/dev` 下创建设备节点：

```rust
pub(super) fn init_in_first_process(path_resolver: &PathResolver) -> Result<()> {
    for device in aster_block::collect_all() {
        let device = Arc::new(BlockFile::new(device));
        if let Some(devtmpfs_meta) = device.devtmpfs_meta() {
            let dev_id = device.id().as_encoded_u64();
            add_node(DeviceType::Block, dev_id, &devtmpfs_meta, path_resolver)?;
        }
    }
    Ok(())
}
```

创建的设备节点示例：
- `/dev/vda` — 整个 VirtIO Block 磁盘
- `/dev/vda1` — 第一个分区
- `/dev/vda2` — 第二个分区

---

## 5. Virtqueue 机制详解

Virtqueue 是 Virtio 规范的核心数据传输机制，由三部分组成：

```
┌─────────────────────────────────────────────┐
│              Descriptor Table                │
│  ┌─────┬─────┬─────┬─────┬─────┬─────┐     │
│  │ D0  │ D1  │ D2  │ D3  │ ... │ Dn  │     │
│  └─────┴─────┴─────┴─────┴─────┴─────┘     │
├─────────────────────────────────────────────┤
│            Available Ring (Driver → Device)  │
│  flags | idx | ring[0..n] | used_event      │
├─────────────────────────────────────────────┤
│             Used Ring (Device → Driver)      │
│  flags | idx | ring[0..n] | avail_event     │
└─────────────────────────────────────────────┘
```

### 5.1 描述符链 (Descriptor Chain)

一次 I/O 操作通过一条描述符链表示。对于 Block 设备：

**读操作** (Driver ← Device):
```
[D0: BlockReq (input)] → [D1: 数据缓冲区1 (output)] → [D2: 数据缓冲区2 (output)] → [D3: BlockResp (output)]
```

**写操作** (Driver → Device):
```
[D0: BlockReq (input)] → [D1: 数据缓冲区1 (input)] → [D2: 数据缓冲区2 (input)] → [D3: BlockResp (output)]
```

- `input` (无 `WRITE` 标志): 驱动写入、设备读取的方向
- `output` (有 `WRITE` 标志): 设备写入、驱动读取的方向

### 5.2 add_dma_bufs 流程

**文件**: `kernel/comps/virtio/src/queue.rs:271-361`

```
add_dma_bufs(inputs, outputs)
  │
  ├── 检查 inputs + outputs 非空
  ├── 检查可用描述符数量足够
  │
  ├── 从 free_head 开始分配描述符
  │   ├── 填充 input 描述符: 设置 addr/len/flags(NEXT)/next
  │   └── 填充 output 描述符: 设置 addr/len/flags(NEXT|WRITE)/next
  │
  ├── 清除最后一个描述符的 NEXT 标志
  ├── 更新 free_head 和 num_used
  ├── 在 head 描述符记录总 output 长度
  │
  ├── 将 head 索引写入 Available Ring 的当前槽位
  ├── 内存屏障 (fence SeqCst)
  ├── 递增 avail_idx 并写入 AvailRing.idx
  └── 内存屏障 (fence SeqCst)

  返回 head (token)
```

### 5.3 pop_used 流程

**文件**: `kernel/comps/virtio/src/queue.rs:399-456`

```
pop_used_with_min_bytes(min_bytes)
  │
  ├── 检查 can_pop() (last_used_idx != used.idx)
  │
  ├── 读取 Used Ring 的当前元素
  │   ├── element.id = 描述符链 head 索引 (即 token)
  │   └── element.len = 设备写入的字节数
  │
  ├── 验证 token 和长度的合法性
  ├── 递增 last_used_idx
  ├── 回收描述符到空闲链表
  │
  └── 返回 (token, len)
```

### 5.4 通知机制

- **驱动通知设备**: 写入 notify 配置空间（`queue.notify()`）
- **设备通知驱动**: 通过中断（MSI-X 或共享 IRQ）

`should_notify()` 检查 Used Ring 的 flags 字段，如果 `VIRTQ_USED_F_NO_NOTIFY` 未设置，则驱动应通知设备。

---

## 6. I/O 请求处理全流程

### 6.1 请求提交路径

```
用户进程 read/write syscall
  │
  ▼
VFS / 文件系统 → BlockDevice::read() / write()  (VmIo trait)
  │
  ▼
impl_block_device.rs: VmIo for dyn BlockDevice
  ├── 创建 BioSegment (DMA 缓冲区)
  ├── 创建 Bio (BioType::Read/Write, 起始扇区, 段列表)
  └── bio.submit_and_wait(block_device)
      │
      ▼
Bio::submit() → BlockDevice::enqueue(submitted_bio)
  │
  ▼
Virtio BlockDevice::enqueue()                   // device.rs:135
  └── BioRequestSingleQueue::enqueue(bio)       // request_queue.rs:59
      ├── 尝试与队列头部请求合并 (同类型 + 扇区连续)
      │   └── request.merge_bio(bio)
      └── 无法合并: 创建新的 BioRequest 并入队
          └── wait_queue.wake_all()             // 唤醒处理线程
```

### 6.2 请求处理路径 (内核线程)

**文件**: `kernel/src/device/registry/block.rs:22-38`

内核在 `init_in_first_kthread` 中为每个 virtio block 设备 spawn 一个专用内核线程：

```rust
let task_fn = move || {
    let virtio_block_device = device_clone.downcast_ref::<VirtIoBlockDevice>().unwrap();
    loop {
        virtio_block_device.handle_requests();  // 阻塞式循环
    }
};
ThreadOptions::new(task_fn).spawn();
```

`handle_requests()` 的流程：

```
BlockDevice::handle_requests()                  // device.rs:116
  │
  ├── queue.dequeue()                           // 阻塞等待 BioRequest
  │   └── BioRequestSingleQueue::dequeue()      // FIFO 出队，可能等待
  │
  └── match request.type_()
      ├── BioType::Read  → device.read(request)
      ├── BioType::Write → device.write(request)
      └── BioType::Flush → device.flush(request)
```

### 6.3 Read 操作详解

**文件**: `kernel/comps/virtio/src/device/block/device.rs:340-405`

```
DeviceInner::read(bio_request)
  │
  ├── id = id_allocator.alloc()                 // 分配请求 ID (可能阻塞)
  │
  ├── 构造 BlockReq { type_: In, sector: start_sector }
  ├── 写入 block_requests DMA 区域 [id * REQ_SIZE]
  ├── sync_to_device()                          // 刷新 DMA 缓冲区到设备可见
  │
  ├── 初始化 BlockResp { status: NotReady }     // 写入 block_responses DMA 区域
  ├── sync_to_device()
  │
  ├── 收集 output 缓冲区:
  │   ├── 各 BioSegment 的 DMA slice (设备将数据写入)
  │   └── resp_slice (设备将响应状态写入)
  │
  ├── loop {
  │   ├── queue.disable_irq().lock()            // 禁用中断并加锁
  │   ├── 检查可用描述符数
  │   ├── queue.add_dma_bufs(&[req_slice], outputs)  // 提交到 virtqueue
  │   │   ├── inputs: [req_slice]               // 1 个 input 描述符 (请求头)
  │   │   └── outputs: [seg1, seg2, ..., resp]  // N+1 个 output 描述符
  │   ├── if queue.should_notify() → queue.notify()  // 通知设备
  │   └── 记录 SubmittedRequest { id, bio_request } 到 submitted_requests
  │ }
  └── return
```

**描述符链布局 (读操作)**:
```
Input 描述符:
  D0: BlockReq { type=In, sector=S }    (driver → device)

Output 描述符:
  D1: BioSegment[0] DMA buffer          (device → driver, 写入读取的数据)
  D2: BioSegment[1] DMA buffer          (device → driver)
  ...
  Dn: BlockResp { status }              (device → driver, 写入操作结果)
```

### 6.4 Write 操作详解

**文件**: `kernel/comps/virtio/src/device/block/device.rs:408-472`

Write 与 Read 的关键区别在于数据缓冲区的方向：

```
DeviceInner::write(bio_request)
  │
  ├── id = id_allocator.alloc()
  ├── 构造 BlockReq { type_: Out, sector: start_sector }
  │
  ├── 收集 input 缓冲区:
  │   ├── req_slice (请求头)
  │   └── 各 BioSegment 的 DMA slice (设备将从中读取数据)
  │
  └── queue.add_dma_bufs(inputs, &[resp_slice])
```

**描述符链布局 (写操作)**:
```
Input 描述符:
  D0: BlockReq { type=Out, sector=S }   (driver → device)
  D1: BioSegment[0] DMA buffer          (driver → device, 包含要写入的数据)
  D2: BioSegment[1] DMA buffer          (driver → device)
  ...

Output 描述符:
  Dn: BlockResp { status }              (device → driver)
```

### 6.5 Flush 操作详解

**文件**: `kernel/comps/virtio/src/device/block/device.rs:476-527`

```
DeviceInner::flush(bio_request)
  │
  ├── 如果设备不支持 FLUSH 特性 → 直接 complete(Complete)
  │
  ├── 构造 BlockReq { type_: Flush, sector }
  └── queue.add_dma_bufs(&[req_slice], &[resp_slice])  // 仅 2 个描述符
```

Flush 操作不需要数据缓冲区，只需请求头和响应。

---

## 7. 中断处理机制

### 7.1 IRQ 注册

在 `DeviceInner::init` 中注册两个回调：

```rust
// device.rs:262-276
transport.register_cfg_callback(Box::new(handle_config_change))?;
transport.register_queue_callback(0, Box::new(handle_irq), false)?;
```

- **PCI Modern**: 通过 MSI-X 分配中断向量
- **PCI Legacy**: 通过 MSI-X 或共享 IRQ
- **MMIO**: 使用共享 IRQ，通过 `MultiplexIrq` 分发

### 7.2 handle_irq 处理流程

**文件**: `kernel/comps/virtio/src/device/block/device.rs:282-333`

```
DeviceInner::handle_irq()
  │
  └── loop {
      ├── queue.pop_used_with_min_bytes(RESP_SIZE)  // 从 Used Ring 取回完成的请求
      │   └── 返回 (token, len)
      │
      ├── 从 submitted_requests 中移除 token 对应的 SubmittedRequest
      │
      ├── 读取响应:
      │   ├── resp_slice.sync_from_device()         // DMA 同步：设备 → CPU
      │   └── 读取 BlockResp.status
      │
      ├── id_allocator.dealloc(id)                  // 释放请求 ID
      │
      ├── 检查响应状态:
      │   ├── 非 Ok → 所有 Bio 设置 IoError 状态并 complete
      │   └── Ok → 继续
      │
      ├── 如果是 Read 操作:
      │   └── 对每个 BioSegment 的 DMA slice 调用 sync_from_device()  // 同步读取的数据
      │
      └── 对每个 Bio 调用 complete(BioStatus::Complete)
          ├── 设置 BioMetadata.status = Complete
          ├── 释放 segments
          ├── 调用完成回调
          └── wake_all() 唤醒等待者
  }
```

### 7.3 ID 分配器的同步机制

**文件**: `kernel/comps/virtio/src/id_alloc.rs`

`SyncIdAlloc` 使用 `WaitQueue` 实现线程安全的 ID 分配：

- `alloc()`: 在任务上下文调用，可能阻塞等待空闲 ID
- `dealloc()`: 在 IRQ 处理程序中调用，释放 ID 并唤醒等待者

这保证了在 virtqueue 满时，请求处理线程会阻塞等待，直到有请求完成并释放 ID。

---

## 8. 块设备抽象层

### 8.1 BlockDevice Trait

**文件**: `kernel/comps/block/src/lib.rs:64-89`

```rust
pub trait BlockDevice: Send + Sync + Any + Debug {
    fn enqueue(&self, bio: SubmittedBio) -> Result<(), BioEnqueueError>;
    fn metadata(&self) -> BlockDeviceMeta;
    fn name(&self) -> &str;
    fn id(&self) -> DeviceId;
    fn is_partition(&self) -> bool { false }
    fn set_partitions(&self, _infos: Vec<Option<PartitionInfo>>) {}
    fn partitions(&self) -> Option<Vec<Arc<dyn BlockDevice>>> { None }
}
```

### 8.2 BioRequestSingleQueue

**文件**: `kernel/comps/block/src/request_queue.rs`

这是一个 FIFO 生产者-消费者队列：

- **生产者** (文件系统等): 调用 `enqueue()` 提交 `SubmittedBio`
- **消费者** (驱动处理线程): 调用 `dequeue()` 获取 `BioRequest`

**合并优化**: 当新提交的 Bio 与队列头部请求类型相同且扇区连续时，会合并到同一个 `BioRequest` 中，减少 I/O 请求次数。

### 8.3 设备注册表

**文件**: `kernel/comps/block/src/lib.rs:122-152`

```rust
static DEVICE_REGISTRY: Mutex<BTreeMap<u32, Arc<dyn BlockDevice>>> = ...;

pub fn register(device: Arc<dyn BlockDevice>) -> Result<(), Error> { ... }
pub fn unregister(id: DeviceId) -> Result<Arc<dyn BlockDevice>, Error> { ... }
pub fn collect_all() -> Vec<Arc<dyn BlockDevice>> { ... }
pub fn lookup(id: DeviceId) -> Option<Arc<dyn BlockDevice>> { ... }
```

### 8.4 分区解析

**文件**: `kernel/comps/block/src/partition.rs`

在 `init_in_first_process` 中，对所有已注册的块设备进行分区解析：

1. 读取 MBR 头部 (LBA 0)
2. 如果是 GPT Protective MBR (type = 0xEE)，转而解析 GPT
3. 否则解析 MBR 分区表
4. 为每个分区创建 `PartitionNode` 并注册到块设备注册表

`PartitionNode` 实现了 `BlockDevice` trait，其 `enqueue` 方法设置 `sid_offset` 后委托给父设备。

### 8.5 设备节点创建

**文件**: `kernel/src/device/registry/block.rs:55-65`

```rust
pub(super) fn init_in_first_process(path_resolver: &PathResolver) -> Result<()> {
    for device in aster_block::collect_all() {
        let device = Arc::new(BlockFile::new(device));
        if let Some(devtmpfs_meta) = device.devtmpfs_meta() {
            add_node(DeviceType::Block, dev_id, &devtmpfs_meta, path_resolver)?;
        }
    }
}
```

这会在 `/dev` 目录下创建设备节点（如 `/dev/vda`, `/dev/vda1`），用户进程可以通过这些节点访问块设备。

---

## 9. 传输层实现

### 9.1 VirtioTransport Trait

**文件**: `kernel/comps/virtio/src/transport/mod.rs:31-110`

```rust
pub trait VirtioTransport: Sync + Send + Debug {
    // 设备相关
    fn device_type(&self) -> VirtioDeviceType;
    fn read_device_features(&self) -> u64;
    fn write_driver_features(&mut self, features: u64) -> Result<()>;
    fn read_device_status(&self) -> DeviceStatus;
    fn write_device_status(&mut self, status: DeviceStatus) -> Result<()>;
    fn finish_init(&mut self);  // 设置 ACKNOWLEDGE | DRIVER | FEATURES_OK | DRIVER_OK

    // 配置空间
    fn device_config_mem(&self) -> Option<IoMem>;
    fn device_config_bar(&self) -> Option<(BarAccess, usize)>;

    // Virtqueue
    fn num_queues(&self) -> u16;
    fn set_queue(&mut self, idx, size, desc, avail, used) -> Result<()>;
    fn max_queue_size(&self, idx: u16) -> Result<u16>;
    fn notify_config(&self, idx: usize) -> ConfigManager<u32>;
    fn is_legacy_version(&self) -> bool;

    // 中断
    fn register_queue_callback(&mut self, index, func, single_interrupt) -> Result<()>;
    fn register_cfg_callback(&mut self, func) -> Result<()>;
}
```

### 9.2 PCI Modern Transport

**文件**: `kernel/comps/virtio/src/transport/pci/device.rs`

`VirtioPciModernTransport` 通过 PCI Capability 发现并映射以下寄存器空间：

| Capability 类型 | 用途 |
|----------------|------|
| CommonCfg | 通用配置：状态、特性、队列选择/大小/地址 |
| NotifyCfg | 通知区域：驱动写入以通知设备有新请求 |
| DeviceCfg | 设备特定配置：如 VirtioBlockConfig |
| IsrCfg | 中断状态寄存器 |

关键操作：
- `set_queue()`: 向 CommonCfg 写入描述符表、Available Ring、Used Ring 的物理地址
- `notify_config()`: 返回 Notify 区域中对应队列的偏移位置
- `register_queue_callback()`: 分配 MSI-X 向量并注册回调

### 9.3 PCI Legacy Transport

**文件**: `kernel/comps/virtio/src/transport/pci/legacy.rs`

Legacy 传输将所有配置映射到 PCI BAR0，布局如下：

```
偏移    字段
0x00    Device Features (R)
0x04    Driver Features (W)
0x08    Queue Address PFN (R/W)
0x0C    Queue Size (R) | Queue Select (R/W)
0x10    Queue Notify (R/W) | Device Status (R/W)
0x13    ISR Status (R)
0x14    Config MSIX Vector | Queue MSIX Vector
0x14/0x18  Device Specific Config (取决于 MSI-X 是否启用)
```

Legacy 的关键区别：
- `set_queue()` 仅需写入 Queue Address PFN（描述符表的页帧号），因为三部分必须物理连续
- `finish_init()` 不设置 `FEATURES_OK`（Legacy 无此状态）
- 仅支持 Feature Bits 0-31

### 9.4 MMIO Transport

**文件**: `kernel/comps/virtio/src/transport/mmio/device.rs`

MMIO 传输通过内存映射寄存器与设备交互，布局定义在 `VirtioMmioLayout` 中。设备配置空间固定在偏移 `0x100~0x200`。

MMIO 使用 `MultiplexIrq` 来多路复用单个 IRQ：
- 同一个 IRQ 可能由队列中断或配置变更中断触发
- 通过读取 `interrupt_status` 寄存器区分中断来源
- 处理完毕后写入 `interrupt_ack` 寄存器确认

---

## 10. 关键代码索引

| 模块 | 文件路径 | 核心内容 |
|------|---------|---------|
| PCI 总线 | `kernel/comps/pci/src/bus.rs` | PciBus, PciDevice/PciDriver trait, register_driver, register_common_device |
| PCI 设备枚举 | `kernel/comps/pci/src/lib.rs` | pci_init, PCI 设备扫描与注册 |
| MMIO 总线 | `kernel/comps/virtio/src/transport/mmio/bus/bus.rs` | MmioBus, MmioDevice/MmioDriver trait, register_driver |
| MMIO 设备发现 | `kernel/comps/virtio/src/transport/mmio/bus/mod.rs` | MMIO 总线初始化，arch::probe_for_device |
| MMIO x86 探测 | `kernel/comps/virtio/src/transport/mmio/bus/arch/x86.rs` | x86_64 MMIO 区域扫描，magic number 验证 |
| MMIO RISC-V 探测 | `kernel/comps/virtio/src/transport/mmio/bus/arch/riscv.rs` | 设备树解析发现 MMIO 设备 |
| 总线错误定义 | `ostd/src/bus.rs` | BusProbeError 枚举 |
| 内核设备抽象 | `kernel/src/device/mod.rs` | Device trait (用户态 I/O) |
| Virtio 初始化 | `kernel/comps/virtio/src/lib.rs` | 组件入口，设备发现循环，特性协商 |
| Block 设备类型定义 | `kernel/comps/virtio/src/device/block/mod.rs` | VirtioBlockConfig, BlockFeatures, ReqType, RespStatus |
| Block 设备驱动 | `kernel/comps/virtio/src/device/block/device.rs` | BlockDevice, DeviceInner, read/write/flush, handle_irq |
| Virtqueue | `kernel/comps/virtio/src/queue.rs` | VirtQueue, add_dma_bufs, pop_used, 描述符管理 |
| 传输层抽象 | `kernel/comps/virtio/src/transport/mod.rs` | VirtioTransport trait, ConfigManager, DeviceStatus |
| PCI Modern | `kernel/comps/virtio/src/transport/pci/device.rs` | VirtioPciModernTransport |
| PCI Legacy | `kernel/comps/virtio/src/transport/pci/legacy.rs` | VirtioPciLegacyTransport |
| PCI 驱动 | `kernel/comps/virtio/src/transport/pci/driver.rs` | VirtioPciDriver, probe, 匹配逻辑 |
| PCI 驱动注册 | `kernel/comps/virtio/src/transport/pci/mod.rs` | virtio_pci_init, VIRTIO_PCI_DRIVER |
| MMIO Transport | `kernel/comps/virtio/src/transport/mmio/device.rs` | VirtioMmioTransport |
| MMIO 驱动 | `kernel/comps/virtio/src/transport/mmio/driver.rs` | VirtioMmioDriver, probe |
| MMIO 驱动注册 | `kernel/comps/virtio/src/transport/mmio/mod.rs` | virtio_mmio_init, VIRTIO_MMIO_DRIVER |
| DMA 缓冲区 | `kernel/comps/virtio/src/dma_buf.rs` | DmaBuf trait |
| ID 分配器 | `kernel/comps/virtio/src/id_alloc.rs` | SyncIdAlloc (阻塞式 ID 分配) |
| 块设备框架 | `kernel/comps/block/src/lib.rs` | BlockDevice trait, 注册表 |
| Bio 数据结构 | `kernel/comps/block/src/bio.rs` | Bio, SubmittedBio, BioSegment, BioMetadata |
| 请求队列 | `kernel/comps/block/src/request_queue.rs` | BioRequestSingleQueue, BioRequest |
| 块设备 VmIo | `kernel/comps/block/src/impl_block_device.rs` | VmIo for dyn BlockDevice |
| 分区解析 | `kernel/comps/block/src/partition.rs` | MBR/GPT 解析, PartitionNode |
| 块设备注册 | `kernel/src/device/registry/block.rs` | 内核线程 spawn, /dev 节点创建 |

---

## 附录：完整 I/O 路径时序图

以一次 Read 操作为例：

```
  用户进程              VFS/FS              Block框架           Virtio-Block驱动         VirtQueue          设备(硬件)
    │                    │                    │                      │                      │                 │
    │  read() syscall    │                    │                      │                      │                 │
    │───────────────────>│                    │                      │                      │                 │
    │                    │  VmIo::read()      │                      │                      │                 │
    │                    │───────────────────>│                      │                      │                 │
    │                    │                    │  创建 Bio(BioType::Read)                     │                 │
    │                    │                    │  Bio::submit_and_wait()                      │                 │
    │                    │                    │  BlockDevice::enqueue(SubmittedBio)          │                 │
    │                    │                    │─────────────────────>│                      │                 │
    │                    │                    │                      │  BioRequestSingleQueue::enqueue()   │                 │
    │                    │                    │                      │  wake_all()          │                 │
    │                    │                    │                      │                      │                 │
    │                    │                    │                      │<───── dequeue() ─────│                 │
    │                    │                    │                      │  (内核线程被唤醒)      │                 │
    │                    │                    │                      │                      │                 │
    │                    │                    │                      │  DeviceInner::read() │                 │
    │                    │                    │                      │  1. alloc ID         │                 │
    │                    │                    │                      │  2. 构造 BlockReq    │                 │
    │                    │                    │                      │  3. DMA sync_to_device                │                 │
    │                    │                    │                      │  4. add_dma_bufs()   │                 │
    │                    │                    │                      │─────────────────────>│                 │
    │                    │                    │                      │                      │  notify         │
    │                    │                    │                      │                      │────────────────>│
    │                    │                    │                      │                      │                 │
    │                    │                    │                      │                      │                 │  处理请求
    │                    │                    │                      │                      │                 │  读取数据
    │                    │                    │                      │                      │                 │  写入响应
    │                    │                    │                      │                      │  <── IRQ ──────│
    │                    │                    │                      │                      │                 │
    │                    │                    │                      │<── handle_irq() ─────│                 │
    │                    │                    │                      │  1. pop_used()       │                 │
    │                    │                    │                      │  2. sync_from_device │                 │
    │                    │                    │                      │  3. 检查 RespStatus  │                 │
    │                    │                    │                      │  4. DMA sync (read)  │                 │
    │                    │                    │                      │  5. bio.complete()   │                 │
    │                    │                    │                      │  6. dealloc ID       │                 │
    │                    │                    │                      │                      │                 │
    │                    │                    │<─── wait_all() 返回 ─│                      │                 │
    │                    │                    │                      │                      │                 │
    │<───────────────────│  返回读取的数据     │                      │                      │                 │
    │                    │                    │                      │                      │                 │
```

