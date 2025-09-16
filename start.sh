#!/bin/bash

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                                                                            ║
# ║                    Flutter Desktop Release Script v2.0                     ║
# ║                                                                            ║
# ║                     优雅的一站式桌面应用发布脚本                            ║
# ║                                                                            ║
# ╚════════════════════════════════════════════════════════════════════════════╝
#
# 使用文档
# ================================================================================
#
# 快速开始
#   ./start.sh                     # 完整发布流程（图标+构建+打包）
#   ./start.sh --help              # 查看帮助文档
#
# 功能选项
#   --icons-only                   # 仅生成图标
#   --build-only                   # 仅构建应用
#   --package-only                 # 仅打包应用
#
# 平台选择
#   --platform macos              # 构建 macOS
#   --platform windows            # 构建 Windows
#   --platform linux              # 构建 Linux
#   --platform all                # 构建所有平台（默认）
#
# 图标配置
#   --icon-source <path>          # 指定图标源文件（默认: assets/icon.png）
#   --skip-icons                  # 跳过图标生成步骤
#
# 构建配置
#   --skip-build                  # 跳过构建步骤
#   --debug                       # 构建调试版本（默认: release）
#   --clean                       # 构建前清理
#
# 高级选项
#   --version <version>           # 指定版本号（覆盖 pubspec.yaml）
#   --output <dir>                # 指定输出目录（默认: dist）
#   --verbose                     # 显示详细日志
#   --dry-run                     # 模拟运行（不执行实际操作）
#
# 使用示例
#   ./start.sh --clean            # 清理后完整构建
#   ./start.sh --platform macos   # 仅构建 macOS 版本
#   ./start.sh --icons-only       # 仅生成应用图标
#   ./start.sh --debug            # 构建调试版本
#
# 前置要求
#   • Flutter SDK 3.0+
#   • ImageMagick（用于图标生成）
#   • Xcode（macOS 构建）
#   • Visual Studio（Windows 构建）
#
# 环境检查
#   脚本会自动检查所需依赖，如有缺失会给出安装提示
#
# ================================================================================

set -e  # 遇错即停

# ┌────────────────────────────────────────┐
# │            全局配置区                   │
# └────────────────────────────────────────┘

# 应用基本信息
APP_NAME="vibeloft"
BUNDLE_ID="com.vibeloft.desktop"

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ICON_SOURCE="assets/icon.png"
OUTPUT_DIR="build"
TEMP_DIR=".release_temp"

# 从 pubspec.yaml 读取版本
VERSION=$(grep "^version:" "$PROJECT_ROOT/pubspec.yaml" | cut -d ' ' -f 2 | tr -d '\r')

# 颜色定义（用于美化输出）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

# 默认参数
PLATFORM="all"
BUILD_MODE="release"
SKIP_ICONS=true
SKIP_BUILD=false
SKIP_PACKAGE=false
CLEAN_BUILD=false
VERBOSE=false
DRY_RUN=false

# ┌────────────────────────────────────────┐
# │            工具函数区                   │
# └────────────────────────────────────────┘

# 日志输出函数
log_info() {
    echo -e "${BLUE}ℹ  ${1}${NC}"
}

log_success() {
    echo -e "${GREEN}✓ ${1}${NC}"
}

log_error() {
    echo -e "${RED}✗ ${1}${NC}"
    exit 1
}

log_warning() {
    echo -e "${YELLOW}⚠  ${1}${NC}"
}

log_step() {
    echo -e "\n${CYAN}${BOLD}▶ ${1}${NC}"
}

# 显示进度
show_progress() {
    echo -e "${MAGENTA}⏳ ${1}...${NC}"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# 执行命令（支持 dry-run）
execute_cmd() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}▶ 执行: $*${NC}"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] $*${NC}"
    else
        "$@"
    fi
}

# ┌────────────────────────────────────────┐
# │            环境检查函数                 │
# └────────────────────────────────────────┘

