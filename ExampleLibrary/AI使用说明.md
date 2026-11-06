# 给 AI 的脚本库使用说明

每个 Workspace 对应一个独立目录，无需在此库配置中填写 Workspace ID 或本机登记信息。

在此目录中编写脚本并配置 `library.json`，App 会自动检测配置变化。字段约束见 `library.schema.json`。

1. 新脚本放到 `scripts/`。脚本与配置使用 UTF-8，JSON 不包含注释或尾逗号。
2. 配置文件格式为 `{"version":1,"scripts":[...]}`，保留已有脚本条目，不重写无关内容。可保留 `$schema` 字段以便编辑器提示。
3. 脚本必填字段为 `id`、`name`、`file`。使用稳定可读的 ID，例如 `database-backup`；修改名称时保留 ID。参数 ID 在同一脚本内唯一。
4. `file` 和 `cwd` 相对于此目录解析。省略 `cwd` 时以脚本所在目录运行，`cwd: "."` 表示库根目录。优先使用相对路径，便于迁移。
5. `group` 使用 `/` 分隔层级，如 `运维/备份`。
6. `interpreter` 支持 `/bin/bash`、`/bin/zsh`、`python3`、`node`、`direct`，以及自定义解释器绝对路径。
7. 所有脚本都在 App 内交互终端运行，支持密码、确认和标准输入；无需配置 `execution`（旧字段仍兼容读取但不生效）。不要在默认值或日志中存储密码。
8. 参数按 `parameters` 数组顺序对应脚本的 `$1`、`$2` 等。每项需包含 `id`、`label`；`type` 可为 `text`、`file`、`folder`、`select`；`required` 默认为 false。不要设计需要跳过中间位置参数的调用方式。
9. 下拉参数配置示例：`{"id":"environment","label":"目标环境","type":"select","required":true,"default":"staging","options":[{"label":"预发布","value":"staging"},{"label":"生产","value":"production"}]}`。下拉框显示 label，传给脚本的是 value。options 也可以写成字符串数组。选项传值非空且唯一，default 必须匹配某个选项。
10. 脚本成功时返回 0，失败时返回非零状态。按步骤输出日志，长任务及时刷新输出。处理参数时正确使用引号。
11. 不要在修改配置后自动运行脚本。用户会在 App 中手动选择并执行。

可使用的请求示例：

> 在这个脚本库新增一个日志归档脚本，放到“运维/日志”分组。提供目录选择参数和压缩格式下拉参数，默认 gzip；完成后配置 library.json，不执行脚本。

App 会自动把执行日志保存在脚本所在目录的 `logs/脚本文件名/` 中（文件名保留扩展名），无需在脚本中重复实现 App 的日志落盘。不要在脚本输出中打印密码；可通过输出区“历史记录”查看每次运行的日志。
