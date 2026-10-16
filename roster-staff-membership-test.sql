-- Run against the isolated test database only.
select set_config('request.jwt.claim.sub','',false);
do $$ begin
 begin perform public.staff_hub_add_staff_v3('Denied');raise exception 'Unauthorized add accepted';exception when others then if sqlerrm='Unauthorized add accepted' then raise;end if;end;
 begin perform public.staff_hub_remove_staff_v3(0);raise exception 'Unauthorized remove accepted';exception when others then if sqlerrm='Unauthorized remove accepted' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$ declare before_weeks jsonb;new_slot integer;expected date:=date_trunc('week',current_timestamp at time zone 'Australia/Sydney')::date;begin
 select coalesce(jsonb_agg(to_jsonb(w)),'[]') into before_weeks from public.staff_hub_weeks w;
 perform public.staff_hub_add_staff_v3('  New   Employee  ');
 select slot into new_slot from public.staff_hub_directory where name='New Employee';
 if new_slot is distinct from 3 or (select starts_week from public.staff_hub_directory where slot=new_slot) is distinct from expected then raise exception 'Invalid new slot or start week';end if;
 begin perform public.staff_hub_add_staff_v3('new employee');raise exception 'Duplicate accepted';exception when others then if sqlerrm='Duplicate accepted' then raise;end if;end;
 begin perform public.staff_hub_add_staff_v3(' ');raise exception 'Empty accepted';exception when others then if sqlerrm='Empty accepted' then raise;end if;end;
 perform public.staff_hub_remove_staff_v3(0);
 if (select active or ends_week is distinct from (expected+7) from public.staff_hub_directory where slot=0) then raise exception 'Removal boundary missing';end if;
 if not exists(select 1 from jsonb_array_elements(public.staff_hub_list_staff_v3()) x where (x->>'slot')::integer=0 and x->>'name'='Alice' and x->>'ends_week'=(expected+7)::text) then raise exception 'History missing from directory';end if;
 if before_weeks is distinct from (select coalesce(jsonb_agg(to_jsonb(w)),'[]') from public.staff_hub_weeks w) then raise exception 'Week data changed';end if;
 perform public.staff_hub_remove_staff_v3(new_slot);
 if (select starts_week+7<>ends_week from public.staff_hub_directory where slot=new_slot) then raise exception 'Same-week add/remove mismatch';end if;
 perform public.staff_hub_add_staff_v3('Replacement');
 if (select slot from public.staff_hub_directory where name='Replacement')<>4 then raise exception 'Historical slot reused';end if;
 -- Restore baseline fixtures for the existing regression suite.
 delete from public.staff_hub_directory where slot>=3;
 update public.staff_hub_directory set active=true,ends_week=null where slot=0;
end $$;
select set_config('request.jwt.claim.sub','',false);
