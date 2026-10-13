-- Run AFTER roster-service-requests.sql. Idempotent leave request upgrade.
-- Run AFTER roster-actual-adjustments.sql and roster-draft-request-lock.sql.
-- Adds separate requests without reopening draft actual-time requests.
begin;
create or replace function public.staff_hub_service_cleaning(before_state jsonb,after_state jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare result jsonb:=before_state->'cleaning';q jsonb;prior jsonb;
begin
 for q in select value from jsonb_array_elements(coalesce(after_state->'serviceRequests','[]'::jsonb)) loop
  select value into prior from jsonb_array_elements(coalesce(before_state->'serviceRequests','[]'::jsonb)) where value->>'id'=q->>'id';
  if q->>'kind'='cleaning' and q->>'status'='approved' and prior->>'status'='pending' then
   if (q-'status') is distinct from (prior-'status') or coalesce(result->(q->>'day'),'[]'::jsonb) is distinct from q->'planned' then raise exception 'Bathroom assignment changed; reject and resubmit';end if;
   result:=jsonb_set(result,array[q->>'day'],q->'actual');
  end if;
 end loop;
 return result;
end $$;
-- Retain the installed publish guard and its editing/transfer protections.
do $$
declare definition text;
begin
 select pg_get_functiondef('public.staff_hub_guard_published_roster()'::regprocedure) into definition;
 if position('public.staff_hub_service_cleaning(old.state,new.state)' in definition)>0 then return;end if;
 if position('new.state->''cleaning'' is distinct from old.state->''cleaning''' in definition)=0 then raise exception 'Install roster-actual-adjustments.sql first';end if;
 definition:=replace(definition,'new.state->''cleaning'' is distinct from old.state->''cleaning''',
 'new.state->''cleaning'' is distinct from public.staff_hub_service_cleaning(old.state,new.state)');
 execute definition;
end $$;
create or replace function public.staff_hub_submit_service_request(p_week date,p_revision bigint,p_request jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare w public.staff_hub_weeks;q jsonb;items jsonb;r integer;c integer;day date;slot integer;
begin
 if p_week is null or extract(isodow from p_week)<>1 then raise exception 'Invalid week';end if;
 perform pg_advisory_xact_lock(782431,1);
 perform pg_advisory_xact_lock(hashtext('staff-hub'),(p_week-date '2000-01-01'));
 select * into w from public.staff_hub_weeks where week_start=p_week for update;
 if w.week_start is null or w.revision is distinct from p_revision then raise exception 'Conflict: refresh the roster and retry';end if;
 if jsonb_typeof(p_request) is distinct from 'object' then raise exception 'Invalid request';end if;
 if p_request->>'kind'='withdraw' then
  r:=(p_request->>'row')::integer;c:=(p_request->>'col')::integer;
  if r is null or c is null or c not between 2 and 13 or not exists(select 1 from public.staff_hub_directory d where d.slot=r and d.active)
   or (w.state->'published' is not null and w.state->'published'<>'null'::jsonb)
   or public.staff_hub_shift_minutes(p_request->>'planned')<=0
   or w.state#>>array['cells',r::text,c::text] is distinct from p_request->>'planned' then raise exception 'Draft shift changed';end if;
  q:=jsonb_build_object('kind','withdraw','row',r,'col',c,'planned',p_request->>'planned');
 elsif p_request->>'kind'='leave' then
  r:=(p_request->>'row')::integer;c:=(p_request->>'col')::integer;
  if r is null or c is null or c not between 2 and 13 or not exists(select 1 from public.staff_hub_directory d where d.slot=r and d.active)
   or w.state->'published' is null or w.state->'published'='null'::jsonb
   or public.staff_hub_shift_minutes(p_request->>'planned')<=0
   or w.state#>>array['cells',r::text,c::text] is distinct from p_request->>'planned'
   or w.state#>>array['published','cells',r::text,c::text] is distinct from p_request->>'planned' then raise exception 'Published shift changed';end if;
  q:=jsonb_build_object('kind','leave','row',r,'col',c,'planned',p_request->>'planned');
 elsif p_request->>'kind'='cleaning' then
  day:=(p_request->>'day')::date;
  if day is null or day<=p_week or day>p_week+6 or coalesce(w.state->'cleaning'->day::text,'[]'::jsonb) is distinct from p_request->'planned'
   or jsonb_typeof(p_request->'actual') is distinct from 'array' or jsonb_array_length(p_request->'actual')>1 then raise exception 'Invalid Bathroom change';end if;
  if jsonb_array_length(p_request->'actual')=1 then
   slot:=(p_request->'actual'->>0)::integer;
   if slot is null or not exists(select 1 from public.staff_hub_directory d where d.slot=(p_request->'actual'->>0)::integer and active) then raise exception 'Invalid cleaner';end if;
  end if;
  if p_request->'actual'=p_request->'planned' then raise exception 'Select a different cleaner or Not cleaned';end if;
  q:=jsonb_build_object('kind','cleaning','day',day::text,'planned',p_request->'planned','actual',case when slot is null then '[]'::jsonb else jsonb_build_array(slot) end);
 else raise exception 'Invalid request kind';end if;
 items:=coalesce(w.state->'serviceRequests','[]'::jsonb);
 if jsonb_array_length(items)>=1000 then raise exception 'Too many requests';end if;
 if exists(select 1 from jsonb_array_elements(items) x where x->>'status'='pending' and
  ((q->>'kind' in ('withdraw','leave') and x->>'kind' in ('withdraw','leave') and x->'row'=q->'row' and x->'col'=q->'col') or
   (q->>'kind'='cleaning' and x->>'kind'='cleaning' and x->'day'=q->'day'))) then raise exception 'A request is already awaiting approval';end if;
 q:=q||jsonb_build_object('id',gen_random_uuid()::text,'status','pending','submittedAt',clock_timestamp());
 update public.staff_hub_weeks set state=jsonb_set(w.state,'{serviceRequests}',items||jsonb_build_array(q)),revision=revision+1,updated_at=now() where week_start=p_week;
 return jsonb_build_object('revision',w.revision+1);
end $$;
create or replace function public.staff_hub_decide_service_request(p_week date,p_revision bigint,p_id text,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare w public.staff_hub_weeks;s jsonb;q jsonb;i integer;r integer;c integer;
begin
 if not coalesce(public.staff_hub_is_admin(),false) then raise exception 'Administrator required';end if;
 if p_week is null or p_status is null or p_status not in ('approved','rejected') then raise exception 'Invalid decision';end if;
 perform pg_advisory_xact_lock(782431,1);
 perform pg_advisory_xact_lock(hashtext('staff-hub'),(p_week-date '2000-01-01'));
 select * into w from public.staff_hub_weeks where week_start=p_week for update;
 if w.week_start is null or w.revision is distinct from p_revision then raise exception 'Conflict: refresh the roster and retry';end if;
 s:=w.state;
 select value,(ordinality-1)::integer into q,i from jsonb_array_elements(coalesce(s->'serviceRequests','[]'::jsonb)) with ordinality where value->>'id'=p_id;
 if q is null or q->>'status'<>'pending' then raise exception 'Request is no longer pending';end if;
 if p_status='approved' then
  if q->>'kind'='withdraw' then
   r:=(q->>'row')::integer;c:=(q->>'col')::integer;
   if (s->'published' is not null and s->'published'<>'null'::jsonb) or s#>>array['cells',r::text,c::text] is distinct from q->>'planned' then raise exception 'Draft shift changed; reject and resubmit';end if;
   s:=jsonb_set(s,array['cells',r::text,c::text],'"unavailable"'::jsonb);
  elsif q->>'kind'='leave' then
   r:=(q->>'row')::integer;c:=(q->>'col')::integer;
   if s->'published' is null or s->'published'='null'::jsonb
    or s#>>array['cells',r::text,c::text] is distinct from q->>'planned'
    or s#>>array['published','cells',r::text,c::text] is distinct from q->>'planned' then raise exception 'Published shift changed; reject and resubmit';end if;
   if exists(select 1 from jsonb_array_elements(s->'requests') a where a->'row'=q->'row' and a->'col'=q->'col' and a->>'status'='pending')
    or exists(select 1 from jsonb_array_elements(s->'transfers') a where a->'col'=q->'col' and (a->'from'=q->'row' or a->'to'=q->'row') and a->>'status'='pending') then raise exception 'Resolve pending time or swap requests before approving leave';end if;
   s:=jsonb_set(s,array['cells',r::text,c::text],'""'::jsonb);
   s:=jsonb_set(s,array['published','cells',r::text,c::text],'""'::jsonb);
  elsif q->>'kind'='cleaning' then
   if coalesce(s->'cleaning'->(q->>'day'),'[]'::jsonb) is distinct from q->'planned' then raise exception 'Bathroom assignment changed; reject and resubmit';end if;
   if exists(select 1 from jsonb_array_elements_text(q->'actual') a where not exists(select 1 from public.staff_hub_directory where slot=a::integer and active)) then raise exception 'Cleaner is no longer active';end if;
   s:=jsonb_set(s,array['cleaning',q->>'day'],q->'actual');
  else raise exception 'Invalid request';end if;
 end if;
 s:=jsonb_set(s,array['serviceRequests',i::text,'status'],to_jsonb(p_status));
 update public.staff_hub_weeks set state=s,revision=revision+1,updated_at=now() where week_start=p_week;
 return jsonb_build_object('revision',w.revision+1);
end $$;
revoke all on function public.staff_hub_service_cleaning(jsonb,jsonb),public.staff_hub_submit_service_request(date,bigint,jsonb),public.staff_hub_decide_service_request(date,bigint,text,text) from public;
grant execute on function public.staff_hub_submit_service_request(date,bigint,jsonb) to anon,authenticated;
grant execute on function public.staff_hub_decide_service_request(date,bigint,text,text) to authenticated;

create or replace function public.staff_hub_leave_cells(before_state jsonb,after_state jsonb,cells jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare q jsonb;prior jsonb;r integer;c integer;
begin
 for q in select value from jsonb_array_elements(coalesce(after_state->'serviceRequests','[]'::jsonb)) where value->>'kind'='leave' loop
  select value into prior from jsonb_array_elements(coalesce(before_state->'serviceRequests','[]'::jsonb)) where value->>'id'=q->>'id';
  if q->>'status'='approved' and q is distinct from prior then
   if prior is null or prior->>'status'<>'pending' or (q-'status') is distinct from (prior-'status') then raise exception 'Leave approval must match pending request';end if;
   r:=(q->>'row')::integer;c:=(q->>'col')::integer;
   if cells#>>array[r::text,c::text] is distinct from q->>'planned' then raise exception 'Published shift changed; reject and resubmit';end if;
   cells:=jsonb_set(cells,array[r::text,c::text],'""'::jsonb);
  end if;
 end loop;
 return cells;
end $$;
revoke all on function public.staff_hub_leave_cells(jsonb,jsonb,jsonb) from public,anon,authenticated;
do $$
declare definition text;
begin
 select pg_get_functiondef('public.staff_hub_guard_published_roster()'::regprocedure) into definition;
 if position('public.staff_hub_leave_cells' in definition)>0 then return;end if;
 if position('if new.state->''cells'' is distinct from expected_cells' in definition)=0 then raise exception 'Install roster-actual-adjustments.sql first';end if;
 definition:=replace(definition,'if new.state->''cells'' is distinct from expected_cells',
 'expected_cells:=public.staff_hub_leave_cells(old.state,new.state,expected_cells); expected_pub:=public.staff_hub_leave_cells(old.state,new.state,expected_pub); if new.state->''cells'' is distinct from expected_cells');
 execute definition;
end $$;

commit;
