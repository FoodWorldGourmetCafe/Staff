# Staff 更新说明

本包基于 main 的 5a88d7c，包含 index.html、christmas.html 和数据库更新。

1. 在 Supabase SQL Editor 执行 roster-service-requests.sql。需要先安装项目原有的 roster-actual-adjustments.sql 和 roster-draft-request-lock.sql。
2. 执行 roster-service-requests-test.sql 验证数据库流程；测试数据会回滚。
3. 将两份 HTML 替换到网站仓库，再发布网站。

新增行为：
- 草稿中点击已分配班次可申请划班，批准前原班次不变，批准后显示不可用横线。
- 管理员登录后默认管理员模式，切微信或浏览器后台保留模式。手动 Staff Mode 保留选择；重新登录默认管理员模式。退出登录会撤销管理员权限。
- 点击 Bathroom 日期可提交换人或 Not cleaned，老板在 Pending 中审批，审批记录保留。

审批按「申请划班」「工时变化」「Bathroom」分类，旧换班记录单独保留。操作说明保留三条编号，已移除排班页 OWNER 卡片及悬挂蜘蛛特效。排班表行高、列宽和原有高度计算保持不变。

验证：
- 本地 PostgreSQL 环境运行原有发布锁、工时调整和新增审批更新及回滚测试，全部通过；验证更新可重复执行。
- 两版页面完整初始化、草稿申请、分类审批、批准后横线、模式保留、重复 Staff Mode、重复管理员指令、退出登录及 Bathroom 提交通过。
- 两版页面所有脚本语法检查通过。
- 测试使用本地测试表和模拟 Supabase 客户端，尚未在生产数据库或真实手机上验证。

运行自动检查：安装 Node.js 24 后，在项目目录执行 pnpm install，再执行 pnpm test。

GitHub 推送与线上数据库更新是两个步骤。推送 HTML 前建议先安装数据库更新。本次线上数据库更新尚未执行。
