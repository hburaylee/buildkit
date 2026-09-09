# SquashFS 磁盘布局细节（各 Section 内部结构）

> 参考：https://dr-emann.github.io/squashfs/squashfs.html
> 约定：所有整数小端序（little-endian）。metadata（inode/dir/各类 lookup table）都是先切成 **8KiB 一块**的逻辑流，再各自独立压缩成 **metadata block**；data block 走的是不同的打包方式，两者不要混。

---

## 1. Superblock（固定 96 字节，无压缩）

```
Offset  Size  Field
 0x00   u32   magic            0x73717368  ("hsqs")
 0x04   u32   inode_count
 0x08   u32   mod_time
 0x0C   u32   block_size                     ← 4K ~ 1M，必须是 2 的幂
 0x10   u32   frag_count                     ← fragment table 条目数
 0x14   u16   compressor       (1 gzip/2 lzma/3 lzo/4 xz/5 lz4/6 zstd)
 0x16   u16   block_log                      ← log2(block_size)，需与上面一致
 0x18   u16   flags
 0x1A   u16   id_count                       ← UID/GID 表条目数
 0x1C   u16   version_major    (=4)
 0x1E   u16   version_minor    (=0)
 0x20   u64   root_inode                     ← 指向根目录 inode 的 metadata 引用
 0x28   u64   bytes_used
 0x30   u64   id_table_start
 0x38   u64   xattr_table_start   (0xFFFF...FFFF = 不存在)
 0x40   u64   inode_table_start
 0x48   u64   dir_table_start
 0x50   u64   frag_table_start    (0xFFFF...FFFF = 不存在)
 0x58   u64   export_table_start  (0xFFFF...FFFF = 不存在)
                                              总计 96 字节 (0x60)
```

`Inode table` 结束的位置 = `dir_table_start`（各表首尾相接，靠 superblock 里的指针定位，不靠隐式对齐）。

---

## 2. Compression Options（可选，紧跟 Superblock 之后）

只有 `flags & 0x0400` 置位时才存在。它本身就是**一个** metadata block（固定不压缩）：

```
 ┌──────────────┬───────────────────────────────┐
 │ u16 hdr       │  payload (4~8 字节，视压缩器而定) │
 │ (bit15=未压缩) │  例如 XZ: dict_size(u32)+filters(u32) │
 └──────────────┴───────────────────────────────┘
```

LZMA1 永远不允许这一节存在；LZ4 则强制要求存在。

---

## 3. Data blocks & Fragments

文件内容按 `block_size` 切块，逐块独立压缩、顺序落盘；不足一块的“尾巴”（或整个小文件）可选择性地打包进 **fragment block**：

```
File A (3块+尾巴)      File B (2块+尾巴)      File C (< 1 block)
┌───┬───┬───┬─┐        ┌───┬───┬─┐            ┌─┐
│A0 │A1 │A2 │a│        │B0 │B1 │b│            │C│
└───┴───┴───┴─┘        └───┴───┴─┘            └─┘
  │   │   │  └──────────────┐  │  ┌──────────────┘
  ▼   ▼   ▼                 ▼  ▼  ▼
┌───┬───┬───┬───┬───┬─────────────┐
│ A0│ A1│ A2│ B0│ B1│ F=[a|b|C]   │   ← 磁盘上顺序排列，无 header
└───┴───┴───┴───┴───┴─────────────┘
块之间可以有 gap（同一文件内部不允许），F 块被压缩后整体落盘。
```

每个 data block 前面**没有**长度头 —— 长度信息全部记在对应文件的 inode 的 `block_sizes[]` 数组里（bit24 标记是否未压缩）。

---

## 4. Inode Table

### 4.1 物理层：metadata block 流

```
inode_table_start
      │
      ▼
┌─len0─┬────compressed/raw data0────┬─len1─┬───data1───┬─len2─┬── … ──┐
 (u16)         (≤8KiB 解压后)         (u16)                (u16)
```

- 每个 metadata block 前置一个 **u16 长度头**：低 15 位是本块在磁盘上的字节数，最高位(bit15)=1 表示该块**未压缩**。
- inode 之间**紧密排列**，允许跨 metadata block 边界（读取时要拼接两块）。
- 引用一个 inode 用 64 位「metadata 引用」：低 16 位 = 块内偏移，高 48 位 = 该 metadata block 相对 `inode_table_start` 的字节偏移。

### 4.2 逻辑层：Common Inode Header（每个 inode 开头都有）

```
u16 type           (1~14，basic/extended × dir/file/symlink/blkdev/chrdev/fifo/socket)
u16 permissions
u16 uid_idx        → 查 ID Table
u16 gid_idx        → 查 ID Table
u32 mtime
u32 inode_number
```

### 4.3 Basic Directory Inode（header 之后）

