# 项目结构与维护约定

这是一个使用 SwiftUI 和 AppKit 的 macOS 应用，通过 Swift Package Manager 构建。应用仍为单个模块，依赖固定版本的 SwiftTerm 提供原生交互终端，依赖解析结果保存在 Package.resolved。

```text
ScriptDeck/
├── Sources/
│   ├── App/                 # 应用入口、窗口生命周期、脚本子进程入口
│   ├── Models/              # 脚本、参数、执行方式、配置文档、分组树
│   ├── Library/             # 脚本库读写、变更检测、导入迁移、错误解释
│   ├── Workspaces/          # 本机登记、库实例缓存、按 Workspace 隔离的会话状态
│   ├── History/             # 流式日志写入、ANSI 过滤、目录索引、历史与分页读取
│   ├── Scheduling/          # 定时模型、原子持久化、LaunchAgent、后台执行器、计划管理 UI
│   ├── Preferences/         # 持久化全局偏好
│   ├── Execution/           # 参数校验、命令构造、多会话管理、PTY 与停止控制
│   ├── Views/
│   │   ├── Runner/          # 主窗口及按职责划分的同类型扩展
│   │   ├── History/         # 执行记录筛选、列表和日志详情
│   │   ├── Settings/        # Workspace 管理和终端设置
│   │   ├── Terminal/        # SwiftTerm 的 AppKit/SwiftUI 桥接
│   │   └── Editor/          # 脚本配置编辑器
│   └── Support/             # 通用错误类型、原生路径选择器
├── Resources/
│   ├── Info.plist           # 应用元数据、版本和权限说明
│   └── library.schema.json  # 脚本库配置格式的规范源文件
├── Assets/                  # 图标原图、PNG 母版、ICNS
├── Scripts/                 # 构建、打包、测试入口实现和图标转换工具
├── Tests/                   # 现有测试源码
├── ExampleLibrary/          # 可直接打开的示例脚本库
├── Docs/                    # 架构说明、图标设计记录
├── Package.swift            # 构建目标与精确依赖版本
├── Package.resolved         # 完整依赖版本锁定
├── build.sh                 # 兼容入口，转发到 Scripts/build.sh
├── package.sh               # 兼容入口，转发到 Scripts/package.sh
├── test.sh                  # 兼容入口，仅主动调用时执行测试
├── .build/                  # 编译缓存、图标尺寸、临时打包目录（忽略）
└── dist/                    # App 与 ZIP 产物（忽略）
```

## 职责边界

- `App` 负责组合 `WorkspaceStore`、`AppPreferences`、`ProcessRunner`、主窗口和设置窗口。`EntryPoint` 保留辅助进程模式，用于建立独立进程组并启动脚本。
- `Models` 负责数据定义、JSON 编解码兼容和配置校验，不依赖界面或进程管理。`RunnerError` 是共享的错误值类型。
- `Library` 负责文件系统和偏好存储，不直接操作界面。通过 ObservableObject 发布库内容和配置问题。
- `Execution` 负责参数验证、解释器选择、PTY 会话和进程停止。ProcessRunner 在主线程管理 ExecutionSession 集合和当前终端选择；每次执行独立持有终端视图、进程状态及日志写入器，保证面板收起或选择切换不会销毁正在运行的终端。底层 IO 与终端解析由 SwiftTerm 管理。
- `Views` 负责交互和显示，通过 Store、Runner 调用读写与执行服务。
- `Support/PathPicker.swift` 使用 AppKit，供界面选择路径；执行服务和数据模型不调用它。

`RunnerView.swift` 保留主窗口的状态、布局和生命周期。其他 `RunnerView+*.swift` 是同一视图的扩展，分别负责 Workspace 操作、侧栏、配置参数和执行操作。终端输出由独立的 TaskOutputView 显示，放在当前 Workspace 视图之外。这些扩展共享视图状态，因此相关成员使用模块内部访问权限；它们不对外形成独立业务服务。新增可复用控件时，应提取为独立 View，通过值、Binding 或回调传入依赖。

## 维护约定

