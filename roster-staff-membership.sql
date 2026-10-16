-- Weekly employee membership. Existing rows keep their legacy visibility until
-- a dated change is made; unknown historical join/leave dates are not invented.
begin;
alter table public.staff_hub_directory add column if not exists starts_week date;
alter table public.staff_hub_directory add column if not exists ends_week date;

create or replace function public.staff_hub_membership_week()
returns date language sql stable set search_path='' as $$
 select date_trunc('week',current_timestamp at time zone 'Australia/Sydney')::date
$$;

create or replace function public.staff_hub_list_staff_v3()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('slot',slot,'name',name,'active',active,'starts_week',starts_week,'ends_week',ends_week) order by slot),'[]'::jsonb) from public.staff_hub_directory
$$;

create or replace function public.staff_hub_staff_active_in_week(p_slot integer,p_week date)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select case when starts_week is null and ends_week is null then active
 else (starts_week is null or p_week>=starts_week) and (ends_week is null or p_week<ends_week) end
 from public.staff_hub_directory where slot=p_slot),false) and p_week is not null
$$;
CREATE OR REPLACE FUNCTION public.staff_hub_pad_staff_rows(p_state jsonb, p_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$ declare result jsonb:=p_state;cells jsonb;pub jsonb;empty_row jsonb:=to_jsonb(array_fill(''::text,array[14])); begin if p_state is null or p_state='null'::jsonb then return p_state;end if;cells:=p_state->'cells';pub:=p_state#>'{published,cells}';while jsonb_array_length(cells)<p_count loop cells:=cells||jsonb_build_array(empty_row);end loop;result:=jsonb_set(result,'{cells}',cells);if jsonb_typeof(pub)='array' then while jsonb_array_length(pub)<p_count loop pub:=pub||jsonb_build_array(empty_row);end loop;result:=jsonb_set(result,'{published,cells}',pub);end if;return result;end;$function$
;
CREATE OR REPLACE FUNCTION public.staff_hub_add_staff(p_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ declare normalized text;new_slot integer;begin if not public.staff_hub_is_admin() then raise exception 'Administrator access required';end if;normalized:=regexp_replace(btrim(p_name),'[[:space:]]+',' ','g');if normalized is null or char_length(normalized) not between 1 and 40 then raise exception 'Name must contain 1–40 characters';end if;perform pg_advisory_xact_lock(782431,1);if exists(select 1 from public.staff_hub_directory where active and lower(name)=lower(normalized)) then raise exception 'An active employee already has this name';end if;select coalesce(max(slot),-1)+1 into new_slot from public.staff_hub_directory;insert into public.staff_hub_directory(slot,name,starts_week) values(new_slot,normalized,public.staff_hub_membership_week());update public.staff_hub_weeks set state=public.staff_hub_pad_staff_rows(state,new_slot+1),revision=revision+1,updated_at=now() where state is not null and jsonb_array_length(state->'cells')<new_slot+1;return jsonb_build_object('slot',new_slot,'name',normalized,'active',true);end;$function$
;
CREATE OR REPLACE FUNCTION public.staff_hub_remove_staff(p_slot integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ begin if not public.staff_hub_is_admin() then raise exception 'Administrator access required';end if;perform pg_advisory_xact_lock(782431,1);update public.staff_hub_directory set active=false,retired_at=now(),ends_week=public.staff_hub_membership_week()+7 where slot=p_slot and active;if not found then raise exception 'Employee is already removed or does not exist';end if;return jsonb_build_object('slot',p_slot,'active',false);end;$function$
;

create or replace function public.staff_hub_add_staff_v3(p_name text)
returns void language plpgsql security definer set search_path='' as $$
begin perform public.staff_hub_add_staff(p_name);end $$;
create or replace function public.staff_hub_remove_staff_v3(p_slot integer)
returns void language plpgsql security definer set search_path='' as $$
begin perform public.staff_hub_remove_staff(p_slot);end $$;

-- Preserve the installed validators, revision checks and publication locks.
-- Change membership predicates only; rerunning the migration is safe.
do $migration$
declare signature text;definition text;prior text;
begin
 foreach signature in array array['public.staff_hub_save_week_v2(date,bigint,jsonb)','public.staff_hub_submit_service_request(date,bigint,jsonb)','public.staff_hub_decide_service_request(date,bigint,text,text)'] loop
  if to_regprocedure(signature) is null then raise exception 'Existing roster migrations required: %',signature;end if;
  select pg_get_functiondef(signature::regprocedure) into definition;prior:=definition;
  definition:=replace(definition,'exists(select 1 from public.staff_hub_directory where slot=r and active)','public.staff_hub_staff_active_in_week(r,p_week)');
  definition:=replace(definition,'exists(select 1 from public.staff_hub_directory where slot=a and active)','public.staff_hub_staff_active_in_week(a,p_week)');
  definition:=replace(definition,'exists(select 1 from public.staff_hub_directory where slot=b and active)','public.staff_hub_staff_active_in_week(b,p_week)');
  definition:=replace(definition,'exists(select 1 from public.staff_hub_directory d where d.slot=r and d.active)','public.staff_hub_staff_active_in_week(r,p_week)');
  definition:=replace(definition,'exists(select 1 from public.staff_hub_directory d where d.slot=(p_request->''actual''->>0)::integer and active)','public.staff_hub_staff_active_in_week((p_request->''actual''->>0)::integer,p_week)');
  definition:=replace(definition,'exists(select 1 from public.staff_hub_directory where slot=a::integer and active)','public.staff_hub_staff_active_in_week(a::integer,p_week)');
  if signature like '%save_week_v2%' and position('if not public.staff_hub_staff_active_in_week(r,p_week) or q->>''status''' in definition)=0 then
   definition:=replace(definition,'if q->>''status''<>''pending'' or','if not public.staff_hub_staff_active_in_week(r,p_week) or q->>''status''<>''pending'' or');
  end if;
  if position('staff_hub_staff_active_in_week' in definition)=0 then raise exception 'Unexpected validator definition: %',signature;end if;
  if definition<>prior then execute definition;end if;
 end loop;
end $migration$;
revoke all on function public.staff_hub_staff_active_in_week(integer,date),public.staff_hub_pad_staff_rows(jsonb,integer) from public,anon,authenticated;
revoke all on function public.staff_hub_add_staff_v3(text),public.staff_hub_remove_staff_v3(integer) from public,anon;
grant execute on function public.staff_hub_add_staff_v3(text),public.staff_hub_remove_staff_v3(integer) to authenticated;
revoke all on function public.staff_hub_list_staff_v3() from public;
grant execute on function public.staff_hub_list_staff_v3() to anon,authenticated;
commit;