```
u32 block_index     ← dir table 里 metadata block 的相对偏移
u32 link_count
u16 file_size        (比真实 listing 大 3 字节，historical reasons)
u16 block_offset     ← 上面那个 metadata block 内的解压偏移
u32 parent_inode
```

`file_size < 4` 表示空目录，dir table 里没有对应 listing。

### 4.4 Extended Directory Inode

```
u32 link_count
u32 file_size            (可达 4GiB)
u32 block_index
u32 parent_inode
u16 index_count           ← 后面跟的 directory index 条目数
u16 block_offset
u32 xattr_index            (0xFFFFFFFF = 无)
── 紧跟 index_count 个 Directory Index 条目（见第 6.1 节） ──
```

### 4.5 Basic File Inode

```
u32   blocks_start    ← 第一个 data block 相对 archive 起始的绝对偏移
u32   frag_index       (0xFFFFFFFF = 不用 fragment)
u32   block_offset     ← 尾巴在 fragment block 内的解压偏移
u32   file_size
u32[] block_sizes      ← ceil/floor(file_size/block_size) 个，每个 bit24=未压缩标记
```

### 4.6 Extended File Inode

```
u64   blocks_start
u64   file_size
u64   sparse           ← 稀疏文件省下的字节数
u32   link_count
u32   frag_index
u32   block_offset
u32   xattr_index
u32[] block_sizes
```

### 4.7 Symlink / Device / FIFO·Socket（简表）

```
Symlink(basic):   u32 link_count, u32 target_size, u8[target_size] target_path
Symlink(ext):     ...同上..., u32 xattr_index

Device(basic):    u32 link_count, u32 dev_number
Device(ext):      ...同上..., u32 xattr_index

FIFO/Socket(basic): u32 link_count
FIFO/Socket(ext):   u32 link_count, u32 xattr_index
```

---

## 5. Directory Table

物理层同样是 metadata block 流（结构与 Inode Table 相同，len 头 + 数据）。逻辑内容按目录分段，每段：

```
┌─────────────── Header (12B) ───────────────┐
│ u32 count        (实际条目数 - 1)             │
│ u32 start        (对应 inode 所在的 metadata │
│                    block，相对 inode_table  │
│                    起始的偏移)                │
│ u32 inode_number (本组条目的“参考”inode号)     │
└──────────────────────────────────────────────┘
        │  最多跟随 256 个 entry，超出则新起一个 header
        ▼
┌────────────── Entry (8B + name) ─────────────┐
│ u16 offset        (inode 在其 metadata block │
│                     内的解压偏移)              │
│ s16 inode_offset  (相对 header.inode_number  │
│                     的差值)                   │
│ u16 type          (basic 类型, 1~7)           │
│ u16 name_size     (真实长度 - 1)               │
│ u8[name_size+1] name  (不含结尾 \0)            │
└────────────────────────────────────────────────┘
        ... 重复 count+1 次 ...

条目按名字 ASCII 排序；inode 块变化 或 offset 差值超出 s16 范围时，
必须切出新的 Header + Entry 组。
```

### 5.1 Directory Index（仅 Extended Directory Inode 附带）

紧跟在 extended dir inode 结构体之后，一共 `index_count` 个：

```
u32 index      ← 从第一个 dir header 开始算起的字节偏移（假设所有
                  metadata block 解压后连续摆放）
u32 start      ← 该 header 所在 metadata block 相对 dir_table_start 的偏移
u32 name_size  ← 该 header 后第一个 entry 名字长度 - 1
u8[] name      ← 该 entry 的名字
```

作用：二分/跳跃定位到某个 metadata block，避免线性扫描整个 listing。

---

## 6. Fragment Table（两级查找结构）

这是你在 issue #3647 里重点关注的部分。整体是标准的 **lookup table** 套路：**位置索引数组（未压缩）→ metadata block（压缩，存 entry 数组）**。

```
Superblock.frag_table_start
        │
        ▼
┌─────────────────────────────────────────────┐
│  u64[]  location_list   (未压缩，无 header)    │  ← Level 1：定位数组
│  block_count = ceil(frag_count * 16 / 8192)  │
│  loc[0], loc[1], loc[2], ...                 │
└───────┬───────────────┬───────────────┬─────┘
        │               │               │
        ▼               ▼               ▼
   ┌─len─┬──data──┐ ┌─len─┬──data──┐ ┌─len─┬──data──┐   ← Level 2：
   │metadata block│ │metadata block│ │metadata block│      每块最多
   │ 最多512条目   │ │  最多512条目  │ │  最多512条目  │      8192/16=512 条
   └───────────────┘ └───────────────┘ └───────────────┘

每个 metadata block 内，entry 结构 16 字节：
   u64 start    ← fragment block 在 archive 内的绝对偏移
   u32 size     ← 该 fragment block 在盘上的大小；bit24=1 表示未压缩存储
   u32 unused   ← 应为 0（Linux 内核忽略，不能复用）
```

**定位一个 frag_index 的过程**（`entry_size=16`）：

