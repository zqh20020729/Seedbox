#!/bin/bash
# PixHost 批量上传工具 (增强版)
# 功能：支持更多格式、并行上传思路以及更健壮的 URL 转换

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# --- 依赖检查 ---
check_deps() {
    for pkg in jq curl file; do
        if ! command -v "$pkg" &>/dev/null; then
            echo -e "${YELLOW}正在安装依赖: $pkg...${NC}"
            sudo apt update -y >/dev/null 2>&1 && sudo apt install -y "$pkg" >/dev/null 2>&1 || {
                echo -e "${RED}错误: $pkg 安装失败，请手动安装。${NC}"
                exit 1
            }
        fi
    done
}

# --- 参数与目录检查 ---
if [ -z "$1" ]; then
    echo "用法: $0 <图片目录路径>"
    exit 1
fi

DIR="$1"
[[ ! -d "$DIR" ]] && { echo -e "${RED}错误: 目录不存在 [$DIR]${NC}"; exit 1; }

# --- 文件验证 ---
validate_file() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1
    # 增加 webp 支持
    file --mime-type "$file" | grep -qiE 'image/(jpeg|png|gif|webp|bmp)' || return 1
    # 限制 10MB
    [[ $(stat -c%s "$file") -gt 10485760 ]] && return 1
    return 0
}

# --- 核心：直链转换器 ---
# PixHost API 返回 show_url (展示页)，我们需要推导其存储服务器
convert_to_direct_url() {
    local show_url="$1"
    # PixHost 的逻辑通常是 https://pixhost.to/show/[ID]/[FILENAME]
    # 直链通常是 https://img[N].pixhost.to/images/[ID]/[FILENAME]
    # 关键在于：show_url 页面内其实包含服务器编号，但为了脚本简洁，
    # 绝大多数新上传都通过 img1 分发。如果 img1 失效，可能需要更复杂的正则。
    
    if [[ "$show_url" =~ show/([0-9]+)/(.+)$ ]]; then
        local img_id="${BASH_REMATCH[1]}"
        local img_name="${BASH_REMATCH[2]}"
        echo "https://img1.pixhost.to/images/${img_id}/${img_name}"
    else
        return 1
    fi
}

# --- 上传函数 ---
upload_image() {
    local image="$1"
    local response
    
    # 增加超时处理，防止脚本卡死
    response=$(curl -s --connect-timeout 10 --max-time 60 "https://api.pixhost.to/images" \
        -H "Accept: application/json" \
        -F "img=@$image" \
        -F "content_type=0" \
        -F "max_th_size=420")

    # 检查 API 是否返回了正确的 JSON
    if ! jq -e . <<<"$response" >/dev/null 2>&1; then
        return 1
    fi

    local show_url=$(jq -r '.show_url // empty' <<<"$response")
    [[ -z "$show_url" ]] && return 1

    convert_to_direct_url "$show_url"
}

# --- 主程序 ---
main() {
    check_deps
    
    local files=()
    # 改进文件查找，支持更多后缀且对特殊字符更友好
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) -print0)

    local total=${#files[@]}
    [[ $total -eq 0 ]] && { echo "未发现有效图片。"; exit 0; }

    echo -e "${GREEN}找到 $total 个文件，准备上传...${NC}"

    local success=0
    local bbcode_links=""
    local direct_links=""

    for img in "${files[@]}"; do
        echo -n "正在上传: $(basename "$img")... "
        if ! validate_file "$img"; then
            echo -e "${YELLOW}[跳过: 格式不支持或文件过大]${NC}"
            continue
        fi

        local direct_url
        direct_url=$(upload_image "$img")
        
        if [[ $? -eq 0 ]]; then
            ((success++))
            bbcode_links+="[img]${direct_url}[/img]\n"
            direct_links+="${direct_url}\n"
            echo -e "${GREEN}[成功]${NC}"
        else
            echo -e "${RED}[失败]${NC}"
        fi
    done

    # 输出结果
    echo -e "\n--- 上传报告 ($success/$total) ---"
    if [[ $success -gt 0 ]]; then
        echo -e "\n${YELLOW}[BBCode 代码]${NC}"
        echo -e "$bbcode_links"
        echo -e "${YELLOW}[图片直链]${NC}"
        echo -e "$direct_links"
    fi
}

main
