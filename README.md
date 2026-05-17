# opencode-centos7

在 CentOS 7 / RHEL 7 上运行现代版本的 OpenCode。

## 问题背景

CentOS 7 默认的 glibc 版本是 2.17（2012 年发布），而现代软件（如 OpenCode）通常需要 glibc 2.31+。直接运行会报错：

```
opencode: /usr/lib64/libc.so.6: version `GLIBC_2.31' not found
```

## 解决方案

本项目采用以下方案：

1. **自带 glibc**：在用户目录编译安装 glibc 2.31，不修改系统库
2. **PatchELF**：运行时动态修改 opencode 二进制的 interpreter，指向自定义 glibc
3. **启动脚本**：自动设置环境变量，开箱即用

## 快速开始

### 一键安装

```bash
bash install-block.sh
```

### 指定安装目录

```bash
OPENCODE_INSTALL_DIR=$HOME/.opencode bash install-block.sh
```

### 使用方法

```bash
# 运行 OpenCode
~/.opencode/bin/opencode

# 添加到 PATH（推荐）
echo 'export PATH=$HOME/.opencode/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
opencode
```

## 目录结构

### 源码结构

```
my_install/
├── common.sh              # 公共函数库（日志输出）
├── install-block.sh       # 主安装入口
├── scripts/
│   ├── 01-check-deps.sh   # 检查系统依赖
│   ├── 02-build-gcc.sh    # 编译 GCC 9.5.0
│   ├── 03-build-glibc.sh  # 编译 glibc 2.31
│   ├── 04-build-patchelf.sh   # 编译 patchelf
│   ├── 05-install-opencode.sh # 安装并备份 opencode
│   └── 06-create-launcher.sh  # 生成启动脚本
└── deps/                  # 源码和编译目录（安装完成后可删除，但删除后无法重新运行安装脚本进行验证/修复）
```

### 安装后结构

```
~/.opencode/
├── bin/
│   ├── opencode           # 启动脚本（入口）
│   └── opencode.bak       # 原始 opencode 备份
└── gnu/                   # 自定义 glibc 2.31 + GCC 运行库
    ├── bin/
    │   └── patchelf
    ├── lib/
    │   ├── ld-linux-x86-64.so.2  # glibc loader
    │   ├── libc.so.6
    │   └── ...
    └── lib64/
        └── libgcc_s.so.1
```

## 安装流程

`install-block.sh` 依次执行以下脚本：

| 步骤 | 脚本 | 说明 |
|------|------|------|
| 1 | `01-check-deps.sh` | 检查系统依赖（GCC、devtoolset 等） |
| 2 | `02-build-gcc.sh` | 编译 GCC 9.5.0（支持 C++17） |
| 3 | `03-build-glibc.sh` | 编译 glibc 2.31 |
| 4 | `04-build-patchelf.sh` | 编译 patchelf |
| 5 | `05-install-opencode.sh` | 下载官方 opencode 并备份为 `opencode.bak` |
| 6 | `06-create-launcher.sh` | 生成启动脚本（包含完整 launcher 逻辑） |

## 编译时间

首次安装需要编译 GCC 和 glibc，大约需要 **1-2 小时**：
- GCC 编译：30-60 分钟
- glibc 编译：30-60 分钟
- patchelf 编译：1-2 分钟

建议后台运行：
```bash
nohup bash install-block.sh > install.log 2>&1 &
tail -f install.log
```

## 迁移与备份

### 迁移到新机器

只需复制以下文件到新机器即可运行安装：

```
my_install/
├── common.sh
├── install-block.sh
└── scripts/
```

**注意**：`launcher.sh` 不需要复制，其内容已嵌入到 `06-create-launcher.sh` 中。

### 移动安装目录

整个安装目录可以移动到任何位置，只要保持内部结构不变。

```bash
# 移动到另一个目录
mv ~/.opencode ~/my-opencode

# 运行
~/my-opencode/bin/opencode
```

**注意**：移动后直接运行新位置的启动脚本即可，无需重新安装。

### 备份与恢复

```bash
# 备份
tar -czf opencode-backup.tar.gz ~/.opencode