```
meta_index = floor(frag_index * 16 / 8192)     → 查 location_list[meta_index] 拿到 metadata block 磁盘位置
offset     = (frag_index * 16) % 8192          → 该 metadata block 解压后的字节偏移
读取该 offset 处 16 字节 = {start, size, unused}
```

拿到 `start/size` 后再去 `start` 处读整个 fragment block、解压，最后用文件 inode 里的 `block_offset` 定位尾巴数据。

---

## 7. Export Table（NFS 用，可选，两级结构同上）

```
Superblock.export_table_start
        │
        ▼
   u64[] location_list  (未压缩)， block_count = ceil(inode_count * 8 / 8192)
        │
        ▼
┌─len─┬──────data (每块最多 8192/8=1024 条 u64)──────┐
│ inode_ref[0]  inode_ref[1]  ...  inode_ref[1023]   │
└──────────────────────────────────────────────────┘

index = inode_number - 1   (inode 0 保留不用)
每个 inode_ref 就是一个 64 位 metadata 引用，直接指向 Inode Table 里的具体 inode。
```

---

## 8. ID (UID/GID) Table（两级结构同上，entry 更简单）

```
Superblock.id_table_start
        │
        ▼
   u64[] location_list， block_count = ceil(id_count * 4 / 8192)
        │
        ▼
┌─len─┬──────data (每块最多 8192/4=2048 条 u32)──────┐
│ id[0]   id[1]   id[2]   ...   id[2047]             │
└──────────────────────────────────────────────────┘

inode 里存的 uid_idx/gid_idx 直接当 index 查这个数组即可拿到真实 32bit UID/GID。
```

---

## 9. Extended Attribute (Xattr) Table

这是最复杂的一节，比其它 lookup table 多了一层：**未压缩的 header 结构 + 位置数组**，外加**独立的 kv 数据流**。

```
Superblock.xattr_table_start（绝对偏移，指向下面这个结构，整体未压缩）
        │
        ▼
┌───────────────────────────────────────────────┐
│ u64   kv_start     ← 第一个 kv metadata block   │
│                      的绝对磁盘位置              │
│ u32   count        ← lookup table 条目总数      │
│ u32   unused       ← 应为0（同样被内核忽略）      │
│ u64[] locations    ← lookup table 各 metadata   │
│                      block 的绝对磁盘位置        │
│       (共 ceil(count*16/8192) 个)               │
└───────────────┬─────────────────┬───────────────┘
                │                 │
                ▼                 ▼
      ┌─len─┬──lookup metadata block──┐   (每块最多 512 条，16B/条)
      │ xattr_ref(u64) count(u32) size(u32) │  ← 每条对应一个 inode 的
      │ ......                              │     "一组 xattr" 描述符
      └──────────────────────────────────────┘

inode.xattr_index 定位过程：
   block_idx = floor(xattr_index / 512)      → locations[block_idx]
   offset    = (xattr_index * 16) % 8192     → 读出 {xattr_ref, count, size}

xattr_ref 本身又是一个 metadata 引用（block位置<<16 | 块内偏移），
指向下面这条真正的 Key/Value 数据流（从 kv_start 开始的 metadata block 序列）：

      ▼
┌─len─┬────────── kv metadata block ──────────┐
│ Key:  u16 type(prefix, bit8=out-of-line)     │
│       u16 name_size(-1)  u8[] name           │
│ Value:u32 value_size                         │
│       u8[value_size] value                   │
│       (若 out-of-line: value_size 恒=8，     │
│        value 内容是一个 64bit metadata 引用， │
│        指向别处第一次出现的 value)              │
│ ...重复 count 次，总大小=size...              │
└────────────────────────────────────────────────┘
```

要点：

- **value 去重**：同一个 value 第一次出现时 inline 存储，之后所有引用同一 value 的 key 都用 out-of-line 引用（8 字节 metadata 引用）回指第一次的位置，省空间。
- lookup table 条目本身也会被多个 inode 共享——如果两个 inode 的 xattr 集合完全一致，`xattr_index` 是同一个值。

---

## 各表关系速查

```
inode.uid_idx/gid_idx ───────────────► ID Table
inode.xattr_index ────────────────────► Xattr lookup table ──► KV metadata blocks
dir_inode.block_index/block_offset ───► Directory Table（某个 metadata block+偏移）
dir_entry.offset (+header.start) ─────► Inode Table（某个 metadata block+偏移）
file_inode.frag_index ─────────────────► Fragment Table ──► Fragment data block
export_table[inode_number-1] ─────────► Inode Table（NFS 用）
```

---
---

# Linux v7.0 内核 Squashfs 实现分析

> 基于本仓库 `fs/squashfs/` 源码（Squashfs 4.0，约 6600 行）的分析。

## 一、总体定位