check_environment() {
    log_step "检查构建环境"

    local has_error=false

    # 检查 Flutter
    if ! check_command flutter; then
        log_error "Flutter 未安装，请先安装 Flutter SDK"
        has_error=true
    else
        log_success "Flutter 已安装: $(flutter --version | head -n 1)"
    fi

    # 检查 ImageMagick（图标生成需要）
    if check_command magick; then
        log_success "ImageMagick 已安装 (使用 magick 命令)"
    elif check_command convert; then
        log_success "ImageMagick 已安装 (使用 convert 命令)"
    else
        log_warning "ImageMagick 未安装（图标生成需要）"
        echo "  安装方法："
        echo "    macOS:   brew install imagemagick"
        echo "    Linux:   sudo apt install imagemagick"
        echo "    Windows: https://imagemagick.org/script/download.php"
    fi

    # 检查平台特定工具
    case "$(uname -s)" in
        Darwin*)
            if ! check_command xcodebuild; then
                log_warning "Xcode 未安装（macOS 构建需要）"
            else
                log_success "Xcode 已安装"
            fi
            ;;
        Linux*)
            if ! check_command ninja; then
                log_warning "Ninja 未安装（Linux 构建需要）"
                echo "  安装: sudo apt install ninja-build"
            fi
            ;;
    esac

    # 检查项目文件
    if [ ! -f "$PROJECT_ROOT/pubspec.yaml" ]; then
        log_error "未找到 pubspec.yaml，请在 Flutter 项目根目录运行"
    fi

    if [ "$has_error" = true ]; then
        exit 1
    fi

    log_success "环境检查通过"
}

# ┌────────────────────────────────────────┐
# │            图标生成模块                 │
# └────────────────────────────────────────┘

generate_icons() {
    log_step "生成应用图标"

    # 检查源图标
    if [ ! -f "$ICON_SOURCE" ]; then
        log_warning "图标源文件不存在: $ICON_SOURCE"
        log_info "跳过图标生成"
        return 0
    fi

    # 检查 ImageMagick (优先检查 magick 命令)
    if ! check_command magick && ! check_command convert; then
        log_warning "ImageMagick 未安装，跳过图标生成"
        return 0
    fi

    # 创建临时目录
    mkdir -p "$TEMP_DIR"

    # 检查图标尺寸
    local dimensions=$(identify -format "%wx%h" "$ICON_SOURCE" 2>/dev/null || echo "0x0")
    local width=$(echo $dimensions | cut -d'x' -f1)
    local height=$(echo $dimensions | cut -d'x' -f2)

    if [ "$width" -lt 1024 ] || [ "$height" -lt 1024 ]; then
        log_warning "图标尺寸 ($dimensions) 小于推荐的 1024x1024"
    fi

    # 生成 macOS 图标
    if [[ "$PLATFORM" == "all" || "$PLATFORM" == "macos" ]]; then
        generate_macos_icons
    fi

    # 生成 Windows 图标
    if [[ "$PLATFORM" == "all" || "$PLATFORM" == "windows" ]]; then
        generate_windows_icons
    fi

    # 生成 Linux 图标
    if [[ "$PLATFORM" == "all" || "$PLATFORM" == "linux" ]]; then
        generate_linux_icons
    fi

    # 清理临时文件
    rm -rf "$TEMP_DIR"

    log_success "图标生成完成"
}

# macOS 图标生成
generate_macos_icons() {
    show_progress "生成 macOS 图标"

    local dest_dir="$PROJECT_ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    mkdir -p "$dest_dir"

    # 检查使用 magick 还是 convert 命令
    local img_cmd="convert"
    if check_command magick; then
        img_cmd="magick"
    fi

    # 根据 Contents.json 生成所需的 PNG 文件
    # 生成各种尺寸的图标文件
    execute_cmd $img_cmd "$ICON_SOURCE" -resize 16x16     "$dest_dir/app_icon_16.png"
    execute_cmd $img_cmd "$ICON_SOURCE" -resize 32x32     "$dest_dir/app_icon_32.png"
    execute_cmd $img_cmd "$ICON_SOURCE" -resize 64x64     "$dest_dir/app_icon_64.png"
    execute_cmd $img_cmd "$ICON_SOURCE" -resize 128x128   "$dest_dir/app_icon_128.png"
    execute_cmd $img_cmd "$ICON_SOURCE" -resize 256x256   "$dest_dir/app_icon_256.png"
    execute_cmd $img_cmd "$ICON_SOURCE" -resize 512x512   "$dest_dir/app_icon_512.png"
    execute_cmd $img_cmd "$ICON_SOURCE" -resize 1024x1024 "$dest_dir/app_icon_1024.png"

    log_success "macOS 图标已生成"
}

