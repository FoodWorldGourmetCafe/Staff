-- Least-privilege grants; existing RLS policies remain in force.
begin;
revoke all on public.admin_users from anon;
revoke insert,update,delete,truncate,references,trigger on public.admin_users from authenticated;
grant select on public.admin_users to authenticated;
do $$ begin
 if to_regclass('public.menu') is not null then
  execute 'revoke all on public.menu from anon';
  execute 'grant select on public.menu to anon';
  execute 'revoke truncate,references,trigger on public.menu from authenticated';
 end if;
end $$;
revoke all on function public.staff_hub_add_staff(text),public.staff_hub_remove_staff(integer) from public,anon;
grant execute on function public.staff_hub_add_staff(text),public.staff_hub_remove_staff(integer) to authenticated;
commit;