Squashfs 是一个**只读、压缩**的文件系统（`sb->s_flags |= SB_RDONLY`，`super.c`），目标是高压缩率与低内存开销，典型用途是 live CD、嵌入式 rootfs、固件镜像。整个文件系统没有写路径，所有设计都围绕"如何高效地找到并解压某一块数据"展开。

源文件分工：

| 文件 | 职责 |
|---|---|
| `super.c` | 挂载、读超级块、注册文件系统 |
| `block.c` | 读盘 + 解压一个数据块/元数据块的最底层入口 |
| `cache.c` | 元数据/fragment 块缓存；`squashfs_read_metadata` |
| `inode.c` | 解析磁盘 inode，填充 VFS inode |
| `file.c` | 常规文件读取：block list 索引缓存、read_folio/readahead、SEEK_HOLE |
| `file_cache.c` / `file_direct.c` | 两种数据块读取策略（经中间缓冲 vs 直接解入 page cache） |
| `dir.c` / `namei.c` | readdir / 文件名查找 |
| `fragment.c` / `id.c` / `export.c` / `xattr*.c` | 尾部碎片、uid/gid 表、NFS 导出、xattr |
| `decompressor*.c` | 解压算法与并发框架 |
| `page_actor.c/h` | 输出缓冲抽象（页数组或 kmalloc 缓冲） |

## 二、磁盘格式（`squashfs_fs.h`）

镜像布局从低地址到高地址：

```
superblock(60B) → [压缩选项] → 数据块 + fragment 块 ……
→ inode 表 → 目录表 → fragment 索引表 → inode lookup 表 → id 表 → xattr id 表
```

`super.c` 挂载时正是按这个顺序用各表起始地址互相做合法性校验（如 `directory_table > next_table` 则拒绝挂载）。

**两类基本块：**

1. **数据块**：文件内容按 `block_size`（默认 128 KiB，最大 1 MiB）切分压缩；每个块压缩后的大小记录在 inode 内的 block list 中；压缩后若反而变大，则存原始数据并在长度字段置位（数据块用 bit 24，元数据块用 bit 15）。
2. **元数据块**：inode、目录项、id 表、fragment 表等都打包进 8 KiB（`SQUASHFS_METADATA_SIZE`）的压缩块，块前有 2 字节长度头。元数据的位置一律用 **`<块起始地址, 解压后偏移>`** 二元组寻址。

超级块 `struct squashfs_super_block` 记录 magic、块大小、inode/fragment/id 数量、压缩算法编号（zlib=1/lzma/lzo/xz/lz4/zstd）以及上述各表的起始地址。

## 三、核心抽象

### 1. inode 号 = 48 位 `<block, offset>`

`squashfs_fs.h` 中 `SQUASHFS_INODE_BLK/SQUASHFS_INODE_OFFSET` 把 inode 号解码为"inode 表内压缩元数据块的偏移 + 块内偏移"。也就是说 **inode 号不是序号，而是磁盘位置的编码**，普通路径查找无需任何映射表就能直达 inode（只有 NFS 导出才用 inode lookup 表做"序号 → 位置"转换，见 `export.c`）。

### 2. `squashfs_read_metadata`：元数据读取的统一入口（`cache.c`）

给定 `<block, offset>` 和长度，它循环地：从 metadata cache 取一个解压后的 8 KiB 块 → 拷贝所需字节 → 若读到块尾则用该块的 `next_index` 跳到下一个压缩块继续。数据可以跨块，块地址自动推进。所有上层（inode、目录、xattr、id、fragment 表）都走这个函数。

### 3. `squashfs_read_data`：读盘+解压总入口（`block.c`）

- **length == 0** 表示元数据块：先读 2 字节长度头，取出压缩大小和是否压缩标志；
- **length != 0** 表示数据块：大小已由调用方（block list / fragment 表）给出。
- 读盘用 `squashfs_bio_read` 构造 bio（按设备块大小对齐）。这里有一个较新的优化：当设备块大小 == PAGE_SIZE 时，用一个伪 inode 的 address_space（`msblk->cache_mapping`）**缓存压缩块本身**，避免重复读盘；`CONFIG_SQUASHFS_COMP_CACHE_FULL` 下缓存全部压缩块（Kconfig 里给了 fio 数据：约 107MB/s → 291MB/s）。
- 解压走 `msblk->thread_ops->decompress(...)`；未压缩块直接 `copy_bio_to_actor` 拷贝。输出统一写入 `squashfs_page_actor`。

### 4. page_actor：输出缓冲抽象

解压结果可以直接写入 page cache 的页面（`file_direct.c` 模式），也可以写入 kmalloc 的中间缓冲再 memcpy（`file_cache.c` 模式）。actor 提供 `first_page/next_page/finish_page` 迭代接口，解压算法只面向这个接口编程。

## 四、挂载流程（`squashfs_fill_super`）