# 恢复
tar -xzf opencode-backup.tar.gz -C ~/
```

## 卸载

```bash
rm -rf ~/.opencode
```

## 技术细节

### Patch 原理

本方案采用**运行时动态 patch**策略：

1. **安装时**（`05-install-opencode.sh`）：
   - 下载官方 opencode 二进制
   - 备份为 `~/.opencode/bin/opencode.bak`（不做任何修改）

2. **运行时**（启动脚本）：
   - 复制 `opencode.bak` 到临时目录
   - 使用 patchelf 动态修改 interpreter 指向自定义 glibc loader
   - 执行临时文件，退出后自动清理

```bash
# 运行时 patch 命令
patchelf --set-interpreter ~/.opencode/gnu/lib/ld-linux-x86-64.so.2 \
         /tmp/opencode
```

### 启动脚本设计

启动脚本采用以下稳健设计：

1. **运行时 patch**：不修改原始备份文件，每次启动时临时 patch
2. **不设置 glibc 的 LD_LIBRARY_PATH**：只设置 `$OPENCODE_DIR/gnu/lib64`（GCC 运行库），避免子进程 bash 继承自定义 glibc 而崩溃
3. **依赖 patchelf interpreter**：二进制自动通过 interpreter 找到自定义 glibc
4. **终端状态清理**：退出时重置终端鼠标模式，防止 TUI 退出后终端异常
5. **环境变量保存/恢复**：保存原始 `LD_LIBRARY_PATH`、`LANG`、`TERM`、`LOCPATH`，退出时恢复

### 为什么用运行时 patch？

| 方案 | 优点 | 缺点 |
|------|------|------|
| 安装时静态 patch | 简单快速 | 修改了原始二进制，难以恢复 |
| 运行时动态 patch | 保持原始备份，更安全灵活 | 每次启动需临时复制 |

本方案选择运行时动态 patch，原因：
- ✅ 保持 `opencode.bak` 原始状态，便于调试和恢复
- ✅ 支持 opencode 升级（重新运行 05 脚本即可）
- ✅ 临时目录执行，自动清理

## 兼容性

- ✅ CentOS 7.x (x86_64)
- ✅ RHEL 7.x (x86_64)
- ✅ Rocky Linux 7.x
- ✅ AlmaLinux 7.x

## 已知问题

### 1. 编译失败

**问题**：编译 GCC 或 glibc 时报错

**解决**：
```bash
# 安装完整开发工具
sudo yum groupinstall -y "Development Tools"
sudo yum install -y gmp-devel mpfr-devel libmpc-devel
```

### 2. 运行时找不到库

**问题**：`error while loading shared libraries: libxxx.so.x`

**解决**：确保用启动脚本运行：
```bash
# ✅ 正确
~/.opencode/bin/opencode
```

### 3. TUI 按键无响应

**问题**：Docker 中运行，按键没反应

**解决**：加上 `--privileged` 参数：
```bash
docker run --rm -it --privileged ...
```

## 参考项目

- [vscode-server-centos7](https://github.com/MikeWang000000/vscode-server-centos7) - VS Code Server on CentOS 7
- [opencode-on-centos7](https://github.com/Tao-Yida/opencode-on-centos7) - OpenCode on CentOS 7 原方案
- [opencode](https://opencode.ai) - OpenCode 官方项目

## License

MIT


######
2026.5.16 修改
调整脚本，可以摆脱对patchelf的依赖，实现启动，也就是借用原有的数据库安装，
cd gcc-9.5.0
./contrib/download_prerequisites预安装gcc前置
 ssh -L 2048:127.0.0.1:2048 root@net8(vmwareip)进行端口穿透
 然后使用OPENCODE_SERVER_PASSWARD="PASSWARD" opencode serve --hostname 127.0.0.1 --port 2048 启动虚拟机内cli，再添加model（授权copy）
 使用opencode attach http://127.0.0.1:2048 -p "PASSWARD"进行激活，达到在shell中进行虚拟机agent操作
 