# Windows 图标生成
generate_windows_icons() {
    show_progress "生成 Windows 图标"

    local ico_dir="$TEMP_DIR/windows_icons"
    mkdir -p "$ico_dir"

    # 检查使用 magick 还是 convert 命令
    local img_cmd="convert"
    if check_command magick; then
        img_cmd="magick"
    fi

    # 生成 Windows 需要的尺寸
    for size in 16 24 32 48 64 128 256; do
        execute_cmd $img_cmd "$ICON_SOURCE" \
            -resize ${size}x${size} \
            -background transparent \
            "$ico_dir/icon_${size}.png"
    done

    # 合并成 .ico 文件
    execute_cmd $img_cmd "$ico_dir"/icon_*.png "$TEMP_DIR/app_icon.ico"

    # 复制到项目
    local dest="$PROJECT_ROOT/windows/runner/resources/app_icon.ico"
    mkdir -p "$(dirname "$dest")"
    execute_cmd cp "$TEMP_DIR/app_icon.ico" "$dest"

    log_success "Windows 图标已生成"
}

# Linux 图标生成
generate_linux_icons() {
    show_progress "生成 Linux 图标"

    local linux_dir="$PROJECT_ROOT/linux/runner/resources"
    mkdir -p "$linux_dir"

    # 检查使用 magick 还是 convert 命令
    local img_cmd="convert"
    if check_command magick; then
        img_cmd="magick"
    fi

    # 生成 Linux 标准尺寸
    for size in 16 32 48 64 128 256 512; do
        execute_cmd $img_cmd "$ICON_SOURCE" \
            -resize ${size}x${size} \
            "$linux_dir/app_icon_${size}.png"
    done

    # 创建主图标
    execute_cmd cp "$linux_dir/app_icon_512.png" "$linux_dir/app_icon.png"

    log_success "Linux 图标已生成"
}

# ┌────────────────────────────────────────┐
# │            构建模块                     │
# └────────────────────────────────────────┘

build_app() {
    log_step "构建应用"

    # 清理构建
    if [ "$CLEAN_BUILD" = true ]; then
        show_progress "清理旧构建"
        execute_cmd flutter clean
    fi

    # 获取依赖
    show_progress "获取依赖包"
    execute_cmd flutter pub get

    # 根据平台构建
    case "$PLATFORM" in
        all)
            build_all_platforms
            ;;
        macos)
            build_macos
            ;;
        windows)
            build_windows
            ;;
        linux)
            build_linux
            ;;
        *)
            log_error "不支持的平台: $PLATFORM"
            ;;
    esac

    log_success "应用构建完成"
}

# 构建所有平台
build_all_platforms() {
    # 检测当前系统
    case "$(uname -s)" in
        Darwin*)
            build_macos
            ;;
        Linux*)
            build_linux
            ;;
        MINGW*|MSYS*|CYGWIN*)
            build_windows
            ;;
        *)
            log_warning "未知系统，尝试构建所有平台"
            build_macos
            build_windows
            build_linux
            ;;
    esac
}

# 构建 macOS
build_macos() {
    show_progress "构建 macOS 应用"

    # 检查是否在 macOS 上
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_warning "当前不在 macOS 系统，跳过 macOS 构建"
        return 0
    fi

    # 检查 macOS 平台是否启用
    if ! flutter config --list | grep -q "enable-macos-desktop: true"; then
        log_info "启用 macOS 桌面支持"
        execute_cmd flutter config --enable-macos-desktop
    fi

    # 构建应用
    if [ "$BUILD_MODE" = "debug" ]; then
        execute_cmd flutter build macos --debug
    else
        execute_cmd flutter build macos --release
    fi

    log_success "macOS 构建成功"
}

# 构建 Windows
build_windows() {
    show_progress "构建 Windows 应用"

    # 检查 Windows 平台是否启用
    if ! flutter config --list | grep -q "enable-windows-desktop: true"; then
        log_info "启用 Windows 桌面支持"
        execute_cmd flutter config --enable-windows-desktop
    fi

    # 构建应用
    if [ "$BUILD_MODE" = "debug" ]; then
        execute_cmd flutter build windows --debug
    else
        execute_cmd flutter build windows --release
    fi

    log_success "Windows 构建成功"
}