1. 读超级块，校验 magic、版本（仅支持 4.x）、`bytes_used` 不越界、block_size/block_log 一致、根 inode 合法；
2. 按 `compression` 字段查解压算法表（`decompressor.c`，未编译的算法只有名字、`supported=0`，挂载时报错）；
3. 建三个缓存：metadata 缓存（8 × 8 KiB）、data read_page 缓存（`CONFIG_SQUASHFS_FILE_CACHE` 时按解压线程数分配）、fragment 缓存（默认 3 个块）；
4. `squashfs_decompressor_setup` 创建解压流（含读取可选的压缩参数块）；
5. 依次把 xattr id 表、id 表、inode lookup 表、fragment 索引表的**二级索引**（未压缩的 u64 数组）读入内存——这些表本身存在压缩元数据块里，但二级索引很小，挂载时全部载入，之后单表访问只需一次元数据读；
6. 读根 inode，`d_make_root` 建根 dentry。

## 五、inode 实现（`inode.c`）

`squashfs_read_inode` 先读 16 字节的 `squashfs_base_inode`（type/mode/uid 索引/gid 索引/mtime/inode 序号），再按 14 种类型分支解析。类型设计完全为压缩率服务：

- 每种文件类型一个紧凑结构体（reg、dir、symlink、dev、ipc）；
- 常规文件和目录各有"短/长"两版：`REG_TYPE`（32 位 start_block/file_size，无 nlink/xattr）与 `LREG_TYPE`（64 位、含 sparse/nlink/xattr），`DIR/LDIR` 同理；
- uid/gid 只存 **id 表索引**（16 位），真实 32 位 uid/gid 由 `id.c` 的 `squashfs_get_id` 查表换算，大量文件共享少数 uid 时非常省空间。

常规文件 inode 中关键字段：`start_block`（第一个数据块位置）、`fragment`/`offset`（尾部碎片索引及片内偏移）、紧随结构体之后的 `block_list[]`（每个数据块的压缩后大小，本身也在压缩元数据块内）。解析后这些位置被记入 `squashfs_inode_info`（`squashfs_fs_i.h`），VFS inode 由 `squashfs_inode_cachep` slab 分配。

## 六、文件数据读取（`file.c` + `file_cache.c`/`file_direct.c`）

**基本路径**（`squashfs_read_folio`）：页索引换算成数据块索引 → `read_blocklist` 取该块压缩大小 → 大小为 0 是稀疏块（清零即可）→ 否则 `squashfs_readpage_block` 解压；文件最后一个不完整块若配了 fragment，则从 fragment 缓存取解压后的碎片块并按 `fragment_offset` 截取。

**大文件的 block list 索引缓存（meta_index）**：block list 是顺序存储的，直接定位第 N 块需要从 inode 起累加所有块大小。为此 `file.c` 实现了 16 KiB 的内存索引缓存：8 个槽、每槽 127 个条目，条目间距 `skip` 随文件增大而增大（受元数据缓存槽数限制）。`fill_meta_index` 增量地把"块索引 → 磁盘位置"映射填入缓存，之后读大文件只需从最近的缓存条目开始累加。文件头注释说明该机制可支撑 128 KiB 块下的 1.75 TiB 文件。

**两种读法**（编译期二选一，也可都编入由配置决定）：

- `file_cache.c`：经 `read_page` 缓存解压再 `squashfs_copy_cache` 拷入 page cache；一个 128 KiB 数据块解压后会顺带填满覆盖的所有页；
- `file_direct.c`：先 `grab_cache_page_nowait` 抓齐该数据块覆盖的全部页，构造 page actor **直接解压进 page cache**，省一次 memcpy 和缓冲锁竞争。

`squashfs_readahead` 实现批量预读，按数据块边界对齐展开 readahead 区间；`squashfs_llseek` 借助 block list（长度为 0 即洞）实现 `SEEK_HOLE/SEEK_DATA`，一次最多扫描 1024 个索引（`SQUASHFS_SCAN_INDEXES`）。

## 七、目录（`dir.c` + `namei.c`）

`namei.c` 头部注释描述了目录格式：目录不是简单的条目列表，而是**两级结构**——`squashfs_dir_header`（携带共享的 `start_block` 和基准 inode 号）+ 若干 `squashfs_dir_entry`（只存相对偏移、相对 inode 号增量、类型、名字）。同一 inode 元数据块内的条目共享一个 header，压缩率更高。

两个实现细节：

- **"." 和 ".." 不存盘**，readdir 时凭空构造（`..` 的 inode 号来自目录 inode 里存的 `parent_inode`，这也是 `export.c` 里 `get_parent` 的依据）。因此外部 f_pos 比盘上偏移大 3。
- **目录索引**（`LDIR_TYPE` 携带 `squashfs_dir_index` 数组）：每个元数据块存一条"该块第一个条目的名字 + 块位置"。`squashfs_lookup` 先线性扫索引（目录按字典序排序），找到名字刚好大于目标名的索引项，从而保证**一次查找最多只需解压一个元数据块**；readdir 则用 `get_dir_index_using_offset` 按 f_pos 跳过大目录的前部。

