-- Late Start and independent actual-time adjustments. Existing state is preserved.
begin;
create or replace function public.staff_hub_shift_bounds(code text)
returns text[] language sql immutable set search_path='' as $$
 select case code when '103' then array['10:00','15:00'] when '113' then array['11:00','15:00']
 when '1033' then array['10:30','15:00'] when '1133' then array['11:30','15:00']
 when '58' then array['17:00','20:00'] when '59' then array['17:00','21:00']
 else array[substring(code,8,5),substring(code,14,5)] end;
$$;
create or replace function public.staff_hub_request_kind(q jsonb)
returns text language sql immutable set search_path='' as $$
 select coalesce(q->>'kind',case
 when (public.staff_hub_shift_bounds(q->>'actual'))[1] is distinct from (public.staff_hub_shift_bounds(q->>'planned'))[1] then 'late_start'
 when public.staff_hub_shift_minutes(q->>'actual')<public.staff_hub_shift_minutes(q->>'planned') then 'early_leave' else 'overtime' end);
$$;
create or replace function public.staff_hub_request_key(q jsonb)
returns text language sql immutable set search_path='' as $$
 select concat(q->>'row',':',q->>'col',':',q->>'planned',':',public.staff_hub_request_kind(q));
$$;
create or replace function public.staff_hub_original_shift(state jsonb,r integer,c integer,code text)
returns text language sql immutable set search_path='' as $$
 select coalesce((select q->>'planned' from jsonb_array_elements(state->'requests') q
 where (q->>'row')::integer=r and (q->>'col')::integer=c and not(q?'kind')
 and q->>'status'='approved' and q->>'actual'=code limit 1),code);
