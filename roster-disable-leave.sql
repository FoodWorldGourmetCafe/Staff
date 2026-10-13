-- Retire leave requests without changing roster data or history.
-- Run after the installed leave and unavailable-swap migrations.
begin;
do $$
declare definition text;
begin
 select pg_get_functiondef('public.staff_hub_submit_service_request(date,bigint,jsonb)'::regprocedure) into definition;
 if position('Leave requests are no longer available' in definition)=0 then
  if position('if p_week is null' in definition)=0 then raise exception 'Unexpected service submit definition';end if;
  definition:=replace(definition,'if p_week is null','if p_request->>''kind''=''leave'' then raise exception ''Leave requests are no longer available'';end if; if p_week is null');
  execute definition;
 end if;
 select pg_get_functiondef('public.staff_hub_decide_service_request(date,bigint,text,text)'::regprocedure) into definition;
 if position('Leave requests are no longer available' in definition)=0 then
  if position('if q is null' in definition)=0 then raise exception 'Unexpected service decision definition';end if;
  definition:=replace(definition,'if q is null','if q->>''kind''=''leave'' then raise exception ''Leave requests are no longer available'';end if; if q is null');
  execute definition;
 end if;
end $$;
commit;