查找命中后：`ino = SQUASHFS_MKINODE(header.start_block, entry.offset)`，交给 `squashfs_iget`（`iget_locked` + `squashfs_read_inode`）。

## 八、解压框架（两层解耦）

**算法层** `struct squashfs_decompressor`（`decompressor.h`）：每种算法一个 wrapper（`zlib/lzo/xz/lz4/zstd_wrapper.c`），提供 `init/free/decompress/comp_opts`。以 `zstd_wrapper.c` 为例：`init` 按块大小算好 workspace 并 vmalloc；`decompress` 从 bio 的 bvec 逐段取输入、从 page actor 逐页取输出，流式调用 `zstd_decompress_stream`。LZMA 只登记名字，始终不支持。

**并发层** `struct squashfs_decompressor_thread_ops`（`squashfs.h`）：三种实现，编译期选择或用挂载参数 `threads=single|multi|percpu|N` 指定（`super.c` 的参数解析）：

- `decompressor_single.c`：单实例 + mutex 串行，内存最省；
- `decompressor_multi.c`：解压实例池，按需动态创建，上限 `num_online_cpus()*2`，并发读压力大时性能好；
- `decompressor_multi_percpu.c`：每 CPU 一个实例 + local_lock，无全局锁竞争。

## 九、其余子系统

- **fragment（尾部打包）**：所有文件末尾不足一个块的部分按顺序打包进共享的 fragment 块（压缩），inode 记录 fragment 索引和片内偏移；fragment 块经 `fragment_cache` 缓存（默认 3 个），`fragment.c` 通过挂载时载入的二级索引表定位。
- **id 表**：uid/gid 去重存储，`id.c`。
- **xattr**（`xattr.c`/`xattr_id.c`）：xattr 名值对存 xattr 表（元数据块），每个 inode 存的是 xattr id 表里的索引（含计数、总大小）；支持 user/trusted/security 前缀，值可外置（`XATTR_VALUE_OOL`）。
- **NFS 导出**（`export.c`）：仅当镜像带 lookup 表时启用，filehandle → inode 序号 → 查表得到 `<block, offset>` → `squashfs_iget`。
- **错误处理**：读失败打 `ERROR`；挂载参数 `errors=panic` 时直接 panic（`block.c` 末尾），默认 continue。

## 十、函数调用树（ASCII）

### 1. 挂载

```text
init_squashfs_fs                       [模块初始化, super.c]
└── register_filesystem(squashfs_fs_type)

SYSCALL_DEFINE5(mount, ...)                            [fs/namespace.c:4338]
└── do_mount                                           [fs/namespace.c:4163]
    └── path_mount                                     [fs/namespace.c:4084]
        └── do_new_mount                               [fs/namespace.c:3792]
            ├── get_fs_type("squashfs")                [fs/filesystems.c:274]
            ├── fc = fs_context_for_mount              [fs/fs_context.c:306]
            │   └── alloc_fs_context                   [fs/fs_context.c:258]
            │       └── squashfs_init_fs_context(*fc)  [fs/squashfs/super.c:550]
            │           ├── fc->fs_private = opts
            │           └── fc->ops = &squashfs_context_ops
            └── do_new_mount_fc(fc)                    [fs/namespace.c:3759]
                └── fc_mount                           [fs/namespace.c:1191]
                    └── vfs_get_tree                   [fs/super.c:1743]
                        └── squashfs_get_tree          [fs/squashfs/super.c:494]
                            └── get_tree_bdev(fc, squashfs_fill_super)
                                └── squashfs_fill_super   [fs/squashfs/super.c:180]
                                    ├── sb_min_blocksize
                                    ├── squashfs_read_table            // 读 96B squashfs_super_block
                                    ├── supported_squashfs_filesystem
                                    │   └── squashfs_lookup_decompressor
                                    ├── squashfs_cache_init            // "metadata" 8 x 8KiB
                                    ├── squashfs_cache_init            // "data" read_page (FILE_CACHE 时)
                                    ├── squashfs_decompressor_setup    [fs/squashfs/decompressor.c]
                                    │   ├── get_comp_opts
                                    │   │   └── squashfs_read_data     // 读压缩参数块(可选)
                                    │   └── thread_ops->create         // single/multi/percpu
                                    │       └── decompressor->init     // 如 zstd_init, 分配 workspace
                                    ├── squashfs_read_xattr_id_table                                         ─┐
                                    ├── squashfs_read_id_index_table                                         ─┤
                                    ├── squashfs_read_inode_lookup_table                                     ─┤ 都经 squashfs_read_table
                                    ├── squashfs_cache_init // "fragment" 3 x block_size (fragments != 0 时)  │
                                    ├── squashfs_read_fragment_index_table // 二级索引常驻内存               ─┘
                                    ├── root = new_inode(sb)
                                    ├── squashfs_read_inode(root, root_ino)
                                    └── d_make_root(root)
```