# 构建 Linux
build_linux() {
    show_progress "构建 Linux 应用"

    # 检查 Linux 平台是否启用
    if ! flutter config --list | grep -q "enable-linux-desktop: true"; then
        log_info "启用 Linux 桌面支持"
        execute_cmd flutter config --enable-linux-desktop
    fi

    # 构建应用
    if [ "$BUILD_MODE" = "debug" ]; then
        execute_cmd flutter build linux --debug
    else
        execute_cmd flutter build linux --release
    fi

    log_success "Linux 构建成功"
}

# ┌────────────────────────────────────────┐
# │            打包模块                     │
# └────────────────────────────────────────┘

package_app() {
    log_step "打包应用"

    # 创建输出目录
    mkdir -p "$OUTPUT_DIR"

    # 根据平台打包
    case "$PLATFORM" in
        all)
            package_all_platforms
            ;;
        macos)
            package_macos
            ;;
        windows)
            package_windows
            ;;
        linux)
            package_linux
            ;;
    esac

    log_success "打包完成，文件位于: $OUTPUT_DIR"
    ls -la "$OUTPUT_DIR"
}

# 打包所有平台
package_all_platforms() {
    case "$(uname -s)" in
        Darwin*)
            package_macos
            ;;
        Linux*)
            package_linux
            ;;
        MINGW*|MSYS*|CYGWIN*)
            package_windows
            ;;
    esac
}

# 打包 macOS
package_macos() {
    show_progress "打包 macOS 应用"

    local app_path="build/macos/Build/Products/Release/${APP_NAME}.app"
    if [ "$BUILD_MODE" = "debug" ]; then
        app_path="build/macos/Build/Products/Debug/${APP_NAME}.app"
    fi

    if [ ! -d "$app_path" ]; then
        log_warning "macOS 应用未找到，跳过打包"
        return 0
    fi

    # 复制 .app 到输出目录
    execute_cmd cp -R "$app_path" "$OUTPUT_DIR/"

    # 创建 DMG（如果有 create-dmg）
    if check_command create-dmg; then
        show_progress "创建 DMG 安装包"
        execute_cmd create-dmg \
            --volname "$APP_NAME" \
            --window-pos 200 120 \
            --window-size 800 400 \
            --icon-size 100 \
            --app-drop-link 600 185 \
            "$OUTPUT_DIR/${APP_NAME}-${VERSION}-macos.dmg" \
            "$OUTPUT_DIR/${APP_NAME}.app"
    else
        log_info "create-dmg 未安装，跳过 DMG 创建"
        log_info "安装方法: npm install -g create-dmg"
    fi

    log_success "macOS 打包完成"
}

# 打包 Windows
package_windows() {
    show_progress "打包 Windows 应用"

    local win_path="build/windows/x64/runner/Release"
    if [ "$BUILD_MODE" = "debug" ]; then
        win_path="build/windows/x64/runner/Debug"
    fi

    if [ ! -d "$win_path" ]; then
        log_warning "Windows 应用未找到，跳过打包"
        return 0
    fi

    # 创建 ZIP 包
    local zip_name="${APP_NAME}-${VERSION}-windows.zip"
    show_progress "创建 ZIP 包: $zip_name"

    cd "$win_path"
    execute_cmd zip -r "../../../../../$OUTPUT_DIR/$zip_name" .
    cd - > /dev/null

    log_success "Windows 打包完成"
}

# 打包 Linux
package_linux() {
    show_progress "打包 Linux 应用"

    local linux_path="build/linux/x64/release/bundle"
    if [ "$BUILD_MODE" = "debug" ]; then
        linux_path="build/linux/x64/debug/bundle"
    fi

    if [ ! -d "$linux_path" ]; then
        log_warning "Linux 应用未找到，跳过打包"
        return 0
    fi

    # 创建 tar.gz 包
    local tar_name="${APP_NAME}-${VERSION}-linux.tar.gz"
    show_progress "创建 TAR.GZ 包: $tar_name"

    cd "$linux_path"
    execute_cmd tar -czf "../../../../../$OUTPUT_DIR/$tar_name" .
    cd - > /dev/null

    log_success "Linux 打包完成"
}

