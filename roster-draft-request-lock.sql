-- Run in Supabase SQL Editor after the existing roster migrations.
-- Reject new or changed staff adjustments until the stored week is published.
-- Applies to legacy/v2 RPCs and direct writes; existing request history is kept.
begin;
create or replace function public.staff_hub_guard_draft_requests()
returns trigger language plpgsql security definer set search_path='' as $$
declare q jsonb;prior jsonb;
begin
 if coalesce(public.staff_hub_is_admin(),false) then return new;end if;
 if tg_op='INSERT' then
  -- ON CONFLICT saves are checked by the UPDATE trigger against stored state.
  if exists(select 1 from public.staff_hub_weeks where week_start=new.week_start) then return new;end if;
  if jsonb_array_length(coalesce(new.state->'requests','[]'::jsonb))>0 then
   raise exception 'Publish the roster before requesting overtime, early leave or late start';
  end if;
 elsif old.state->'published' is null or old.state->'published'='null'::jsonb then
  for q in select value from jsonb_array_elements(new.state->'requests') loop
   select value into prior from jsonb_array_elements(old.state->'requests')
    where public.staff_hub_request_key(value)=public.staff_hub_request_key(q);
   if q is distinct from prior then
    raise exception 'Publish the roster before requesting overtime, early leave or late start';
   end if;
  end loop;
 end if;
 return new;
end $$;
revoke all on function public.staff_hub_guard_draft_requests() from public,anon,authenticated;
drop trigger if exists staff_hub_draft_request_guard on public.staff_hub_weeks;
create trigger staff_hub_draft_request_guard before insert or update on public.staff_hub_weeks
for each row execute function public.staff_hub_guard_draft_requests();
commit;
