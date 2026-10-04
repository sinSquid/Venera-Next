# VeneraNext 2026-10-04 改动与验证追踪

> 日期：2026-10-04（Asia/Shanghai）。本记录汇总本次对话当天完成的检查、修复、性能优化、提交、构建和安装。它是一次工作快照；后续修改请追加日期、提交与验证结果，保留原有结果的适用范围。

## 1. 范围与当前状态

| 项目 | 记录 |
|---|---|
| 仓库 | `/Users/sin/code/mine/Venera-Next` |
| Remote | `git@github.com:sinSquid/Venera-Next.git` |
| 分支 | `main` |
| 本次检查开始前基线 | `3772f65b77acd05bc48849ec69f542c8b90ce291` |
| 最终代码提交 | `f52d37ac21a0daa33a9ea1840697489da13eee4f` |
| 已推送范围 | `3772f65..f52d37a`，共 **12 个提交**；编写本记录前本地 HEAD 与 `origin/main` 一致 |
| 代码差异 | **79 个文件，新增 5,597 行、删除 697 行**：39 个 `lib/` 文件、38 个 `test/` 文件、`CHANGELOG.md`、`macos/Podfile` |
| 版本 | `1.17.0+228`；本次未修改 `pubspec.yaml` 或 `pubspec.lock` |
| 最终验证 | Flutter 测试 **1,352 通过、15 跳过**；分析器 **0 error、0 warning、56 info** |
| Android | 最新提交的 ARM64 Release APK 已构建，并覆盖安装到已连接的 PJE110 手机 |
| 本汇总的保存 | 仓库：`doc/experiments/change_tracking_2026_10_04.zh.md`；另有 `outputs/` 下载副本 |

差异统计不包含本记录与文档索引改动，这部分作为独立文档提交维护。`CHANGELOG.md` 包含更早的工作，本次只归纳上述提交范围。

代码链接固定到 `f52d37a`，方便以后对照当时实现；完整变更文件清单见附录。代码检查和测试覆盖了大量路径，但不表示所有运行环境、输入组合及真机交互都已验证。

## 2. 提交清单