### 2. 路径查找 `squashfs_lookup`（namei.c）

```text
SYSCALL_DEFINE5(statx, ...)                               [fs/stat.c:804]
└── do_statx                                              [fs/stat.c:744]
    └── vfs_statx                                         [fs/stat.c:341]
        └── filename_lookup                               [fs/namei.c:2831]
            └── path_lookupat                             [fs/namei.c:2798]
                ├── path_init                             [fs/namei.c:2671]
                ├── link_path_walk                        [fs/namei.c:2575]
                │   └── walk_component                    [fs/namei.c:2262]   // 非最后一级
                │       ├── lookup_fast                   [fs/namei.c:1839]
                │       └── lookup_slow                   [fs/namei.c:1926]
                │           └── __lookup_slow             [fs/namei.c:1889]
                │               └── dir->d_inode->i_op->lookup(inode, dentry, flags)
                │                   └── squashfs_lookup   [fs/squashfs/namei.c:120]
                └── lookup_last                           [fs/namei.c:2779]
                    └── walk_component                // 最后一级, 同样经 lookup_fast/lookup_slow

squashfs_lookup(dir, dentry, flags)                       [fs/squashfs/namei.c:120]
├── get_dir_index_using_name                          // 扫目录索引, 定位元数据块
│   └── squashfs_read_metadata ×2                     // 每项: dir_index + name
├── while (length < i_size_read(dir))                 // 扫目录条目
│   ├── squashfs_read_metadata(&dirh)                 // squashfs_dir_header
│   └── while (dir_count--)
│       ├── squashfs_read_metadata(dire)              // squashfs_dir_entry
│       ├── squashfs_read_metadata(dire->name)
│       └── squashfs_iget(sb, SQUASHFS_MKINODE(blk, off), ino_num)   // [名字命中] 见第 3 节
└── d_splice_alias(inode, dentry)
```

### 3. inode 读取 `squashfs_iget`（inode.c）

```text
squashfs_iget(sb, ino, ino_number)                          [fs/squashfs/inode.c:79]
├── iget_locked(sb, ino_number)                             // VFS inode 缓存; 非 I_NEW 直接返回
└── [I_NEW] squashfs_read_inode(inode, ino)                 [fs/squashfs/inode.c:107]
    ├── squashfs_read_metadata                              // 读 16B squashfs_base_inode
    ├── squashfs_new_inode                                  [fs/squashfs/inode.c:44]
    │   └── squashfs_get_id ×2 (uid/gid)                    [fs/squashfs/id.c:33]
    │       └── squashfs_read_metadata                      // 查 id 表
    ├── switch (inode_type)                                 // 14 种类型
    │   ├── REG / LREG:
    │   │   ├── squashfs_read_metadata                      //   文件 inode 主体
    │   │   └── [有 fragment] squashfs_frag_lookup          [fs/squashfs/fragment.c:35]
    │   │       └── squashfs_read_metadata                  // 查 fragment 表项
    │   ├── DIR / LDIR: squashfs_read_metadata              // 目录 inode 主体
    │   ├── SYMLINK / LSYMLINK: squashfs_read_metadata      // 符号链接 inode 主体
    │   │   └── [LSYMLINK] squashfs_read_metadata ×2        // 链接目标 + xattr id
    │   ├── DEV (BLK/CHR 及长格式): squashfs_read_metadata  // 设备 inode 主体
    │   └── IPC (FIFO/SOCKET 及长格式): squashfs_read_metadata  // FIFO/socket inode 主体
    └── [有 xattr] squashfs_xattr_lookup                    [fs/squashfs/xattr_id.c:29]
        └── squashfs_read_metadata                          // 查 xattr id 表
```

### 4. 元数据读取公共路径 `squashfs_read_metadata`（cache.c）

上面所有 `squashfs_read_metadata` 展开后都是这棵树：

```text
squashfs_read_metadata(sb, buffer, &block, &offset, length)
└── while (length > 0)                       // 可能跨元数据块
    ├── squashfs_cache_get(block_cache, block)
    │   ├── [命中] refcount++
    │   │   └── [别人正在解压] wait_event(entry->wait_queue, !pending)
    │   └── [未命中] round-robin 选 refcount==0 的槽
    │       └── squashfs_read_data(block, length=0, ...)   // 见第 6 节
    ├── squashfs_copy_data                   // 从缓存条目拷出所需字节
    │   [块读完] block = entry->next_index; offset = 0
    └── squashfs_cache_put                   // refcount--, 唤醒等待者
```

### 5. 文件数据读取（file.c）