$$;
create or replace function public.staff_hub_validate_adjustments(state jsonb,staff_total integer,include_pending boolean)
returns void language plpgsql set search_path='' as $$
declare q jsonb;x jsonb;r integer;c integer;p text[];a text[];kind text;start_at text;end_at text;code text;
begin
 if (select count(*) from jsonb_array_elements(state->'requests')) is distinct from
 (select count(distinct public.staff_hub_request_key(value)) from jsonb_array_elements(state->'requests')) then
  raise exception 'Duplicate shift adjustment request';
 end if;
 for q in select value from jsonb_array_elements(state->'requests') loop
  if jsonb_typeof(q) is distinct from 'object' then raise exception 'Invalid shift adjustment';end if;
  r:=(q->>'row')::integer;c:=(q->>'col')::integer;kind:=public.staff_hub_request_kind(q);
  if r is null or c is null or r not between 0 and staff_total-1 or c not between 2 and 13 or
  q->>'status' is null or q->>'status' not in ('pending','approved','rejected') or
  kind is null or kind not in ('late_start','early_leave','overtime') or
  public.staff_hub_shift_minutes(q->>'planned')<=0 or public.staff_hub_shift_minutes(q->>'actual')<=0 then
   raise exception 'Invalid shift adjustment request';
  end if;
  p:=public.staff_hub_shift_bounds(q->>'planned');a:=public.staff_hub_shift_bounds(q->>'actual');
  if kind='late_start' then
   if a[1]<=p[1] or a[2]<>p[2] then raise exception 'Late start must preserve finish and start later';end if;
  else
   if a[1]<>p[1] then raise exception 'Finish adjustment must preserve planned start';end if;
   if kind='early_leave' and a[2]>=p[2] then raise exception 'Early leave must finish earlier';end if;
   if kind='overtime' and (a[2]<p[2] or (q?'kind' and a[2]=p[2])) then raise exception 'Overtime must finish later';end if;
  end if;
  if q->>'status'='rejected' then continue;end if;
  if kind<>'late_start' and exists(select 1 from jsonb_array_elements(state->'requests') z
   where z->'row'=q->'row' and z->'col'=q->'col' and z->'planned'=q->'planned'
   and z->>'status'<>'rejected' and public.staff_hub_request_kind(z)<>'late_start'
   and public.staff_hub_request_kind(z)<>kind) then raise exception 'Conflicting finish adjustments';end if;
  code:=coalesce(state#>>array['published','cells',r::text,c::text],state#>>array['cells',r::text,c::text]);
  if public.staff_hub_original_shift(state,r,c,code) is distinct from q->>'planned' then continue;end if;
  start_at:=p[1];end_at:=p[2];
  for x in select value from jsonb_array_elements(state->'requests') where value->'row'=q->'row'
   and value->'col'=q->'col' and value->'planned'=q->'planned'
   and (value->>'status'='approved' or include_pending and value->>'status'='pending') loop
   a:=public.staff_hub_shift_bounds(x->>'actual');
   if public.staff_hub_request_kind(x)='late_start' then start_at:=a[1];else end_at:=a[2];end if;
  end loop;
  if start_at>=end_at then raise exception 'Actual finish must be after actual start';end if;
 end loop;
end $$;
revoke all on function public.staff_hub_shift_bounds(text),public.staff_hub_request_kind(jsonb),
 public.staff_hub_request_key(jsonb),public.staff_hub_original_shift(jsonb,integer,integer,text),
 public.staff_hub_validate_adjustments(jsonb,integer,boolean) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.staff_hub_save_week_v2(p_week date, p_revision bigint, p_state jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare staff_total int;w public.staff_hub_weeks;old jsonb;expected jsonb;cells jsonb;pub jsonb;q jsonb;prior jsonb;v text;before text;r int;c int;i int;n int;a int;b int;admin boolean;clean jsonb;
begin perform pg_advisory_xact_lock(782431,1);select count(*) into staff_total from public.staff_hub_directory;
 if p_week is null or p_revision is null or p_revision<0 or extract(isodow from p_week)<>1 or p_state is null or octet_length(p_state::text)>100000 then raise exception 'Invalid week';end if;
 perform pg_advisory_xact_lock(hashtext('staff-hub'),(p_week-date '2000-01-01'));
 select * into w from public.staff_hub_weeks where week_start=p_week for update;
 if coalesce(w.revision,0)<>p_revision then raise exception 'Conflict: another device changed this week. Local changes are retained.';end if;
 admin:=public.staff_hub_is_admin();cells:=p_state->'cells';
 if jsonb_typeof(cells) is distinct from 'array' or jsonb_array_length(cells)<>staff_total then raise exception 'Invalid staff rows';end if;
 for r in 0..staff_total-1 loop
  if jsonb_typeof(cells->r) is distinct from 'array' or jsonb_array_length(cells->r)<>14 then raise exception 'Invalid shift columns';end if;
  for c in 0..13 loop
   if jsonb_typeof(cells->r->c) is distinct from 'string' then raise exception 'Invalid cell';end if;
   v:=cells->r->>c;perform public.staff_hub_shift_minutes(v);
   if c<2 and v<>'' then raise exception 'Monday is closed';end if;
  end loop;
 end loop;
 if p_state->'published' is not null and p_state->'published'<>'null'::jsonb then
  pub:=p_state->'published'->'cells';
  if jsonb_typeof(pub) is distinct from 'array' or jsonb_array_length(pub)<>staff_total then raise exception 'Invalid published roster';end if;
  for r in 0..staff_total-1 loop
   if jsonb_typeof(pub->r) is distinct from 'array' or jsonb_array_length(pub->r)<>14 then raise exception 'Invalid published row';end if;
   for c in 0..13 loop
    if jsonb_typeof(pub->r->c) is distinct from 'string' then raise exception 'Invalid published cell';end if;
    perform public.staff_hub_shift_minutes(pub->r->>c);
    if c<2 and pub->r->>c<>'' then raise exception 'Monday is closed';end if;
   end loop;
  end loop;
 end if;
 if jsonb_typeof(p_state->'requests') is distinct from 'array' or jsonb_typeof(p_state->'transfers') is distinct from 'array' or jsonb_typeof(p_state->'cleaning') is distinct from 'object' then raise exception 'Invalid week metadata';end if;
 if jsonb_array_length(p_state->'requests')>staff_total*36 or jsonb_array_length(p_state->'transfers')>1000 then raise exception 'Too many records';end if;
 perform public.staff_hub_validate_adjustments(p_state,staff_total,not admin);
 for v,q in select key,value from jsonb_each(p_state->'cleaning') loop
  if v::date<=p_week or v::date>p_week+6 or jsonb_typeof(q)<>'array' or jsonb_array_length(q)>1 then raise exception 'Invalid cleaning assignment';end if;
  if jsonb_array_length(q)=1 and ((q->>0)::int is null or (q->>0)::int not between 0 and staff_total-1) then raise exception 'Invalid cleaner';end if;
 end loop;
 if not admin then
  old:=coalesce(w.state,jsonb_build_object('cells',(select jsonb_agg(row) from (select to_jsonb(array_fill(''::text,array[14])) row from generate_series(1,staff_total)) x),'published',null,'requests','[]'::jsonb,'transfers','[]'::jsonb,'cleaning','{}'::jsonb));expected:=old;
  for r in 0..staff_total-1 loop for c in 2..13 loop
   v:=cells->r->>c;before:=old->'cells'->r->>c;
   if v is distinct from before and before in ('','unavailable') and v in ('','unavailable') and exists(select 1 from public.staff_hub_directory where slot=r and active) then expected:=jsonb_set(expected,array['cells',r::text,c::text],to_jsonb(v));end if;
  end loop;end loop;
  for q in select value from jsonb_array_elements(old->'requests') loop
   select value into prior from jsonb_array_elements(p_state->'requests') where public.staff_hub_request_key(value)=public.staff_hub_request_key(q);
   if prior is null or (q->>'status'='approved' and prior<>q) then raise exception 'Cannot remove or change approved overtime';end if;
  end loop;
  for q in select value from jsonb_array_elements(p_state->'requests') loop
   select value into prior from jsonb_array_elements(old->'requests') where public.staff_hub_request_key(value)=public.staff_hub_request_key(q);
   if q is distinct from prior then
    r:=(q->>'row')::int;c:=(q->>'col')::int;
    if q->>'status'<>'pending' or q->>'planned' is distinct from public.staff_hub_original_shift(old,r,c,old->'cells'->r->>c) or (coalesce(public.staff_hub_shift_minutes(q->>'actual'),0)<=0 or public.staff_hub_shift_minutes(q->>'actual')=public.staff_hub_shift_minutes(q->>'planned')) then raise exception 'Invalid staff shift adjustment';end if;
   end if;
  end loop;
  if (select count(*) from jsonb_array_elements(p_state->'requests'))<>(select count(distinct public.staff_hub_request_key(value)) from jsonb_array_elements(p_state->'requests')) then raise exception 'Duplicate overtime request';end if;
  expected:=jsonb_set(expected,'{requests}',p_state->'requests');n:=jsonb_array_length(old->'transfers');
  if jsonb_array_length(p_state->'transfers')<n then raise exception 'Cannot remove transfer history';end if;
  for i in 0..n-1 loop if p_state->'transfers'->i<>old->'transfers'->i then raise exception 'Cannot change transfer history';end if;end loop;
  for i in n..jsonb_array_length(p_state->'transfers')-1 loop
   q:=p_state->'transfers'->i;a:=(q->>'from')::int;b:=(q->>'to')::int;c:=(q->>'col')::int;
   if a is null or b is null or c is null or a not between 0 and staff_total-1 or b not between 0 and staff_total-1 or a=b or c not between 2 and 13 or q->>'status' is null or q->>'status'<>'approved' or not exists(select 1 from public.staff_hub_directory where slot=a and active) or not exists(select 1 from public.staff_hub_directory where slot=b and active) then raise exception 'Invalid transfer';end if;
   if q->>'source' is null or q->>'target' is null or expected->'published' is null or expected->'published'='null'::jsonb or q->>'source'<>expected->'published'->'cells'->a->>c or q->>'target'<>expected->'published'->'cells'->b->>c or public.staff_hub_shift_minutes(q->>'source')<=0 or q->>'target'='unavailable' then raise exception 'Published shift changed';end if;
   if q->>'source'<>expected->'cells'->a->>c or q->>'target'<>expected->'cells'->b->>c then raise exception 'Unpublished shift changes';end if;
   if exists(select 1 from jsonb_array_elements(expected->'requests') z where (z->>'col')::int=c and (z->>'row')::int in(a,b) and z->>'status'<>'rejected') then raise exception 'Overtime exists for this shift';end if;
   expected:=jsonb_set(expected,array['cells',a::text,c::text],q->'target');expected:=jsonb_set(expected,array['cells',b::text,c::text],q->'source');
   expected:=jsonb_set(expected,array['published','cells',a::text,c::text],q->'target');expected:=jsonb_set(expected,array['published','cells',b::text,c::text],q->'source');
   expected:=jsonb_set(expected,'{published,at}',p_state->'published'->'at');
  end loop;
  expected:=jsonb_set(expected,'{transfers}',p_state->'transfers');
  if expected is distinct from p_state then raise exception 'This action requires an administrator';end if;
 end if;
 insert into public.staff_hub_weeks(week_start,state,revision) values(p_week,p_state,p_revision+1) on conflict(week_start) do update set state=excluded.state,revision=excluded.revision,updated_at=now();
 return jsonb_build_object('revision',p_revision+1);
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_hub_guard_published_roster()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
   where public.staff_hub_request_key(value)=public.staff_hub_request_key(q);
  if q->>'status'='approved' and q is distinct from prior then
   if prior is null or prior->>'status'<>'pending' or q->'planned' is distinct from prior->'planned' then
    raise exception 'Approval must match an existing pending request';
   end if;
   r:=(q->>'row')::integer;c:=(q->>'col')::integer;planned:=q->>'planned';actual:=q->>'actual';
   if planned is distinct from public.staff_hub_original_shift(old.state,r,c,expected_cells->r->>c)
      or planned is distinct from public.staff_hub_original_shift(old.state,r,c,expected_pub->r->>c) then
    raise exception 'Request shift changed; reject and resubmit';
   end if;
   -- Approvals live in requests. Published and draft cells remain the planned roster.

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
end $function$
;
-- Sample week and all its writes roll back inside this block, including failed attempts.
do $$
declare test_week date;staff_total integer;r integer;admin_id uuid;cells jsonb;s jsonb;before_cells jsonb;
 rev bigint:=0;q jsonb;bad jsonb;rejected boolean;loaded jsonb;
begin
 begin
  select user_id into admin_id from public.admin_users limit 1;
  if admin_id is null then raise exception 'Test requires an existing administrator';end if;
  select count(*) into staff_total from public.staff_hub_directory;
  select slot into r from public.staff_hub_directory where active order by slot limit 1;
  select d::date into test_week from generate_series(date '2099-01-05',date '2099-12-28',interval '7 days') d
   where not exists(select 1 from public.staff_hub_weeks where week_start=d::date) limit 1;
  if test_week is null or r is null then raise exception 'No isolated test week or active employee';end if;
  select jsonb_agg(to_jsonb(array_fill(''::text,array[14]))) into cells from generate_series(1,staff_total);
  cells:=jsonb_set(cells,array[r::text,'7'],'"59"');before_cells:=cells;
  s:=jsonb_build_object('cells',cells,'published',jsonb_build_object('cells',cells,'at','2099-01-01T00:00:00Z'),
   'requests','[]'::jsonb,'transfers','[]'::jsonb,'cleaning','{}'::jsonb);
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.staff_hub_save_week_v2(test_week,rev,s);rev:=rev+1;
  perform set_config('request.jwt.claim.sub','',true);
  q:=jsonb_build_object('row',r,'col',7,'planned','59','actual','custom:17:25-21:00','kind','late_start','status','pending');
  s:=jsonb_set(s,'{requests}',jsonb_build_array(q));
  perform public.staff_hub_save_week_v2(test_week,rev,s);rev:=rev+1;
  q:=jsonb_build_object('row',r,'col',7,'planned','59','actual','custom:17:00-20:30','kind','early_leave','status','pending');
  s:=jsonb_set(s,'{requests}',(s->'requests')||jsonb_build_array(q));
  perform public.staff_hub_save_week_v2(test_week,rev,s);rev:=rev+1;
  loaded:=public.staff_hub_get_week_v2(test_week);
  if jsonb_array_length(loaded#>'{state,requests}')<>2 or loaded#>'{state,cells}'<>before_cells then raise exception 'Pending save/reload failed';end if;
  bad:=jsonb_set(s,'{requests,0,status}','"approved"');rejected:=false;
  begin perform public.staff_hub_save_week_v2(test_week,rev,bad);exception when others then rejected:=true;end;
  if not rejected then raise exception 'Staff approval was not blocked';end if;
  bad:=jsonb_set(s,array['cells',r::text,'6'],'"unavailable"');rejected:=false;
  begin perform public.staff_hub_save_week_v2(test_week,rev,bad);exception when others then rejected:=true;end;
  if not rejected then raise exception 'Locked staff availability was not blocked';end if;
  bad:=jsonb_set(s,'{requests,0,actual}','"custom:20:45-21:00"');rejected:=false;
  begin perform public.staff_hub_save_week_v2(test_week,rev,bad);exception when others then rejected:=true;end;
  if not rejected then raise exception 'Crossed pending endpoints were not blocked';end if;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  s:=jsonb_set(s,'{requests,0,status}','"approved"');
  perform public.staff_hub_save_week_v2(test_week,rev,s);rev:=rev+1;
  bad:=jsonb_set(s,'{requests,1,actual}','"custom:17:00-17:20"');bad:=jsonb_set(bad,'{requests,1,status}','"approved"');rejected:=false;
  begin perform public.staff_hub_save_week_v2(test_week,rev,bad);exception when others then rejected:=true;end;
  if not rejected then raise exception 'Crossed approved endpoints were not blocked';end if;
  s:=jsonb_set(s,'{requests,1,status}','"approved"');
  perform public.staff_hub_save_week_v2(test_week,rev,s);rev:=rev+1;
  loaded:=public.staff_hub_get_week_v2(test_week);
  if loaded#>'{state,cells}'<>before_cells or loaded#>'{state,published,cells}'<>before_cells then raise exception 'Approval overwrote planned roster';end if;
  if loaded#>>'{state,requests,0,actual}'<>'custom:17:25-21:00' or loaded#>>'{state,requests,1,actual}'<>'custom:17:00-20:30' then raise exception 'Approved save/reload failed';end if;
  if public.staff_hub_shift_minutes('custom:17:25-20:30')<>185 then raise exception 'Combined hours failed';end if;
  perform set_config('request.jwt.claim.sub','',true);
  bad:=jsonb_set(s,'{requests,0,actual}','"custom:17:30-21:00"');rejected:=false;
  begin perform public.staff_hub_save_week_v2(test_week,rev,bad);exception when others then rejected:=true;end;
  if not rejected then raise exception 'Staff changed approved adjustment';end if;
  rejected:=false;begin perform public.staff_hub_save_week_v2(test_week,rev-1,s);exception when others then rejected:=true;end;
  if not rejected then raise exception 'Revision conflict was not blocked';end if;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  bad:=jsonb_set(s,array['cells',r::text,'7'],'"58"');bad:=jsonb_set(bad,array['published','cells',r::text,'7'],'"58"');rejected:=false;
  begin perform public.staff_hub_save_week_v2(test_week,rev,bad);exception when others then rejected:=true;end;
  if not rejected then raise exception 'Locked administrator arbitrary edit was not blocked';end if;
  perform public.staff_hub_unlock_roster(test_week,rev);
  perform public.staff_hub_save_and_lock_roster(test_week,rev,bad);rev:=rev+1;
  if (public.staff_hub_roster_lock_status(test_week)->>'can_edit')::boolean then raise exception 'Save and lock did not relock';end if;
  -- No test data survives this deliberate subtransaction rollback.
  raise exception using errcode='ZP001',message='Tests complete; rollback sample';
 exception when sqlstate 'ZP001' then null;
 end;
 if exists(select 1 from public.staff_hub_weeks where week_start=test_week) then raise exception 'Test sample rollback failed';end if;
 raise notice 'Late Start: save/reload, independent endpoints, permissions, conflicts and publish locking tests passed; sample rolled back';
end $$;

commit;
select 'Late Start installed; transactional tests passed' as result;