1. 新增 Swift 文件放入对应职责目录，文件名使用主要类型或职责名称。Swift Package Manager 会递归收集 `Sources/` 下的 Swift 文件，无需逐项登记。
2. UI 不新增 JSON 读写、脚本命令拼接或底层进程控制逻辑，分别放入 `Library` 和 `Execution`。
3. 配置字段变更同步更新模型、`Resources/library.schema.json`、示例配置和使用说明。发布打包会将规范源 Schema 复制到示例库。
4. 版本号与构建号统一在 `Resources/Info.plist` 维护。打包脚本从中读取版本号，生成对应名称的 ZIP。
5. 修改图标母版后运行 `bash Scripts/make-icon.sh`，使用本地工具转换尺寸和 ICNS；构建会自动执行转换。
6. `bash package.sh` 仅构建、签名和打包，不运行应用或测试。`bash test.sh` 是独立、显式的测试命令。

构建产物不作为源码维护；保持 `.build/` 和 `dist/` 在 Git 忽略规则中。

## 交互终端

`RunnerTerminalView` 提供原生终端渲染和输入，`EmbeddedTerminalView` 仅负责把持久化终端视图嵌入 SwiftUI。每次运行创建新的终端实例（滚动历史行数由全局设置决定，默认 10,000 行），同一次运行折叠、展开和切换选择均沿用该实例。SwiftTerm 的 forkpty 建立控制终端；应用辅助入口继续按独立 argv 加载登录 Zsh 环境并进入工作目录，不拼接用户参数为 Shell 源码。

ExecutionSession 接收启动失败和最终退出回调，展示退出码；终端 Ctrl+C 作用于前台任务，停止按钮发送进程组信号。应用不记录键盘输入，日志导出从终端解析后的活动缓冲区生成。旧 execution 字段只用于兼容解码，保存时省略。

SwiftTerm 的 MIT 许可证随 App 放入 Resources/ThirdPartyNotices.txt。升级组件时同步更新精确版本、Package.resolved、许可证和构建工具要求。

构建脚本关闭 SwiftTerm 的可选 PortableGraphics trait，并启用 SwiftPM 未使用依赖裁剪；macOS 使用系统图像能力，不需要下载跨平台 PNG 解码库。脚本要求 Swift 6.3 或更高版本；编译器和包管理器缓存均放在项目的 .build 内。

## Workspace 生命周期

WorkspaceStore 使用 UserDefaults 的 workspaceRegistry.v1 保存版本化登记（稳定 ID、显示名称、绝对目录、顺序和选中项），不会修改脚本库内容。首次启动且没有登记时，将旧 libraryDirectory 迁移为首个 Workspace。重复目录按标准化和解析符号链接后的路径判定。

ScriptStore 继续只负责一个库。WorkspaceStore 按 Workspace ID 缓存 ScriptStore 与 WorkspaceSession，后者只在内存保存选中脚本及按脚本 ID 分组的参数值；不会把参数写入偏好。未访问的库延迟加载，已加载的库独立监测配置变化。失效目录保留登记；重新定位沿用 ID，但替换该库的路径和配置内容。

WorkspaceRootView 承载当前 RunnerView 和全局 TaskOutputView。切换只替换上部浏览视图，任务由全局 ProcessRunner 管理、终端由各 ExecutionSession 持有。ExecutionSession 在启动时记录 Workspace ID、名称、脚本 ID 及已解析的命令目录；运行中的名称是启动时快照。活动状态遍历全部运行会话，通过 Workspace ID 与脚本 ID 共同判断；同一脚本多次运行使用独立会话 ID 和记录 ID。

移除和重新定位都检查全部运行任务所属的 Workspace；面板打开后到确认之间如有任务启动，会在实际操作时再次检查。移除不删除任何库文件。AppPreferences 保存终端字体、下次会话的历史行数和侧栏显隐，设置窗口使用单例原生 Window（⌘,），主窗口同样为单例，避免两个主窗口同时挂载同一终端视图。

## 持久执行日志

RunLogWriter 为每次执行创建脚本父目录下的 logs/<原始脚本文件名>/，使用时间与 UUID 生成 .log 和 .json 文件对。元数据不保存命令参数。初始化文件失败会阻止任务启动；执行中的写入失败向输出区发布警告。元数据在结束时原子替换，正常退出 App 会等待结束记录同步落盘。意外退出留下 outcome=running 的记录在非活动会话中显示为未正常结束。

