# 已发布班次请假更新

新增功能：员工点击已发布班次，在 Shift Request 中选择 Request Leave，再提交申请。老板在 Pending → 请假 中 Approve 或 Reject，也可 Approve All。

例如 Ron 本周周六 5–9：点击 Ron 周六 Dinner 的 5–9 班次，提交请假。批准前班次不变；批准后该班次留空白，排班总工时减去该班次，保留原时间及审批记录。拒绝保留原班次。这是功能示例，本更新没有替 Ron 提交真实申请。

上线顺序：
1. 在现有 Supabase 项目 SQL Editor 执行 roster-leave-requests.sql。前提是已安装 roster-publish-lock.sql、roster-actual-adjustments.sql、roster-draft-request-lock.sql、roster-service-requests.sql。新增脚本可重复执行。
2. 在 SQL Editor 执行 roster-unavailable-swap.sql，允许与 Not Available 员工换班；此脚本也可重复执行。
3. 替换仓库 index.html 和 christmas.html，再发布网站。
4. 在测试周提交请假，并以老板账号验证 Approve / Reject。

已有工时变化或换班待审批时，须先处理这些申请再批准该班次请假。如果班次已经被老板修改，旧申请不能批准，应拒绝后重新提交。

本地验证：两版页面脚本语法、完整页面交互、请假提交、分类审批、批准后空白及工时扣除通过；数据库测试覆盖重复申请、权限、拒绝、已发布排班锁、班次变化、批准及重复批准、重复安装。

测试运行：pnpm install，然后 pnpm test。

2026-10-13：Supabase 生产数据库已安装请假及 Not Available 换班更新。线上回滚验证通过：请假提交、重复阻止、审批权限、拒绝、批准留空白、二次确认限制及换班。所有测试数据已回滚。两版页面将在本次提交后由 GitHub Pages 发布。未在真实手机验证。

Not Available 换班：员工将已发布班次拖给同日同餐段的 Not Available 员工，先点 Confirm Transfer，再确认已经与对方沟通且对方同意。取消第二次确认不会改变排班；确认后对方获得班次，原员工该时段变为 Not Available。审批记录保留二次确认标记。这是发起人确认，并非对方账号在线批准。

新增验证：两版页面二次确认、取消不变、确认换班及确认记录保留通过；数据库拒绝缺少二次确认标记的换班，允许确认后的换班，重复安装通过。

换班保存：数据库保存成功后才提示完成；数据库返回错误时不修改本地排班。
