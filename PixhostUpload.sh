#!/bin/bash
# PixHost 批量上传脚本 - 节点修正版
# 变更：强制将所有返回直链指向 img2 域名

# --- 颜色与依赖 ---
G='\033[0;32m'
R='\033[0;31m'
Y='\033[1;33m'
NC='\033[0m'

check_deps() {
    for pkg in jq curl; do
        command -v "$pkg" &>/dev/null || {
            echo -e "${Y}安装依赖: $pkg...${NC}"
            sudo apt update -y >/dev/null 2>&1 && sudo apt install -y "$pkg" -y >/dev/null 2>&1
        }
    done
}

# --- 核心：强制转换逻辑 ---
# 不管 API 返回 th1 还是 th18，一律强制生成 img2 的直链
get_direct_url() {
    local th_url="$1"
    if [[ -n "$th_url" ]]; then
        # 正则说明：
        # 1. s|//th[0-9]*\.|//img2.|  -> 强制将 th(数字) 替换为 img2
        # 2. s|/thumbs/|/images/|     -> 将路径由缩略图转为原图
        echo "$th_url" | sed -E 's|//th[0-9]*\.|//img2.|; s|/thumbs/|/images/|'
    fi
}

# --- 上传逻辑 ---
upload_image() {
    local img_path="$1"
    local response=$(curl -s -X POST "https://api.pixhost.to/images" \
        -H "Accept: application/json" \
        -F "img=@$img_path" \
        -F "content_type=0" \
        -F "max_th_size=420")

    # 检查返回是否为 JSON
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then return 1; fi

    local th_url=$(echo "$response" | jq -r '.th_url // empty')
    [[ -z "$th_url" ]] && return 1

    # 调用转换函数
    get_direct_url "$th_url"
}

# --- 执行流程 ---
main() {
    [[ -z "$1" ]] && { echo "用法: $0 <图片目录>"; exit 1; }
    check_deps
    
    local dir="$1"
    local success=0
    local bbcode_output=""
    local direct_output=""

    # 递归查找图片（限当前目录）
    mapfile -d $'\0' files < <(find "$dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) -print0)
    
    [[ ${#files[@]} -eq 0 ]] && { echo -e "${R}错误: 没找到图片${NC}"; exit 1; }

    echo -e "${G}正在使用 img2 节点上传 ${#files[@]} 张图片...${NC}"

    for img in "${files[@]}"; do
        echo -n "处理: $(basename "$img") ... "
        local d_url=$(upload_image "$img")
        
        if [[ $? -eq 0 ]]; then
            echo -e "${G}[完成]${NC}"
            ((success++))
            bbcode_output+="[img]${d_url}[/img]\n"
            direct_output+="${d_url}\n"
        else
            echo -e "${R}[失败]${NC}"
        fi
    done

    # 最终输出
    if [[ $success -gt 0 ]]; then
        echo -e "\n${Y}====== 上传成功 ($success) ======${NC}"
        echo -e "\n[BBCode]"
        echo -e "$bbcode_output"
        echo -e "[直链 (img2)]"
        echo -e "$direct_output"
    fi
}

main "$1"