| 提交 | 时间（+08:00） | 内容 |
|---|---|---|
| [c0fcf0c](https://github.com/sinSquid/Venera-Next/commit/c0fcf0c96346b483a5eacda5908997e246b32836) | 20:34:12 | fix(network): 修复缓存隔离、下载校验与取消处理 |
| [ecd05ec](https://github.com/sinSquid/Venera-Next/commit/ecd05ec53ded0bb595c2aacce16b9e275d2d6041) | 20:34:13 | fix(storage): 保护文件生命周期并优化批量存储操作 |
| [14d0c34](https://github.com/sinSquid/Venera-Next/commit/14d0c3444da9acf14f5195512c1f339eb38e3c41) | 20:34:13 | fix(ui): 修复分页竞态与图片资源生命周期 |
| [eff6046](https://github.com/sinSquid/Venera-Next/commit/eff6046bd87eed04e9406d84bc0a4a311ecb12a5) | 20:34:13 | fix(comic-source): 合并保存时等待实际写盘 |
| [99107a4](https://github.com/sinSquid/Venera-Next/commit/99107a4d6d730084421bd40eeeebed3dba3875c0) | 20:34:13 | fix(settings): 处理认证异常与数据操作取消 |
| [98cd124](https://github.com/sinSquid/Venera-Next/commit/98cd124b2267705b82fd7cf2bf88608792936b54) | 20:34:13 | fix(macos): 对齐原生依赖最低部署目标 |
| [5676768](https://github.com/sinSquid/Venera-Next/commit/5676768f20aeb202fd8fa508d479aaee2073ff40) | 20:34:13 | docs: 记录全库复查修复与性能优化 |
| [94d4284](https://github.com/sinSquid/Venera-Next/commit/94d4284848c5ad66cd2ef070a7fc56f17a78b8ca) | 21:09:08 | perf(reader): 按可见区域构建章节目录并复用索引 |
| [c43470a](https://github.com/sinSquid/Venera-Next/commit/c43470a4cfc911b2e3032649e4a35aa5c0748685) | 21:09:08 | perf(images): 精简图片缓冲并释放取消监听 |
| [cc3dc27](https://github.com/sinSquid/Venera-Next/commit/cc3dc278e69e167b783e640ac6663d01db814f74) | 21:09:08 | perf(cache): 为清理查询建立索引并压缩写入快照 |
| [4fb646f](https://github.com/sinSquid/Venera-Next/commit/4fb646f66d5a10959eb333840577e477b2d16d21) | 21:09:08 | perf(favorites): 减少批量导入和删除的重复查询 |
| [f52d37a](https://github.com/sinSquid/Venera-Next/commit/f52d37ac21a0daa33a9ea1840697489da13eee4f) | 21:09:08 | docs: 记录章节图片缓存与收藏性能优化 |

前 7 个提交包含多轮复查的修复及第一批优化；后 5 个提交包含章节、图片、缓存、收藏的进一步优化和更新日志。

## 3. 改动、入口与维护要点

### 3.1 网络响应缓存、Cookie 与分块下载

| 改动 | 生产入口 | 回归入口 |
|---|---|---|
| 隔离不同请求头、凭据和响应格式；请求头归一化后比较；缓存写入与命中均复制可变数据和头列表 | [lib/network/cache.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/network/cache.dart) | [test/network/cache_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/network/cache_test.dart) |
| 带 body 的 GET、HTTP `no-store` / `no-cache` 绕过缓存；只存完整 200 响应；HEAD 校验失败回退 GET，取消继续传播 | 同上 | 同上 |
| Secure Cookie 仅用于 HTTPS；路径前缀按 `/` 边界匹配；Max-Age 优先于 Expires，非正数删除 Cookie | [lib/network/cookie_jar.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/network/cookie_jar.dart) | [test/network/cookie_jar_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/network/cookie_jar_test.dart) |
| 校验 HEAD 长度、Range 范围、总量、编码、实际字节数及续传元数据；释放失败响应流与客户端 | [lib/network/file_downloader.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/network/file_downloader.dart) | [test/network/file_downloader_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/network/file_downloader_test.dart) |

维护要点：

- 响应缓存仍是**每 URI 一条记录**，命中前验证请求身份；并未改成可并存多个凭据版本的缓存。
- 复制响应时保留 JSON、`List<int>`、`Uint8List` 等类型。内部 `cache-time:no` 表示强制刷新，后续响应仍可能缓存，不能与 HTTP `no-store` 混用。
- 分块下载只允许整个文件的一次请求接受 200。续传记录必须连续、无重叠、无越界且下载量合法；损坏记录抛出 `FormatException` 并保留数据文件与 sidecar 以供排查。
- 原数据文件缺失或长度变化时，旧偏移失效并重新准备下载。失败不意味着回滚全部已写入字节；后续修复需维持文件、范围和恢复状态的一致性。

### 3.2 图片加载、缓冲与资源释放

| 改动 | 生产入口 | 回归入口 |
|---|---|---|
| 缩略图缓存命中后直接结束；取消不再触发备用下载；释放异步到达但未消费的 JS 回调 | [lib/network/images.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/network/images.dart)、[lib/foundation/image_provider/cached_image.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/foundation/image_provider/cached_image.dart) | [test/network/images_lifecycle_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/network/images_lifecycle_test.dart)、[test/foundation/cached_image_provider_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/foundation/cached_image_provider_test.dart) |
| 使用 `BytesBuilder(copy: false)` 拼接独立字节块，减少普通 List 的扩容、槽位和最终转换成本 | [lib/network/images.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/network/images.dart) | [test/network/images_buffer_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/network/images_buffer_test.dart) |
| 无取消信号时直接读取；实际取消及时解除流订阅；所有结束路径清理 iterator | [lib/network/image_stream.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/network/image_stream.dart)、[lib/foundation/image_provider/base_image_provider.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/foundation/image_provider/base_image_provider.dart)、[lib/foundation/image_provider/reader_image_processing.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/foundation/image_provider/reader_image_processing.dart) | [test/network/image_stream_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/network/image_stream_test.dart)、[test/foundation/base_image_provider_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/foundation/base_image_provider_test.dart)、[test/foundation/reader_image_provider_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/foundation/reader_image_provider_test.dart)、[test/foundation/reader_image_processing_native_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/foundation/reader_image_processing_native_test.dart) |
| 收藏图片离线读取使用正确的漫画/章节标识与页码；空 URL 缓存身份包含页号；取消后不刷新 URL 或写缓存 | [lib/features/history/image_favorites_provider.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/history/image_favorites_provider.dart) | [test/features/history/image_favorites_provider_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/history/image_favorites_provider_test.dart) |

维护要点：

- `copy: false` 的前提是上游 chunk 所有权独立。本次确认锁定版本的 rhttp / flutter_rust_bridge 解码通过 `Uint8List.fromList` 产生独立字节块；更换 adapter 后需重新检查是否复用可变缓冲。
- 缓存响应和缓存排队写入仍须复制，不能把这一优化扩展成所有路径均不复制。
- 取消信号允许 `null`。直接导出不应使用一个静态、永不完成的 Future 代替空信号，否则逐 chunk 的 `Future.any` 会累积未解除的监听。
- `shared_request_stream.dart`、`request_scope.dart`、`reader_image.dart` 本次没有生产代码变更；不要将既有共享请求机制记作本次新增的全局请求去重。

### 3.3 磁盘缓存与 SQLite

生产入口：[lib/foundation/cache_scan.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/foundation/cache_scan.dart)、[lib/foundation/cache_manager.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/foundation/cache_manager.dart)、[lib/foundation/sqlite_connection.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/foundation/sqlite_connection.dart)。

回归入口：[test/foundation/cache_manager_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/foundation/cache_manager_test.dart)、[test/foundation/sqlite_connection_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/foundation/sqlite_connection_test.dart)。

- 启动目录扫描一次读取已登记的 `(dir, name)` 集合，替代逐文件查表；删除疑似孤立文件前仍再次确认归属。
- 修复过期缓存清理后容量未扣减、空缓存容量未归零、选择和删除使用不同时间边界的问题。
- 增加 `cache_expires(expires)`、`cache_file(dir, name)` 索引；已有数据库通过 `CREATE INDEX IF NOT EXISTS` 补齐。
- 排队写入前同步生成 `Uint8List.fromList` 快照，避免调用方后续修改污染写盘内容，同时缩小中间缓冲。
- `busy_timeout` 提前到可能获取锁的 journal PRAGMA 之前，避免短时写事务与后台连接初始化重叠时立即失败；回归包含独立 Isolate 持锁场景。

修改时必须保留目录与文件名的联合身份、入队前快照、删除前复核以及锁等待顺序。索引收益及维护成本见性能记录。

### 3.4 收藏、本地库、WebDAV 与备份

| 改动 | 生产入口 | 回归入口 |
|---|---|---|
| 新收藏目录导入用连续顺序号，成功插入后才递增/递减；免除每条 MIN/MAX 查询，保留来源身份去重、首尾排序和首条记录 | [lib/features/favorites/favorite_folder_import.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/favorites/favorite_folder_import.dart) | [test/features/favorites/favorite_folder_import_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/favorites/favorite_folder_import_test.dart)：900 条批量导入、重复及不同来源 |
| 批量删除复用事务后查询到的跨目录引用计数，只有最后一个引用消失才清理共享封面，清理后通知 | [lib/features/favorites/favorites_manager.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/favorites/favorites_manager.dart) | [test/features/favorites/favorites_manager_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/favorites/favorites_manager_test.dart)：406 个身份跨 400 条查询批次、旧索引快照场景 |
| 图片收藏通过 Set 去重，过滤非法章节/页码，保留首项并排序；直接生成紧凑 JSON，不再 JSON 往返复制 | [lib/features/history/image_favorites_repository.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/history/image_favorites_repository.dart) | 既有 [test/features/history/image_favorites_repository_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/history/image_favorites_repository_test.dart)（该测试文件本次未修改） |
| 保存已下载章节时保序去重，避免重复保存使列表持续膨胀 | [lib/features/local_comics/local_repository.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/local_comics/local_repository.dart) | [test/features/local_comics/local_repository_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/local_comics/local_repository_test.dart) |
| 本地删除规范化原生点路径，同时保留 SAF URI 与共享目录保护 | [lib/features/local_comics/local_deletion_paths.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/local_comics/local_deletion_paths.dart) | [test/features/local_comics/local_deletion_paths_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/local_comics/local_deletion_paths_test.dart)、[test/features/local_comics/local_deletion_repository_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/local_comics/local_deletion_repository_test.dart) |
| pause/cancel 同步抛错时仍等待当前及此前清理，防止后续任务或退出越过存储清理 | [lib/features/local_comics/download_queue.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/local_comics/download_queue.dart) | [test/features/local_comics/download_queue_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/local_comics/download_queue_test.dart) |
| 写权限检测改用 UUID 独占临时文件，只删除自身创建的探测文件 | [lib/features/local_comics/local.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/local_comics/local.dart) | [test/features/local_comics/local_manager_initialization_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/local_comics/local_manager_initialization_test.dart)：保留已有 `venera_test` |
| 已有 WebDAV 索引刷新遇到子目录失败时保留完整旧库；首次扫描仍允许尽力发现；同步通过 ID 索引减少重复查找 | [lib/features/webdav_library/webdav_library_discovery.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/webdav_library/webdav_library_discovery.dart)、[lib/features/webdav_library/webdav_library_synchronizer.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/webdav_library/webdav_library_synchronizer.dart) | [test/features/webdav_library/webdav_library_source_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/webdav_library/webdav_library_source_test.dart) |
| 同批备份上传成功后才更新远端文件名集合，失败可重试；备份/恢复使用独立父目录，保留原文件名，避免长文件名超限及误清理 | [lib/features/sync/comic_backup.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/sync/comic_backup.dart) | [test/features/sync/comic_backup_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/sync/comic_backup_test.dart) |

测试夹具调整：`pdf_import_test.dart` 与部分收藏测试等待后台身份索引刷新，避免安装 SQLite 测试触发器时与启动读取争锁。这不是本次新增的 PDF 导入生产逻辑修复。

### 3.5 文件选择、准备与保存

生产入口：[lib/foundation/file_interaction.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/foundation/file_interaction.dart)。

回归入口：[test/foundation/file_selection_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/foundation/file_selection_test.dart)、[test/foundation/file_interaction_lifecycle_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/foundation/file_interaction_lifecycle_test.dart)。

- 用计数跟踪重叠选择操作，避免一个操作结束就错误解除另一个操作的占用状态。
- Android 文件准备合并并发复制；dispose 等待迟到的临时文件，且只清理一次。
- 传入字节数据的导出和 iOS 导出使用独立临时目录，成功、取消、异常路径统一清理，避免共享临时路径覆盖来源文件；其他平台直接传入文件时使用原文件，不创建临时副本。
- 正确解码 file URI 的转义；iOS 目录选择异常按错误传播；macOS 目录选择接入桌面文件选择插件。

后续变更须保留来源文件与临时文件的所有权边界，不能把等待复制完成改成不等待的后台清理。

### 3.6 分页、搜索、预览与封面导出

| 改动 | 生产入口 | 回归入口 |
|---|---|---|
| 刷新取消旧作用域并重置页数；只有当前请求可更新结果；同步/异步失败均释放状态，初始数据使用独立可变副本 | [lib/components/loading.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/components/loading.dart) | [test/components/multi_page_loading_lifecycle_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/components/multi_page_loading_lifecycle_test.dart) |
| 漫画列表保存独立页面快照；恢复页面时重新请求未完成页，不复用旧请求或加载锁；旧请求的结果与 finally 均不得覆盖或解锁新请求；游标末页停止加载；解除屏蔽后重建有效 Hero ID | [lib/features/comic_widgets/comic_list.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/comic_widgets/comic_list.dart) | [test/features/comic_widgets/comic_list_lifecycle_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/comic_widgets/comic_list_lifecycle_test.dart)、[test/features/comic_widgets/comic_list_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/comic_widgets/comic_list_test.dart) |
| 聚合搜索换词/退出取消旧请求，异常恢复；横向结果按需构建；选项独立复制，切源重绑建议控制器，排除不支持搜索的来源 | [lib/features/search/aggregated_search_page.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/search/aggregated_search_page.dart)、[lib/features/search/search_result_page.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/search/search_result_page.dart) | [test/features/search/search_lifecycle_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/search/search_lifecycle_test.dart) |
| 探索混合分区各自持有列表，避免后续分区清空此前内容 | [lib/features/discovery/explore_page.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/discovery/explore_page.dart) | [test/features/discovery/explore_page_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/discovery/explore_page_test.dart) |
| 预览分页在 await 前上锁，失败后可重试，关闭时取消；收藏面板加载失败显示可重试错误态，避免访问未初始化目录，关闭时取消请求 | [lib/features/comic_details/thumbnails.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/comic_details/thumbnails.dart)、[lib/features/comic_details/favorite.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/comic_details/favorite.dart) | [test/features/comic_details/thumbnails_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/comic_details/thumbnails_test.dart)、[test/features/comic_details/favorite_panel_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/comic_details/favorite_panel_test.dart) |
| 封面导出提取公共入口，只读取首帧；同步缓存帧也解除监听；成功/失败释放 ImageInfo，正确处理 ByteData 偏移与编码失败，关闭后不保存 | [lib/features/comic_details/cover_export.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/comic_details/cover_export.dart)，由 [lib/features/comic_details/comic_page.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/comic_details/comic_page.dart)、[lib/features/comic_details/cover_viewer.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/comic_details/cover_viewer.dart) 调用 | [test/features/comic_details/cover_export_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/comic_details/cover_export_test.dart) |

### 3.7 阅读器章节与手势

生产入口：[lib/features/reader/chapters.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/reader/chapters.dart)、[lib/features/reader/gesture.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/reader/gesture.dart)。

回归入口：[test/features/reader/chapters_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/reader/chapters_test.dart)、[test/features/reader/auto_reading_viewport_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/reader/auto_reading_viewport_test.dart)。

- 章节目录使用固定 48 高度的 `SliverFixedExtentList`，按可见及缓存区域构建；一次生成章节索引、分组全局偏移与已下载章节 Set，减少跳转到长篇后段及倒序时反复遍历。
- 保留跨分组重复 ID 的独立条目及各自全局章节编号，维持正反序定位和状态展示；释放滚动等控制器。
- 页面退出取消 200 ms 单击判定 Timer，并释放手势识别器。7 种阅读模式有挂起点击期间退出的回归。
- `scaffold.dart` 本次仅移除未使用 import；自动阅读实现、ReaderController、ComicChapters 模型、路由和连续阅读布局没有在本范围重写。

### 3.8 源保存、认证与设置操作

| 改动 | 生产入口 | 回归入口 |
|---|---|---|
| 共享同一次 pending save 的调用者等待该次写盘，并共享其结果或错误；当前活动写入失败后，排队写入仍可能成功 | [lib/features/comic_source/source.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/comic_source/source.dart) | [test/features/comic_source/comic_source_save_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/comic_source/comic_source_save_test.dart) |
| 认证合并重复尝试，成功只回调一次；关闭时停止认证，迟到结果失效；平台异常保持锁定并可重试 | [lib/app_shell/auth_page.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/app_shell/auth_page.dart) | [test/app_shell/auth_page_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/app_shell/auth_page_test.dart) |
| 存储、缓存、导入导出保持忙碌状态；finally 关闭等待弹窗和清理临时文件；能力查询失败撤销认证启用，过期查询不能覆盖新状态 | [lib/features/settings/app.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/lib/features/settings/app.dart) | [test/features/settings/app_actions_test.dart](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/test/features/settings/app_actions_test.dart) |

设置导入可以在事务开始前取消；一旦提交阶段开始，需要完成提交或回滚，不能半途丢弃。认证原有的“不支持设备”兼容分支保留，本次不是认证策略重构。

### 3.9 macOS 构建修复

[macos/Podfile](https://github.com/sinSquid/Venera-Next/blob/f52d37ac21a0daa33a9ea1840697489da13eee4f/macos/Podfile) 的 post_install 将低于 12.0 或未声明的 Pod 部署目标提升到 12.0，与应用最低要求对齐；更高目标保持原值。解决新 Xcode 拒绝构建旧 Pod 部署目标的问题。

Android 单 ABI 覆盖、签名配置及 iOS 模拟器临时覆盖属于本机构建环境处理，未作为产品代码提交，详见第 6 节。

## 4. 性能记录与适用范围

下列数据用于证明具体热点的改进。除章节访问次数外均为三次测量的中位数；不可直接换算成整应用启动时间、帧率或真机内存收益。

| 项目 | 优化前 | 优化后 | 条件与解释 |
|---|---:|---:|---|
| 缓存目录扫描：1,000 文件 | 108.313 ms | 38.034 ms | 真实临时文件与 SQLite；包含 isolate 启动和扫描 |
| 缓存目录扫描：5,000 文件 | 1,023.214 ms | 90.468 ms | 相同条件，约 11.31 倍；不是整个应用启动 |
| 普通章节目录：Map 访问次数 | 9,499,158 | 6,000 | 3,000 章、当前第 2,500 章、textScaler=1.8；从打开至 pumpAndSettle，包含索引创建 |
| 分组章节目录：Map 访问次数 | 9,491,610 | 6,000 | 同上，单个章节组；计数包括 key 遍历和 lookup，不是耗时或 FPS |
| 图片缓冲：进程峰值 RSS | 538.92 MiB | 196.02 MiB | 9 张并发 × 2 MiB，每块 64 KiB；含约 154 MiB 运行时基线 |
| 图片缓冲：拼接耗时 | 187.532 ms | 3.956 ms | 相同合成负载；不含网络、解码、JS、磁盘和 Flutter 渲染 |
| SQLite：最旧缓存 LIMIT 10 | 130.729 ms | 1.413 ms | 30,000 行内存数据库，200 次查询 |
| SQLite：文件归属查询 | 99.366 ms | 0.719 ms | 同上 |
| SQLite：过期查询 | 78.764 ms | 0.650 ms | 同上；本负载过期查询返回零行 |
| 收藏导入 SQL 路径 | 625.90 ms | 45.69 ms | 8,000 个唯一身份加重复项；MIN/MAX 查询 8,000 → 0 |
| 收藏删除引用核对 SQL 路径 | 66.77 ms | 12.35 ms | 2,000 个身份 × 20 个目录；SELECT 40,100 → 100 |

方法与限制：

- 缓存扫描：文件各 1 字节且全部已登记，旧/新各预热一次，交替测三次；未模拟孤立文件删除。基线导出源码与 `3772f65` 对应文件逐字节一致。
- 图片缓冲：每种模式各三次独立进程运行；每次输出均为 18 MiB，端点 checksum 均为 315，该值不是完整内容哈希。
- 缓存索引：预热一次、测三次；建索引中位数 6.473 ms。200 次 touch 更新 0.643 → 0.628 ms，差异不足以支持“写入显著提速”的结论；增加索引也会占用空间并产生维护成本。
- 收藏基准：Python 内存 SQLite，`cached_statements=0`，复现 SQL 模式，不含 JSON 解析、文件删除、Flutter UI 或 fsync。耗时来自当时工具输出，保留了复现脚本，但未单独保存该次 JSON 结果。
- 后续需用真机 Profile 测量大图并发、长篇目录和连续阅读，确认端到端收益与内存峰值。

基准脚本及原始结果在第 8 节列出。

## 5. 验证结果

| 验证 | 结果 | 适用版本与边界 |
|---|---|---|
| 第三轮 Flutter 全量测试 | 1,325 通过，15 跳过 | 第一批提交阶段；日志 `round3-full-test-final.log` |
| 最终 Flutter 全量测试 | **1,352 通过，15 跳过** | 最终性能改动全部纳入；较第三轮增加 27 个通过用例；Windows 专用用例在本机跳过 |
| 最终 Flutter analyze | **0 error、0 warning、56 info** | 存在异步 BuildContext、类型推断等已有提示；不是零 lint 问题 |
| Python 脚本测试 | 56 项：53 通过、3 跳过 | 仓库 `.github/scripts/tests` |
| 仓库约束 | 通过 | 结构导入、架构依赖基线、版本同步、Git 依赖清单、Dart 格式和 `git diff --check` |
| 第三轮覆盖率 | **54.34%（17,499 / 32,201 行）**，322 个记录文件 | 来自 `round3-lcov.info`；最后一批性能修改后未重新统计，不能视为最终版本覆盖率 |
| macOS Debug | 构建成功 | 第一批提交阶段（`5676768` 对应代码）；有 Xcode 工具链搜索路径警告；未在最终性能提交后重建 |
| iOS ARM64 模拟器 Debug | 临时覆盖配置下构建成功 | 第一批阶段；最低系统临时设为 15.0、只构建 ARM64；仓库原 14.0 配置及 iOS 真机/分发构建未验证 |
| Android ARM64 Release | 最新 `f52d37a` 构建成功 | 最后一次为增量构建，Gradle 41.3 s；APK 约 22.4 MB |
| Android APK 静态校验 | 通过 | 证书、元数据、12 个 ARM64 ELF `.so` 和 `zipalign -P 16` 校验 |
| Android 安装 | 覆盖安装成功，手机 APK 哈希与产物一致 | Android SDK 36，PJE110，arm64-v8a；未执行完整启动及业务交互验收 |

`perf-cache-green.log` 名称不能代表最终成功：其内容是中间失败记录。判断最终状态应使用 `perf-full-test-final.log` 和 `perf-analyze-final.log`。

## 6. Android 包、安装与构建环境

### 6.1 交付与安装记录

| 项目 | 最终包 |
|---|---|
| 文件 | [VeneraNext-1.17.0-f52d37a-arm64-v8a-local-signed.apk](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/outputs/VeneraNext-1.17.0-f52d37a-arm64-v8a-local-signed.apk) |
| SHA-256 文件 | [VeneraNext-1.17.0-f52d37a-arm64-v8a-local-signed.apk.sha256](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/outputs/VeneraNext-1.17.0-f52d37a-arm64-v8a-local-signed.apk.sha256) |
| 字节数 | `22437191` |
| SHA-256 | `baef616d1e0603462fed124b4c6915720e18f4739f6267c8873f0f54518ce723` |
| 包名 | `com.github.cyrilpeng.veneranext` |
| 版本 | versionName `1.17.0`，ARM64 versionCode `2282`（基础 build 228 × 10 + ABI 编号 2） |
| 系统与 ABI | minSdk 24；target/compile SDK 36；只包含 `arm64-v8a` |
| 签名 | 用户选择的本地签名；使用本机现有 Android Debug 证书签署 Release 包 |
| 公开证书 SHA-256 | `b1eb550f5877883b7577bee314b3de3b23e89f2fa450b8faf0bfd3e0933911f6` |
| 安装 | `adb install -r` 覆盖更新；保留已有应用数据；最后更新时间 `2026-10-04 21:11:24 +08:00` |
| 安装核对 | 读取已安装 `base.apk`，SHA-256 与上述文件完全一致 |

前一版包 [VeneraNext-1.17.0-arm64-v8a-local-signed.apk](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/outputs/VeneraNext-1.17.0-arm64-v8a-local-signed.apk) 对应 `5676768`，22,433,819 字节，SHA-256 为 `a01e42b496818a2ac51fb5eef38395b2f389ce9ba1fe493a3c0bb231d9d41032`。两版版本号相同，以提交及哈希区分；后续测试以带 `f52d37a` 的包为准。

后续覆盖安装需继续使用同一证书。临时 `android/key.properties` 在打包后已移除；本文不记录私钥或密码。

### 6.2 环境和临时处理

| 工具 / 配置 | 本次使用 |
|---|---|
| Flutter / Dart | **3.41.4 / 3.11.1**，项目固定版本；本机另一 Flutter 版本未用于最终验证 |
| Flutter 路径 | `/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/flutter-3.41.4/bin/flutter` |
| Java | JDK 17：`/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home` |
| Android SDK | `/Users/sin/Library/Android/sdk` |
| Gradle / AGP / Kotlin | 8.14 / 8.12.3 / 2.1.0 |
| NDK | 应用 28.0.13004108；插件同时需要 27.0.12077973 |
| Rust | 1.85.1，Android target `aarch64-linux-android` |
| Gradle 隔离目录 | `/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/android-gradle`，复用本机缓存并加载本地 init script |
| Rust 隔离目录 | `/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/rust`；串行 rustup 包装避免多个插件并发安装 target |

仓库 Android 配置默认构建三种 ABI 与 universal 包，因此仅传 Flutter 的 ARM64 参数不足以限制所有原生依赖。实际通过 [android-arm64.init.gradle](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/android-arm64.init.gradle) 在 `finalizeDsl` 阶段清理应用的 NDK ABI filters、将应用 splits 限定为 ARM64，并将 library 的 NDK filters 限定为 ARM64。应用 ABI filters 与 splits 不能同时冲突。该脚本未提交到仓库。

首次下载依赖遇到 Google Maven TLS 中断，通过重试和从官方地址获取、校验 SHA-1 后补入本机 Gradle 缓存解决，未关闭 TLS 校验或更改仓库依赖。iOS 临时覆盖用于绕开 Xcode 27 与 Flutter 3.41.4 的多架构 `lipo -verify_arch` 兼容问题；没有修改项目正式的 iOS 最低系统要求。

生成的 Xcode scheme、Pod 锁文件、Git ignore 迁移和构建报告变动均已清理。最终产品代码变更中的原生构建修复只有前述 `macos/Podfile`。

### 6.3 后续复查与打包命令

以下命令在仓库根目录执行。路径适用于本次机器；迁移机器时需重新准备固定 SDK、原生依赖、隔离缓存和签名配置。

```bash
cd /Users/sin/code/mine/Venera-Next
VENERA_TASK_ROOT=/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next
VENERA_FLUTTER="$VENERA_TASK_ROOT/work/flutter-3.41.4/bin/flutter"
VENERA_DART="$VENERA_TASK_ROOT/work/flutter-3.41.4/bin/dart"

"$VENERA_FLUTTER" pub get --enforce-lockfile
python3 .github/scripts/check_structure_imports.py
python3 .github/scripts/check_architecture_dependencies.py
python3 .github/scripts/release_version.py --check
python3 -m unittest discover -s .github/scripts/tests -p 'test_*.py'
"$VENERA_DART" tool/check_git_dependencies.dart
"$VENERA_FLUTTER" analyze --no-pub
"$VENERA_FLUTTER" test --no-pub
git diff --check
```

打包前需从本机同一签名配置恢复被忽略的 `android/key.properties`，确认 `work/android-gradle/init.d/` 仍加载上述 ARM64 脚本。依赖已按锁文件解析后执行：

```bash
env JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home \
  GRADLE_USER_HOME="$VENERA_TASK_ROOT/work/android-gradle" \
  CARGO_HOME="$VENERA_TASK_ROOT/work/rust/cargo" \
  RUSTUP_HOME="$VENERA_TASK_ROOT/work/rust/rustup" \
  PATH="$VENERA_TASK_ROOT/work/rust/serial-bin:$VENERA_TASK_ROOT/work/rust/cargo/bin:$PATH" \
  RUSTUP_REAL_BINARY="$VENERA_TASK_ROOT/work/rust/cargo/bin/rustup" \
  RUSTUP_LOCK_FILE="$VENERA_TASK_ROOT/work/rust/rustup.lock" \
  "$VENERA_FLUTTER" build apk --release --target-platform android-arm64 --split-per-abi --no-pub
```

产物入口为 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。安装前通过 `adb devices -l` 确认目标手机，再用 `adb -s <设备序列号> install -r <APK完整路径>` 覆盖安装，核对包版本与已安装 APK 哈希。构建后移除临时签名配置并检查 `git status`，避免把机器配置和生成文件混入代码变更。

## 7. 后续跟踪事项

| 状态 | 优先级 | 事项 | 完成判据 |
|---|---|---|---|
| 待做 | 高 | 最新 Android 包业务冒烟 | 实测启动、搜索换词/退出、列表刷新、长目录正反序跳转、图片取消/收藏/导出、下载暂停续传；记录机型、步骤、日志 |
| 待做 | 高 | 真机文件与认证流程 | 覆盖 SAF、取消导入导出、平台认证异常与重试；核对数据和临时文件保留/清理 |
| 待做 | 中 | 端到端性能测量 | Profile 模式记录目录打开耗时、滚动帧、并发大图 RSS 与退出后对象释放；不要沿用合成基准当作真机结论 |
| 待做 | 中 | Windows / Linux 原生验证 | 对应平台运行原生构建及跳过用例；本机 15 个 Windows 用例尚未执行 |
| 待做 | 中 | Apple 平台最终版本验证 | 重建最终代码；验证标准 iOS 14.0 配置、模拟器架构和 iOS 真机；排查 Xcode 工具链警告 |
| 待做 | 中 | 更新覆盖率与分析器提示 | 在最终版本重跑 coverage；逐项判断 56 条 info，优先处理确有失效上下文风险的路径 |
| 可选 | 低 | 将本机 ARM64 构建过程固化为 CI 参数 | 保留默认多 ABI 发布，同时支持可重复的单 ABI 构建；独立评审后再修改正式构建配置 |

修改建议：先定位第 3 节对应实现与回归测试，再查看提交差异；新增故障应记录触发条件和失败回归，修复后跑相关测试及全量检查。涉及缓存快照、文件所有权、取消清理、事务边界和共享封面引用计数的优化，必须保留对应不变量。

需要撤回某项改动时，在独立分支审阅对应提交并使用新的 revert 提交，避免对已共享的 `main` 强制重置。批次中的修复可能互相依赖，回退后重新运行相关回归；覆盖安装旧包仍需匹配签名并考虑数据兼容性。

## 8. 证据与记录维护

本机证据根目录：`/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work`。这些日志、SDK 和基准脚本未提交到仓库；换机或清理工作目录前，按需归档。本文核心结论、边界和 APK 哈希已直接记录，便于脱离日志阅读。

| 证据 | 用途 |
|---|---|
| [perf-full-test-final.log](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/perf-full-test-final.log) | 最终 1,352 通过、15 跳过 |
| [perf-analyze-final.log](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/perf-analyze-final.log) | 最终 56 info、无 error/warning |
| [round3-full-test-final.log](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/round3-full-test-final.log)、[round3-analyze-final.log](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/round3-analyze-final.log) | 第三轮检查快照 |
| [round3-lcov.info](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/round3-lcov.info) | 第三轮覆盖率原始数据 |
| [round3-macos-build-final.log](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/round3-macos-build-final.log)、[round3-ios-arm64-validation.log](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/round3-ios-arm64-validation.log) | Apple 平台较早阶段构建证据 |
| [android-arm64-f52d37a-build.log](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/android-arm64-f52d37a-build.log) | 最新 Android 构建 |
| [cache-scan-benchmark.json](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/cache-scan-benchmark.json)、[cache_scan_benchmark.dart](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/cache_scan_benchmark.dart) | 缓存扫描基准结果与脚本 |
| [image-buffer-benchmark.json](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/image-buffer-benchmark.json)、[image_buffer_benchmark.dart](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/image_buffer_benchmark.dart) | 图片字节缓冲基准结果与脚本 |
| [cache-index-benchmark.json](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/cache-index-benchmark.json)、[cache_index_benchmark.dart](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/cache_index_benchmark.dart) | SQLite 索引基准结果与脚本 |
| [favorites_sql_perf.py](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/favorites_sql_perf.py) | 收藏 SQL 模式基准复现脚本 |
| [perf-chapters-red.log](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/perf-chapters-red.log)、[perf-reader-favorites-green.log](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/perf-reader-favorites-green.log) | 章节优化前失败/优化后回归记录 |
| [perf-images-cache-green.log](/Users/sin/Documents/Codex/2026-10-04/users-sin-code-mine-venera-next/work/perf-images-cache-green.log) | 图片与缓存相关回归通过记录 |

后续记录可追加以下表格，每次填写实际提交与实际执行的验证，避免沿用旧结果：

| 日期 | 问题/改动 | 文件或提交 | 验证与证据 | 尚未验证 |
|---|---|---|---|---|
| 2026-10-04 | 完成本次修复、优化、推送和 Android 安装；编写追踪记录 | `3772f65..f52d37a` | 见第 4～6、8 节 | 见第 7 节 |

## 附录：本次 79 个变更文件

以下路径相对于仓库根目录，来自 `git diff --name-status 3772f65..f52d37a`。`A` 表示新增，`M` 表示修改。

```text
M	CHANGELOG.md
M	lib/app_shell/auth_page.dart
M	lib/components/loading.dart
M	lib/features/comic_details/comic_page.dart
A	lib/features/comic_details/cover_export.dart
M	lib/features/comic_details/cover_viewer.dart
M	lib/features/comic_details/favorite.dart
M	lib/features/comic_details/thumbnails.dart
M	lib/features/comic_source/source.dart
M	lib/features/comic_widgets/comic_list.dart
M	lib/features/discovery/explore_page.dart
M	lib/features/favorites/favorite_folder_import.dart
M	lib/features/favorites/favorites_manager.dart
M	lib/features/history/image_favorites_provider.dart
M	lib/features/history/image_favorites_repository.dart
M	lib/features/local_comics/download_queue.dart
M	lib/features/local_comics/local.dart
M	lib/features/local_comics/local_deletion_paths.dart
M	lib/features/local_comics/local_repository.dart
M	lib/features/reader/chapters.dart
M	lib/features/reader/gesture.dart
M	lib/features/reader/scaffold.dart
M	lib/features/search/aggregated_search_page.dart
M	lib/features/search/search_result_page.dart
M	lib/features/settings/app.dart
M	lib/features/sync/comic_backup.dart
M	lib/features/webdav_library/webdav_library_discovery.dart
M	lib/features/webdav_library/webdav_library_synchronizer.dart
M	lib/foundation/cache_manager.dart
M	lib/foundation/cache_scan.dart
M	lib/foundation/file_interaction.dart
M	lib/foundation/image_provider/base_image_provider.dart
M	lib/foundation/image_provider/cached_image.dart
M	lib/foundation/image_provider/reader_image_processing.dart
M	lib/foundation/sqlite_connection.dart
M	lib/network/cache.dart
M	lib/network/cookie_jar.dart
M	lib/network/file_downloader.dart
M	lib/network/image_stream.dart
M	lib/network/images.dart
M	macos/Podfile
A	test/app_shell/auth_page_test.dart
A	test/components/multi_page_loading_lifecycle_test.dart
A	test/features/comic_details/cover_export_test.dart
A	test/features/comic_details/favorite_panel_test.dart
A	test/features/comic_details/thumbnails_test.dart
M	test/features/comic_source/comic_source_save_test.dart
A	test/features/comic_widgets/comic_list_lifecycle_test.dart
M	test/features/comic_widgets/comic_list_test.dart
A	test/features/discovery/explore_page_test.dart
M	test/features/favorites/favorite_folder_import_test.dart
M	test/features/favorites/favorites_manager_test.dart
A	test/features/history/image_favorites_provider_test.dart
M	test/features/local_comics/download_queue_test.dart
M	test/features/local_comics/import_export/pdf_import_test.dart
M	test/features/local_comics/local_deletion_paths_test.dart
M	test/features/local_comics/local_deletion_repository_test.dart
M	test/features/local_comics/local_manager_initialization_test.dart
M	test/features/local_comics/local_repository_test.dart
M	test/features/reader/auto_reading_viewport_test.dart
A	test/features/reader/chapters_test.dart
A	test/features/search/search_lifecycle_test.dart
A	test/features/settings/app_actions_test.dart
M	test/features/sync/comic_backup_test.dart
M	test/features/webdav_library/webdav_library_source_test.dart
M	test/foundation/base_image_provider_test.dart
M	test/foundation/cache_manager_test.dart
M	test/foundation/cached_image_provider_test.dart
A	test/foundation/file_interaction_lifecycle_test.dart
M	test/foundation/file_selection_test.dart
M	test/foundation/reader_image_processing_native_test.dart
M	test/foundation/reader_image_provider_test.dart
M	test/foundation/sqlite_connection_test.dart
M	test/network/cache_test.dart
A	test/network/cookie_jar_test.dart
M	test/network/file_downloader_test.dart
M	test/network/image_stream_test.dart
A	test/network/images_buffer_test.dart
M	test/network/images_lifecycle_test.dart
```
