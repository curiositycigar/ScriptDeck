#!/usr/bin/env bash
set -euo pipefail

printf '[%s] 开始参数演示\n' "$(date '+%H:%M:%S')"
printf '目标环境：%s\n' "${1:?缺少目标环境}"
printf '运行模式：%s\n' "${2:?缺少运行模式}"
printf '备注：%s\n' "${3-未填写}"
printf '当前目录：%s\n' "$PWD"
printf '参数演示完成。\n'