RunnerTerminalView 使用 SwiftTerm TerminalView 与独立 LocalProcess，在有序的主队列数据回调中把 PTY 输出分别交给 RunLogWriter 和终端解析器，键盘数据仅发给 PTY。日志写入在独立串行队列进行，PlainLogDecoder 按字节跨数据块过滤 ANSI，保留 UTF-8 字节顺序；CR 进度刷新转为换行，不依赖终端缓冲区快照，所以不受滚动历史上限影响。应用的开始/结束消息也按顺序写入日志。

HistoryDirectories 在 UserDefaults 中只索引日志目录；读取历史时同时发现当前已配置脚本的标准日志位置。HistoryViewModel 在后台扫描和解析元数据，校验日志文件名必须是同目录 .log 文件，通过 UUID 去重并按开始时间倒序。日志按 256 KiB 分页读取，UTF-8 边界重叠避免有效字符跨页丢失；过期异步请求用 generation 拦截，避免快速切换记录时显示其他记录的内容。

ExecutionHistoryView 是输出区打开的 sheet，支持 Workspace/脚本筛选、搜索、执行记录列表、分页、刷新和 Finder 定位。日志数据不会因为清空终端、移除配置或移除 Workspace 而删除。

## 多执行会话与输出选择

ProcessRunner 保留应用级入口，管理 sessions、selectedSessionID、运行集合和历史写入聚合状态。每次 run 创建一个只能启动一次的 ExecutionSession，拥有独立 PTY、终端、停止信号和 RunLogWriter。运行入口不再受全局 isRunning 限制；isRunning 表示任意会话运行中，selectedIsRunning 专供当前终端操作使用。新增任务时，如果已有任务运行则保留当前终端选择。

TaskOutputView 使用 HSplitView 在输出左侧显示运行与完成列表；当前选中终端通过持久 NSView 重新挂载，其他终端保留在所属会话内继续收集输出。移出已完成任务仅释放结束且日志已落盘的会话，不删除历史文件。ProcessRunner 转发子会话变更，同时聚合全部活动记录与待保存记录，供历史删除保护使用。退出前等待各会话日志完成，Workspace 移除和重新定位按目标 ID 检查全部活动会话。

## 系统定时执行

`ScheduleStore` 由 App 持有，保存配置快照到 Application Support，`LaunchAgentService` 安装固定路径执行器并通过 `launchctl bootstrap/bootout` 管理当前用户 GUI 域的独立计划。`StartCalendarInterval` 表达日历计划，`StartInterval` 表达固定间隔；日历计划同时做 60 秒到期核对，以处理完整年份、时区变化和错过时间。`RunAtLoad` 用于登录后最多补执行一次。

`EntryPoint --run-schedule <配置路径>` 在 SwiftUI App 启动前分流，整个执行无需 NSApplication 或主窗口。`ScheduleExecutor` 持有每计划的 `flock`，原子写入消费记录后通过 `--execute-script` 启动独立进程组，合并管道收集 stdout/stderr，使用现有 `RunLogWriter` 写日志与历史。标准输入为空，不创建 PTY。停止请求以执行记录 ID 匹配，避免旧停止请求影响下一次运行；TERM 后可升级为 KILL。

配置、运行状态、控制请求相互分离；JSON 使用毫秒时间戳，写入前创建 0600 临时文件并原子替换，锁文件保持稳定 inode。App 读取和修复崩溃状态也使用同一把锁，避免覆盖后台刚完成的结果。运行状态损坏时执行器拒绝重新执行，防止重复产生副作用。一次性时刻在启动前消费，失败不自动重试。

App 每秒读取运行状态，把最近一次后台运行导入 `ProcessRunner`。后台会话只读尾随日志，并纳入 Workspace、脚本、历史删除保护；停止转为控制文件，不依赖 PTY。若 UI 错过两次运行之间的完成状态，会从前一次历史元数据补齐结果。退出检查只阻止仍有手动 PTY 的情况，后台任务由 launchd 独立管理。

测试默认只使用临时脚本和模拟系统服务；`RUNNER_TEST_LAUNCHD=1 bash test.sh` 额外注册一个位于临时目录的真实 LaunchAgent，验证系统触发与卸载。此项需在可访问当前用户 launchd GUI 域的环境运行；完成后不会留下系统任务。`RUNNER_CAPTURE_UI=1` 输出原生面板截图到 /tmp。
