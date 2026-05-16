#!/bin/bash
# 06-create-launcher.sh - 创建启动脚本
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode}"
BIN_DIR="$INSTALL_DIR/bin"

log_step "步骤 6: 创建启动脚本"

if [ ! -f "$BIN_DIR/opencode.bak" ]; then
    log_error "未找到 opencode.bak，请先运行：bash scripts/05-install-opencode.sh"
    exit 1
fi

log_info "创建启动脚本..."
cat > "$BIN_DIR/opencode" << 'LAUNCHER_EOF'
#!/bin/bash
# OpenCode Launcher - 终极方案 (废弃 patchelf，使用 ld.so 原生重定向)
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OPENCODE_DIR="$( dirname "$SCRIPT_DIR" )"

if [[ ! -d "$OPENCODE_DIR" ]]; then
    echo "错误：未找到 OpenCode 安装目录 $OPENCODE_DIR"
    exit 1
fi

cleanup_terminal() {
    # 重置终端鼠标事件跟踪
    echo -e '\033[?1000h\033[?1002h\033[?1003h' 2>/dev/null || true
    # 恢复终端正常状态，防止崩溃后乱码
    stty sane 2>/dev/null || true
}
trap cleanup_terminal EXIT INT TERM

# 禁用鼠标事件跟踪（防止终端异常）
echo -e '\033[?1000l\033[?1002l\033[?1003l\033[?1005l\033[?1006l' 2>/dev/null || true

# 关键路径
GLIBC_LOADER="$OPENCODE_DIR/gnu/lib/ld-linux-x86-64.so.2"
OPENCODE_BIN="$OPENCODE_DIR/bin/opencode.bak"

if [[ ! -f "$GLIBC_LOADER" ]]; then
    echo "错误：未找到 glibc loader: $GLIBC_LOADER"
    exit 1
fi

if [[ ! -f "$OPENCODE_BIN" ]]; then
    echo "错误：未找到 OpenCode 备份文件：$OPENCODE_BIN"
    exit 1
fi

# 保存原始环境变量
ORIGINAL_LANG="${LANG:-}"
ORIGINAL_TERM="${TERM:-}"
ORIGINAL_LOCPATH="${LOCPATH:-}"

# 运行前：彻底清空所有可能污染 glibc 加载的系统环境变量
unset LD_LIBRARY_PATH
unset LD_PRELOAD

# 设置安全的环境变量
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TERM=xterm-256color

# 设置 locale 路径
if [[ -d "$OPENCODE_DIR/gnu/lib/locale" ]]; then
    export LOCPATH="$OPENCODE_DIR/gnu/lib/locale"
fi

# ==============================================================================
# 核心启动逻辑：使用新版 ld.so 直接引导程序并指定库搜索路径
# --library-path 强制程序优先寻找 gnu/lib 和 gnu/lib64，完美替代 RPATH
# ==============================================================================
echo "信息：正在启动 OpenCode..."
"$GLIBC_LOADER" --library-path "$OPENCODE_DIR/gnu/lib:$OPENCODE_DIR/gnu/lib64" "$OPENCODE_BIN" "$@"
RETURN_CODE=$?

# 恢复原始环境变量
export LANG="$ORIGINAL_LANG"
export TERM="$ORIGINAL_TERM"

if [[ -n "$ORIGINAL_LOCPATH" ]]; then
    export LOCPATH="$ORIGINAL_LOCPATH"
else
    unset LOCPATH
fi

exit $RETURN_CODE
LAUNCHER_EOF

chmod +x "$BIN_DIR/opencode"

log_info "测试运行..."
if "$BIN_DIR/opencode" --version &> /dev/null; then
    log_success "安装完成！"
    echo ""
    echo "使用方法：$INSTALL_DIR/opencode"
else
    log_error "测试失败，请检查日志"
    exit 1
fi
