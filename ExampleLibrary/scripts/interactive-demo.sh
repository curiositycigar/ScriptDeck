#!/bin/bash
set -euo pipefail
printf '\033[36m应用内交互终端演示\033[0m\n'
printf '这个演示不会上传文件或连接远程服务。\n\n'
read -r -p '请输入一个显示名称：' DEMO_NAME
printf '你好，%s。\n' "$DEMO_NAME"
read -r -s -p '请输入任意演示文本（不回显，也不会保存）：' DEMO_SECRET
printf '\n已收到隐藏输入，内容不会输出。\n'
unset DEMO_SECRET
read -r -p '开始演示进度刷新？[y/N] ' DEMO_CONFIRM
case "$DEMO_CONFIRM" in
    y|Y)
        for DEMO_PROGRESS in 0 20 40 60 80 100; do
            printf '\r\033[2K进度：%s%%' "$DEMO_PROGRESS"
            sleep 0.3
        done
        printf '\n\033[32m演示完成。\033[0m\n'
        ;;
    *) printf '已取消进度演示。\n' ;;
esac
