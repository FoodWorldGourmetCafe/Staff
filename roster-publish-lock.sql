-- Staff Hub published-roster protection. Review/run only after approval.
-- Requires existing staff_hub_weeks, staff_hub_is_admin and save/get RPCs.
-- Keeps the existing staff/shift/request validators and revision checks.
begin;
do $$ begin
 if to_regclass('public.staff_hub_weeks') is null or
    to_regprocedure('public.staff_hub_save_week(date,bigint,jsonb)') is null or
    to_regprocedure('public.staff_hub_is_admin()') is null then
  raise exception 'Existing Staff Hub schema required; no changes applied';
 end if;
end $$;

alter table public.staff_hub_weeks add column if not exists roster_edit_owner uuid;
alter table public.staff_hub_weeks add column if not exists roster_edit_until timestamptz;
alter table public.staff_hub_weeks enable row level security;
revoke all on public.staff_hub_weeks from public,anon,authenticated;

-- Trigger applies to writes through both legacy and v2 save RPCs.
create or replace function public.staff_hub_guard_published_roster()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 admin boolean:=coalesce(public.staff_hub_is_admin(),false);
 expected_cells jsonb;expected_pub jsonb;q jsonb;prior jsonb;
 r integer;c integer;a integer;b integer;i integer;n integer;
 source text;target text;planned text;actual text;starts text;
 empty_row jsonb:=to_jsonb(array_fill(''::text,array[14]));
begin
 if tg_op='INSERT' then
  -- Existing saves use INSERT ... ON CONFLICT DO UPDATE. Validate those
  -- in the UPDATE trigger, against the stored state and editing lease.
  if exists(select 1 from public.staff_hub_weeks where week_start=new.week_start) then return new;end if;
  if new.state->'published' is not null and new.state->'published'<>'null'::jsonb then
   if not admin or new.state#>'{published,cells}' is distinct from new.state->'cells' then
    raise exception 'Only an administrator may publish the current roster';
   end if;
   new.roster_edit_owner:=null;new.roster_edit_until:=null;
  end if;
  return new;
 end if;
 if tg_op='DELETE' then
  if old.state->'published' is not null and old.state->'published'<>'null'::jsonb then
   raise exception 'Published roster cannot be deleted';
  end if;
  return old;
 end if;
 if old.state->'published' is null or old.state->'published'='null'::jsonb then
  if new.state->'published' is not null and new.state->'published'<>'null'::jsonb then
   if not admin or new.state#>'{published,cells}' is distinct from new.state->'cells' then
    raise exception 'Only an administrator may publish the current roster';
   end if;
   new.roster_edit_owner:=null;new.roster_edit_until:=null;
  end if;
  return new;
 end if;
 if new.state->'published' is null or new.state->'published'='null'::jsonb then
  raise exception 'Publication cannot be removed to reopen availability';
 end if;
 -- No staff availability edits after publication, including old browser tabs.
 if not admin then
  for r in 0..jsonb_array_length(old.state->'cells')-1 loop
   for c in 2..13 loop
    source:=old.state->'cells'->r->>c;target:=new.state->'cells'->r->>c;
    if source in ('','unavailable') and target in ('','unavailable') and source is distinct from target then
     raise exception 'Roster locked after publication';
    end if;
   end loop;
  end loop;
  -- The existing save validator checks all remaining staff changes/swaps.
  return new;
 end if;
 if old.roster_edit_owner=auth.uid() and old.roster_edit_until>clock_timestamp() then return new;end if;
 -- A locked owner can review requests and swaps, but cannot edit arbitrary shifts.
 expected_cells:=old.state->'cells';expected_pub:=old.state#>'{published,cells}';
 -- Employee-directory additions may append empty rows, without changing shifts.
 while jsonb_array_length(expected_cells)<jsonb_array_length(new.state->'cells') loop
  expected_cells:=expected_cells||jsonb_build_array(empty_row);
  expected_pub:=expected_pub||jsonb_build_array(empty_row);
 end loop;
 for q in select value from jsonb_array_elements(new.state->'requests') loop
  select value into prior from jsonb_array_elements(old.state->'requests')
   where value->'row'=q->'row' and value->'col'=q->'col';
  if q->>'status'='approved' and q is distinct from prior then
   if prior is null or prior->>'status'<>'pending' or q->'planned' is distinct from prior->'planned' then
    raise exception 'Approval must match an existing pending request';
   end if;
   r:=(q->>'row')::integer;c:=(q->>'col')::integer;planned:=q->>'planned';actual:=q->>'actual';
   if planned is distinct from expected_cells->r->>c or planned is distinct from expected_pub->r->>c then
    raise exception 'Request shift changed; reject and resubmit';
   end if;
   starts:=case planned when '103' then '10:00' when '113' then '11:00'
    when '1033' then '10:30' when '1133' then '11:30' when '58' then '17:00'
    when '59' then '17:00' else substring(planned,8,5) end;
   if actual is null or actual not like ('custom:'||starts||'-%') or public.staff_hub_shift_minutes(actual)<=0 then
    raise exception 'Approval must preserve the start time';
   end if;
   if public.staff_hub_shift_minutes(prior->>'actual')<public.staff_hub_shift_minutes(planned) then
    if public.staff_hub_shift_minutes(actual)>=public.staff_hub_shift_minutes(planned) then
     raise exception 'Early leave must finish earlier';
    end if;
   elsif public.staff_hub_shift_minutes(actual)<public.staff_hub_shift_minutes(planned) then
    raise exception 'Extra hours cannot finish earlier';
   end if;
   expected_cells:=jsonb_set(expected_cells,array[r::text,c::text],q->'actual');
   expected_pub:=jsonb_set(expected_pub,array[r::text,c::text],q->'actual');
  end if;
 end loop;
 n:=jsonb_array_length(old.state->'transfers');
 for i in 0..jsonb_array_length(new.state->'transfers')-1 loop
  q:=new.state->'transfers'->i;prior:=old.state->'transfers'->i;
  if q->>'status'='approved' and (i>=n or prior->>'status'='pending') then
   if i<n and (q-'status') is distinct from (prior-'status') then raise exception 'Transfer details changed';end if;
   a:=(q->>'from')::integer;b:=(q->>'to')::integer;c:=(q->>'col')::integer;
   if a is null or b is null or c is null or a=b or a<0 or b<0 or
      a>=jsonb_array_length(expected_cells) or b>=jsonb_array_length(expected_cells) or c not between 2 and 13 then
    raise exception 'Invalid transfer';
   end if;
   source:=q->>'source';target:=q->>'target';
   if source is distinct from expected_cells->a->>c or source is distinct from expected_pub->a->>c or
      target is distinct from expected_cells->b->>c or target is distinct from expected_pub->b->>c or
      public.staff_hub_shift_minutes(source)<=0 or target='unavailable' then
    raise exception 'Transfer shifts changed';
   end if;
   expected_cells:=jsonb_set(jsonb_set(expected_cells,array[a::text,c::text],q->'target'),array[b::text,c::text],q->'source');
   expected_pub:=jsonb_set(jsonb_set(expected_pub,array[a::text,c::text],q->'target'),array[b::text,c::text],q->'source');
  end if;
 end loop;
 if new.state->'cells' is distinct from expected_cells or new.state#>'{published,cells}' is distinct from expected_pub or
    new.state->'cleaning' is distinct from old.state->'cleaning' then
  raise exception 'Roster locked. Unlock Editing first';
 end if;
 return new;
