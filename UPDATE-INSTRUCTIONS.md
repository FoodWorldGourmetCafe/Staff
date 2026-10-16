# 请假功能移除更新

员工 Request Leave 和老板请假审批分类已移除。历史记录保留，移除功能不会修改任何排班。Supabase 拒绝旧网页提交或处理请假。

现有生产数据库只需执行 roster-disable-leave.sql，再发布 index.html。该脚本可重复执行。它依赖已经安装的 roster-leave-requests.sql 及 roster-unavailable-swap.sql；重建数据库时，应按原迁移顺序安装，并最后执行 roster-disable-leave.sql。若重新安装旧请假迁移，必须再次执行禁用脚本。

Not Available 换班保留：员工将已发布班次拖给同日同餐段的 Not Available 员工，先点 Confirm Transfer，再确认已经与对方沟通且对方同意。取消第二次确认不会改变排班；确认后对方获得班次，原员工该时段变为 Not Available。记录保留二次确认标记。这是发起人确认，并非对方账号在线批准。

数据库保存成功后才提示换班完成；保存错误时不修改本地排班。加班、迟到、提前离开及其他审批功能保留。

验证：pnpm test 全部通过，包括页面、数据库迁移、请假禁用、历史及排班不变、Not Available 换班二次确认与失败处理。2026-10-13 生产数据库已执行禁用脚本，并验证排班数据指纹未变。