# ┌────────────────────────────────────────┐
# │            帮助文档                     │
# └────────────────────────────────────────┘

show_help() {
    cat << EOF
${BOLD}${CYAN}Flutter Desktop Release Script${NC}

${BOLD}用法:${NC}
  ./start.sh [选项]

${BOLD}选项:${NC}
  ${GREEN}--help${NC}              显示此帮助信息
  ${GREEN}--icons-only${NC}        仅生成图标
  ${GREEN}--build-only${NC}        仅构建应用
  ${GREEN}--package-only${NC}      仅打包应用

  ${GREEN}--platform${NC} <平台>   指定构建平台 (macos/windows/linux/all)
  ${GREEN}--icon-source${NC} <路径> 指定图标源文件
  ${GREEN}--skip-icons${NC}        跳过图标生成
  ${GREEN}--skip-build${NC}        跳过构建步骤
  ${GREEN}--skip-package${NC}      跳过打包步骤

  ${GREEN}--debug${NC}             构建调试版本
  ${GREEN}--clean${NC}             构建前清理
  ${GREEN}--version${NC} <版本>    指定版本号
  ${GREEN}--output${NC} <目录>     指定输出目录

  ${GREEN}--verbose${NC}           显示详细日志
  ${GREEN}--dry-run${NC}           模拟运行

${BOLD}示例:${NC}
  ./start.sh                        # 完整发布流程
  ./start.sh --platform macos       # 仅构建 macOS
  ./start.sh --icons-only           # 仅生成图标
  ./start.sh --clean --debug        # 清理后构建调试版

${BOLD}版本:${NC} 2.0
${BOLD}作者:${NC} VibeLoft Team

EOF
}

# ┌────────────────────────────────────────┐
# │            参数解析                     │
# └────────────────────────────────────────┘

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --icons-only)
                SKIP_BUILD=true
                SKIP_PACKAGE=true
                shift
                ;;
            --build-only)
                SKIP_ICONS=true
                SKIP_PACKAGE=true
                shift
                ;;
            --package-only)
                SKIP_ICONS=true
                SKIP_BUILD=true
                shift
                ;;
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --icon-source)
                ICON_SOURCE="$2"
                shift 2
                ;;
            --skip-icons)
                SKIP_ICONS=true
                shift
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-package)
                SKIP_PACKAGE=true
                shift
                ;;
            --debug)
                BUILD_MODE="debug"
                shift
                ;;
            --clean)
                CLEAN_BUILD=true
                shift
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                ;;
        esac
    done
}

# ┌────────────────────────────────────────┐
# │            主程序入口                   │
# └────────────────────────────────────────┘

main() {
    # 显示欢迎信息
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════╗"
    echo "║     Flutter Desktop Release Script     ║"
    echo "║              Version 2.0                ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"

    # 解析参数
    parse_arguments "$@"

    # 显示配置信息
    log_info "配置信息:"
    echo "  • 应用名称: $APP_NAME"
    echo "  • 版本号: $VERSION"
    echo "  • 构建平台: $PLATFORM"
    echo "  • 构建模式: $BUILD_MODE"
    echo "  • 输出目录: $OUTPUT_DIR"

    # 环境检查
    if [ "$DRY_RUN" = false ]; then
        check_environment
    fi

    # 执行主要步骤

    # 步骤 1: 生成图标
    if [ "$SKIP_ICONS" = false ]; then
        generate_icons
    else
        log_info "跳过图标生成"
    fi

    # 步骤 2: 构建应用
    if [ "$SKIP_BUILD" = false ]; then
        build_app
    else
        log_info "跳过应用构建"
    fi

    # 步骤 3: 打包应用
    if [ "$SKIP_PACKAGE" = false ]; then
        package_app
    else
        log_info "跳过应用打包"
    fi

    # 完成提示
    echo -e "\n${GREEN}${BOLD}"
    echo "╔════════════════════════════════════════╗"
    echo "║         🎉 发布流程完成！               ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"

    if [ -d "$OUTPUT_DIR" ]; then
        log_info "输出文件位于: $OUTPUT_DIR"
    fi
}

# ┌────────────────────────────────────────┐
# │            执行主程序                   │
# └────────────────────────────────────────┘

# 确保在项目根目录执行
cd "$PROJECT_ROOT"

# 运行主程序
main "$@"