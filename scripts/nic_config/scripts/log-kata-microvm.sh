#!/bin/bash

# 输入的简短ID
short_id=$1

# 使用crictl inspectp 命令获取完整的ID
full_id=$(crictl inspectp $short_id | grep '"id":' | head -n 1 | awk -F\" '{print $4}')

# 判断是否成功提取到完整ID
if [ -z "$full_id" ]; then
  echo "无法找到与$short_id对应的完整ID。"
  exit 1
fi

echo "找到完整ID: $full_id"

# 执行kata-exec.sh脚本，将完整ID作为参数
bash kata-exec.sh $full_id
