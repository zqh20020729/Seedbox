#!/bin/bash
# PixHost 批量上传脚本 (2024.06 更新版)
# 修复内容：动态匹配 imgX 存储节点，确保直链解析正确

# --- 颜色定义 ---
G='\033[0;32m'
R='\033[0;31m'
Y='\033[1;33m'
NC='\033[0m'

# --- 依赖检查 ---
check_deps() {
    for pkg in jq curl; do
        if ! command -v "$pkg" &>/dev/null; then
            echo -e "${Y}正在安装依赖: $pkg...${NC}"
            sudo apt update -y >/dev/null 2>&1 && sudo apt install -y "$pkg" >/dev/null 2>&1
        fi
    done
}

# --- 核心：动态直链转换 ---
# 逻辑：自动捕捉 API 返回的缩略图服务器编号（如 th2 -> img2）
get_direct_url() {
    local th_url="$1"
    if [[ -n "$th_url" ]]; then
        # 1. 把协议后的 'th' 替换为 'img' (保留后面的编号)
        # 2. 把路径中的 '/thumbs/' 替换为 '/images/'
        echo "$th_url" | sed -E 's|//th([0-9]*)\.|//img\1.|; s|/thumbs/|/images/|'
    fi
}

# --- 上传函数 ---
upload_image() {
    local img_path="$1"
    
    # 执行上传
    local response=$(curl -s -X POST "https://api.pixhost.to/images" \
        -H "Accept: application/json" \
        -F "img=@$img_path" \
        -F "content_type=0" \
        -F "max_th_size=420")

    # 验证 JSON 有效性
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        return 1
    fi

    local th_url=$(echo "$response" | jq -r '.th_url // empty')
    
    if [[ -z "$th_url" ]]; then
        return 1
    fi

    # 生成直链
    get_direct_url "$th_url"
}

# --- 主程序 ---
main() {
    [[ -z "$1" ]] && { echo "用法: $0 <图片目录>"; exit 1; }
    check_deps

    local dir="$1"
    local success=0
    local total=0
    local bbcode_output=""
    local direct_output=""

    # 这里的 find 增加了对空目录的兼容处理
    mapfile -d $'\0' files < <(find "$dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) -print0)
    total=${#files[@]}

    [[ $total -eq 0 ]] && { echo -e "${R}错误: 目录中没有发现有效图片${NC}"; exit 1; }

    echo -e "${G}检测到存储节点更新，开始上传 ${total} 张图片...${NC}\n"

    for img in "${files[@]}"; do
        local fname=$(basename "$img")
        echo -n "上传中: [$fname] ... "

        local d_url=$(upload_image "$img")
        if [[ $? -eq 0 && -n "$d_url" ]]; then
            echo -e "${G}成功 -> $(echo $d_url | cut -d'.' -f1 | cut -d'/' -f3)${NC}" # 显示当前使用的 img 节点
            ((success++))
            bbcode_output+="[img]${d_url}[/img]\n"
            direct_output+="${d_url}\n"
        else
            echo -e "${R}失败${NC}"
        fi
    done

    # 输出结果汇总
    if [[ $success -gt 0 ]]; then
        echo -e "\n${Y}====== 结果汇总 (${success}/${total}) ======${NC}"
        echo -e "\n${G}[BBCode 列表]${NC}"
        echo -e "$bbcode_output"
        echo -e "${G}[直链列表]${NC}"
        echo -e "$direct_output"
        echo -e "${Y}==========================================${NC}"
    fi
}

main "$1"
