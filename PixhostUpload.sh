#!/bin/bash
# PixHost 批量上传脚本 (API 修复版)
# 修复内容：基于 API 返回的 th_url 动态计算直链，支持更多格式，增强稳定性

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

# --- 核心：直链转换算法 ---
# 原理：PixHost 的缩略图是 https://thX.pixhost.to/thumbs/ID/NAME
# 对应的直链通常是 https://imgX.pixhost.to/images/ID/NAME
get_direct_url() {
    local th_url="$1"
    if [[ -n "$th_url" ]]; then
        # 将 'th' 替换为 'img'，将 'thumbs' 替换为 'images'
        echo "$th_url" | sed 's|//th|//img|; s|/thumbs/|/images/|'
    fi
}

# --- 上传函数 ---
upload_image() {
    local img_path="$1"
    
    # 按照 API 文档发送 POST 请求
    # content_type: 0 为安全内容，1 为成人内容
    # max_th_size: 缩略图尺寸
    local response=$(curl -s -X POST "https://api.pixhost.to/images" \
        -H "Accept: application/json" \
        -F "img=@$img_path" \
        -F "content_type=0" \
        -F "max_th_size=420")

    # 解析返回的 JSON
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        return 1
    fi

    local th_url=$(echo "$response" | jq -r '.th_url // empty')
    local show_url=$(echo "$response" | jq -r '.show_url // empty')

    if [[ -z "$th_url" ]]; then
        return 1
    fi

    # 计算直链
    local direct_url=$(get_direct_url "$th_url")
    echo "$direct_url"
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

    # 查找常见图片格式
    mapfile -d $'\0' files < <(find "$dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) -print0)
    total=${#files[@]}

    [[ $total -eq 0 ]] && { echo -e "${R}错误: 目录中没有发现图片${NC}"; exit 1; }

    echo -e "${G}开始上传 ${total} 张图片到 PixHost...${NC}\n"

    for img in "${files[@]}"; do
        local fname=$(basename "$img")
        echo -n "正在上传 [$fname] ... "

        local d_url=$(upload_image "$img")
        if [[ $? -eq 0 ]]; then
            echo -e "${G}成功${NC}"
            ((success++))
            bbcode_output+="[img]${d_url}[/img]\n"
            direct_output+="${d_url}\n"
        else
            echo -e "${R}失败${NC}"
        fi
    done

    # 输出汇总结果
    if [[ $success -gt 0 ]]; then
        echo -e "\n${Y}====== 结果汇总 (${success}/${total}) ======${NC}"
        echo -e "\n[BBCode 代码]"
        echo -e "$bbcode_output"
        echo -e "\n[图片直链]"
        echo -e "$direct_output"
        echo -e "${Y}==========================================${NC}"
    fi
}

main "$1"
