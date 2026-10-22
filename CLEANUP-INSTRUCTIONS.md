# 资源清理

当前网页使用的本地资源仅有：

- restaurant-logo.143b3cd95e08.webp：原餐厅页头 Logo
- fw-icon-v2.svg：浏览器矢量图标
- fw-icon-v2-32.png：浏览器 PNG 兼容图标
- fw-staff-hub-touch-v2.png：手机主屏幕 FW + STAFF HUB 图标

已删除全部节日图片、样式和页面，以及旧 SH 图标、旧版图标文件和未采用的整套 FW 页头草稿。网页保持原餐厅 Logo 与普通 Staff Hub 文字。

SQL 文件由 roster-database-test.mjs 按依赖顺序执行，全部保留用于测试与数据库维护。roster-leave-requests.sql 还包含换班函数，roster-disable-leave.sql 负责禁用旧请假入口，两者都不是废弃文件。不要仅凭文件名删除或在生产环境随意重跑旧迁移。

SQL 和测试文件不会被浏览器下载，保留它们不会增加网页流量，也不会向数据库新增记录。

## 2026-10-23 点单学习资料

仓库根目录新增并仅保留两张带内容摘要的 JPG 和对应 ZIP 下载包。第三张局部近照、旧包、预览草稿和重复事件未纳入发布。图片更新时使用新的摘要文件名，避免旧资源缓存。保留仍在使用的菜单、班表离线缓存和语言设置；未新增 Service Worker。