end $$;
revoke all on function public.staff_hub_guard_published_roster() from public,anon,authenticated;
drop trigger if exists staff_hub_published_roster_guard on public.staff_hub_weeks;
create trigger staff_hub_published_roster_guard before insert or update or delete on public.staff_hub_weeks
for each row execute function public.staff_hub_guard_published_roster();

create or replace function public.staff_hub_roster_lock_status(p_week date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare w public.staff_hub_weeks;
begin
 if p_week is null or extract(isodow from p_week)<>1 then raise exception 'Invalid week';end if;
 select * into w from public.staff_hub_weeks where week_start=p_week;
 return jsonb_build_object('version',1,'can_edit',coalesce(public.staff_hub_is_admin() and
  w.roster_edit_owner=auth.uid() and w.roster_edit_until>clock_timestamp(),false),'until',w.roster_edit_until);
end $$;
create or replace function public.staff_hub_unlock_roster(p_week date,p_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare w public.staff_hub_weeks;until_time timestamptz:=clock_timestamp()+interval '30 minutes';
begin
 if not coalesce(public.staff_hub_is_admin(),false) then raise exception 'Administrator access required';end if;
 perform pg_advisory_xact_lock(782431,1);
 perform pg_advisory_xact_lock(hashtext('staff-hub'),(p_week-date '2000-01-01'));
 select * into w from public.staff_hub_weeks where week_start=p_week for update;
 if not found or w.state->'published' is null or w.state->'published'='null'::jsonb then raise exception 'Publish first';end if;
 if p_revision is null or w.revision<>p_revision then raise exception 'Conflict: refresh the roster before unlocking';end if;
 if w.roster_edit_owner is not null and w.roster_edit_owner<>auth.uid() and w.roster_edit_until>clock_timestamp() then
  raise exception 'Another administrator is editing this roster';
 end if;
 update public.staff_hub_weeks set roster_edit_owner=auth.uid(),roster_edit_until=until_time where week_start=p_week;
 return jsonb_build_object('until',until_time);
end $$;
create or replace function public.staff_hub_save_and_lock_roster(p_week date,p_revision bigint,p_state jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare w public.staff_hub_weeks;result jsonb;
begin
 if not coalesce(public.staff_hub_is_admin(),false) then raise exception 'Administrator access required';end if;
 -- Same lock order as the existing v2 save/directory RPCs.
 perform pg_advisory_xact_lock(782431,1);
 perform pg_advisory_xact_lock(hashtext('staff-hub'),(p_week-date '2000-01-01'));
 select * into w from public.staff_hub_weeks where week_start=p_week for update;
 if not found or w.roster_edit_owner is distinct from auth.uid() or w.roster_edit_until is null or
    w.roster_edit_until<=clock_timestamp() then raise exception 'Unlock Editing first';end if;
 if p_state#>'{published,cells}' is null or p_state#>'{published,cells}' is distinct from p_state->'cells' then
  raise exception 'Save & Lock must publish the current shifts';
 end if;
 result:=public.staff_hub_save_week(p_week,p_revision,p_state);
 update public.staff_hub_weeks set roster_edit_owner=null,roster_edit_until=null where week_start=p_week;
 return result||jsonb_build_object('state',p_state);
end $$;
revoke all on function public.staff_hub_roster_lock_status(date),public.staff_hub_unlock_roster(date,bigint),
 public.staff_hub_save_and_lock_roster(date,bigint,jsonb) from public,anon,authenticated;
grant execute on function public.staff_hub_roster_lock_status(date) to anon,authenticated;
grant execute on function public.staff_hub_unlock_roster(date,bigint),public.staff_hub_save_and_lock_roster(date,bigint,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
select 'Roster locking installed' as result;
