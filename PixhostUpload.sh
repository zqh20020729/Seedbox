#!/bin/bash
# PixHost 批量上传脚本 (统一输出BBCode格式和图片直链 - 强制 img2 服务器)
# 用法: ./PixHostUpload.sh <图片目录路径>

# 依赖检查
check_deps() {
    for pkg in jq curl; do
        if ! command -v "$pkg" &>/dev/null; then
            echo "正在安装依赖: $pkg..."
            sudo apt update -y >/dev/null 2>&1 && sudo apt install -y "$pkg" >/dev/null 2>&1 || {
                echo "错误: $pkg 安装失败"
                exit 1
            }
        fi
    done
}

# 参数检查
if [ -z "$1" ]; then
    echo "错误: 必须指定图片目录路径"
    echo "用法: $0 <图片目录路径>"
    exit 1
fi

DIR="$1"
if [ ! -d "$DIR" ]; then
    echo "错误: 目录不存在 [$DIR]"
    exit 1
fi

# 文件验证
validate_file() {
    local file="$1"
    [[ ! -f "$file" ]] && { echo "警告: 文件不存在 [$file]"; return 1; }
    file "$file" | grep -qiE 'image|bitmap' || { echo "警告: 非图片文件 [$file]"; return 1; }
    [ $(du -m "$file" | cut -f1) -gt 10 ] && { echo "警告: 文件过大 (>10MB) [$file]"; return 1; }
    return 0
}

# URL转换器 (强制转换为 img2.pixhost.to 原始直链)
convert_to_direct_url() {
    local show_url="$1"
    
    # 将域名统一替换为 img2，并将路径从 /show/ 转换为 /images/
    # 示例输入: https://pixhost.to/show/123/example.jpg
    # 示例输出: https://img2.pixhost.to/images/123/example.jpg
    local direct_url=$(echo "$show_url" | sed '
        s|https://pixhost.to/show/|https://img2.pixhost.to/images/|;
        s|https://pixhost.to/th/|https://img2.pixhost.to/images/|;
    ')

    # 最终验证格式是否正确
    if [[ "$direct_url" =~ ^https://img2\.pixhost\.to/images/[0-9]+/[^/]+\.(jpg|jpeg|png|gif)$ ]]; then
        echo "$direct_url"
    else
        # 如果 sed 失败，尝试用正则二次提取
        if [[ "$show_url" =~ ([0-9]+)/([^/]+\.(jpg|jpeg|png|gif)) ]]; then
            echo "https://img2.pixhost.to/images/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        else
            echo "错误: URL转换失败 [$show_url]"
            return 1
        fi
    fi
}

# 上传函数
upload_image() {
    local image="$1"
    local response show_url direct_url

    response=$(curl -s "https://api.pixhost.to/images" \
        -H "Accept: application/json" \
        -F "img=@$image" \
        -F "content_type=0" \
        -F "max_th_size=420" 2>&1) || {
        echo "错误: 上传请求失败 [$image]"
        return 1
    }

    jq -e . >/dev/null 2>&1 <<<"$response" || {
        echo "错误: API返回无效JSON [$image]"
        echo "$response"
        return 1
    }

    show_url=$(jq -r '.show_url // empty' <<<"$response")
    [ -z "$show_url" ] && {
        echo "错误: API未返回有效URL [$image]"
        echo "$response"
        return 1
    }

    convert_to_direct_url "$show_url"
}

# 主流程
main() {
    check_deps
    local total=0 success=0
    local bbcode_links=()
    local direct_links=()

    # 统计文件
    total=$(find "$DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) | wc -l)
    [ "$total" -eq 0 ] && {
        echo "警告: 未找到有效图片文件"
        exit 0
    }

    echo "开始处理 $total 个文件..."

    # 处理文件 (按文件名排序)
    while IFS= read -r image; do
        validate_file "$image" || continue
        
        if direct_url=$(upload_image "$image"); then
            ((success++))
            bbcode_links+=("[img]$direct_url[/img]")
            direct_links+=("$direct_url")
            echo "已上传 ($success/$total): $(basename "$image")"
        else
            echo "跳过文件: $(basename "$image")"
        fi
    done < <(find "$DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) | sort)

    # 统一输出结果
    echo -e "\n--------------------------------------------------"
    if [ "$success" -gt 0 ]; then
        echo "BBCode代码链接："
        for bbcode in "${bbcode_links[@]}"; do
            echo "$bbcode"
        done
        
        echo -e "\n图片直链 (img2)："
        for direct in "${direct_links[@]}"; do
            echo "$direct"
        done
    fi

    # 结果报告
    echo -e "\n--------------------------------------------------"
    echo "处理完成! 成功: ${success}/${total}"
    [ "$success" -eq 0 ] && exit 1 || exit 0
}

# 执行
main