```text
read(2)
└── generic_file_read_iter
    └── filemap_read → page cache 未命中
        ├── squashfs_readahead               [a_ops.readahead]
        │   ├── readahead_expand             // 对齐到 block_size 边界
        │   ├── [末块且有 fragment] squashfs_readahead_fragment
        │   │   ├── squashfs_get_fragment    //   → squashfs_cache_get(fragment_cache)
        │   │   └── squashfs_copy_data → 逐页填充
        │   └── [普通块]
        │       ├── read_blocklist           // 见下
        │       ├── squashfs_page_actor_init_special
        │       └── squashfs_read_data       // 解压直接进 page cache
        │
        └── squashfs_read_folio              [a_ops.read_folio]
            ├── read_blocklist(inode, index)
            │   └── read_blocklist_ptrs
            │       ├── fill_meta_index      // 大文件索引缓存(8 槽 x 127 项)
            │       │   ├── calculate_skip
            │       │   ├── locate_meta_index / empty_meta_index
            │       │   └── read_indexes     // 累加 block_list
            │       │       └── squashfs_read_metadata
            │       └── squashfs_read_metadata   // 读目标块的压缩大小
            │
            ├── [size==0 稀疏块] squashfs_readpage_sparse
            │   └── squashfs_copy_cache(folio, buffer=NULL)   // 清零
            │
            ├── [普通数据块] squashfs_readpage_block   // 二选一实现
            │   ├── file_direct.c:
            │   │   ├── grab_cache_page_nowait ×N      // 抓齐该块覆盖的页
            │   │   ├── squashfs_page_actor_init_special
            │   │   ├── squashfs_read_data             // 直接解压进 page cache
            │   │   └── SetPageUptodate ×N + unlock_page ×N
            │   └── file_cache.c:
            │       ├── squashfs_get_datablock         // read_page 缓存
            │       │   └── squashfs_cache_get → squashfs_read_data
            │       └── squashfs_copy_cache            // memcpy 进 page cache
            │
            └── [文件尾块在 fragment 中] squashfs_readpage_fragment
                ├── squashfs_get_fragment
                └── squashfs_copy_cache(folio, buffer, fragment_offset)
```

### 6. 读盘 + 解压总入口 `squashfs_read_data`（block.c）

```text
squashfs_read_data(sb, index, length, next_index, output)
├── [length==0 元数据块]
│   ├── squashfs_bio_read(index, 2)          // 先读 2 字节长度头
│   └── 解析: compressed = !(len & bit15)
├── [length!=0 数据块]
│   └── compressed = !(len & bit24)          // 大小来自 block list/fragment 表
│
├── squashfs_bio_read(index, length)
│   ├── 按 devblksize 对齐, 构造 bio
│   ├── squashfs_get_cache_page(cache_mapping)   // 压缩块页缓存(devblk==PAGE_SIZE 时)
│   └── squashfs_bio_read_cached                 // 只提交未缓存页的 bio,
│       │                                        // 顺带缓存头/尾部分覆盖页
│       └── submit_bio_wait                      // (或纯 submit_bio_wait)
│
├── [压缩块] thread_ops->decompress(msblk, bio, offset, length, output)
│   ├── single:  mutex_lock → decompressor->decompress → mutex_unlock
│   ├── multi:   get_decomp_stream(实例池, ≤ cpu*2)
│   │            → decompressor->decompress → put_decomp_stream
│   └── percpu:  local_lock → this_cpu_ptr → decompressor->decompress
│       └── 以 zstd_uncompress 为例            [zstd_wrapper.c]
│           ├── zstd_init_dstream
│           ├── 输入: bio_next_segment/bvec_virt 逐段喂入
│           ├── 输出: squashfs_first_page/next_page 逐页写出 (page actor)
│           └── zstd_decompress_stream (循环)
│
└── [未压缩块] copy_bio_to_actor               // bio → page actor 直接 memcpy
```

### 7. readdir 与 xattr（补充）

```text
getdents(2)
└── squashfs_readdir                          [dir.c]
    ├── dir_emit(".") / dir_emit("..")        // 不存盘, 现场构造
    ├── get_dir_index_using_offset            // 按 f_pos 查目录索引
    │   └── squashfs_read_metadata
    └── while: squashfs_read_metadata(dirh/dire/name) → dir_emit

getxattr/listxattr
└── squashfs_xattr_get / squashfs_listxattr   [xattr.c]
    └── squashfs_read_metadata ×N             // 从 xattr 表读 name/value
```

## 十一、总结

Squashfs 的实现核心是三个思想的叠加：

1. **一切皆压缩元数据块，用 `<block, offset>` 二元组寻址**；
2. **索引表分层**——小的二级索引常驻内存，大索引（block list、目录索引、meta_index）按需建立并缓存；
3. **解压的算法与并发策略各自抽象，可按镜像和挂载参数组合**。

贯穿所有调用树的两个唯一入口：`squashfs_read_metadata`（全部元数据访问）和 `squashfs_read_data`（所有"读盘 + 解压"）；解压输出端统一是 page actor，因此算法层（zstd/zlib/...）、并发层（single/multi/percpu）、输出去向（中间缓冲 vs page cache）三者完全解耦。

