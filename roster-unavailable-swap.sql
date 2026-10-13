-- Run after roster-leave-requests.sql. Preserve installed functions and locks.
begin;
do $$
declare name text;definition text;
begin
 foreach name in array array['public.staff_hub_save_week_v2(date,bigint,jsonb)','public.staff_hub_guard_published_roster()'] loop
  select pg_get_functiondef(name::regprocedure) into definition;
  if position('availabilityConfirmed' in definition)>0 then continue;end if;
  if name like '%save_week_v2%' then
   if position('or q->>''target''=''unavailable''' in definition)=0 then raise exception 'Unexpected save function; install roster-actual-adjustments.sql first';end if;
   definition:=replace(definition,'or q->>''target''=''unavailable''','or (q->>''target''=''unavailable'' and q->''availabilityConfirmed'' is distinct from ''true''::jsonb)');
  else
   if position('or target=''unavailable''' in definition)=0 then raise exception 'Unexpected publish guard';end if;
   definition:=replace(definition,'or target=''unavailable''','or (target=''unavailable'' and q->''availabilityConfirmed'' is distinct from ''true''::jsonb)');
  end if;
  execute definition;
 end loop;
end $$;
commit;
