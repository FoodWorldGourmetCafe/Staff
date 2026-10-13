begin;
do $$
declare wk date:=date '2098-01-06';s jsonb;cells jsonb;rev bigint:=1;id text;failed boolean;
begin
 select jsonb_agg(to_jsonb(array_fill(''::text,array[14]))) into cells from public.staff_hub_directory;
 cells:=jsonb_set(cells,array['0','11'],'"59"');
 s:=jsonb_build_object('cells',cells,'published',jsonb_build_object('cells',cells,'at','2098-01-06'),'requests','[]'::jsonb,'transfers','[]'::jsonb,'cleaning','{}'::jsonb);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 insert into public.staff_hub_weeks(week_start,state,revision) values(wk,s,rev);
 perform set_config('request.jwt.claim.sub','',true);
 perform public.staff_hub_submit_service_request(wk,rev,jsonb_build_object('kind','leave','row',0,'col',11,'planned','59'));rev:=rev+1;
 select state into s from public.staff_hub_weeks where week_start=wk;id:=s#>>'{serviceRequests,0,id}';
 if s#>>'{published,cells,0,11}'<>'59' then raise exception 'Pending leave changed shift';end if;
 failed:=false;begin perform public.staff_hub_submit_service_request(wk,rev,jsonb_build_object('kind','leave','row',0,'col',11,'planned','59'));exception when others then failed:=true;end;
 if not failed then raise exception 'Duplicate leave accepted';end if;
 failed:=false;begin perform public.staff_hub_decide_service_request(wk,rev,id,'approved');exception when others then failed:=true;end;
 if not failed then raise exception 'Staff approved leave';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 perform public.staff_hub_decide_service_request(wk,rev,id,'rejected');rev:=rev+1;
 select state into s from public.staff_hub_weeks where week_start=wk;
 if s#>>'{published,cells,0,11}'<>'59' then raise exception 'Rejected leave changed shift';end if;
 perform set_config('request.jwt.claim.sub','',true);
 perform public.staff_hub_submit_service_request(wk,rev,jsonb_build_object('kind','leave','row',0,'col',11,'planned','59'));rev:=rev+1;
 select state into s from public.staff_hub_weeks where week_start=wk;id:=s#>>'{serviceRequests,1,id}';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 -- A pending leave does not unlock direct roster edits.
 failed:=false;begin update public.staff_hub_weeks set state=jsonb_set(state,'{cells,0,11}','"58"') where week_start=wk;exception when others then failed:=true;end;
 if not failed then raise exception 'Leave unlocked arbitrary edit';end if;
 -- Changed shifts cannot be approved using an old request.
 update public.staff_hub_weeks set roster_edit_owner=auth.uid(),roster_edit_until=now()+interval '5 minutes' where week_start=wk;
 update public.staff_hub_weeks set state=jsonb_set(jsonb_set(state,'{cells,0,11}','"58"'),'{published,cells,0,11}','"58"') where week_start=wk;
 failed:=false;begin perform public.staff_hub_decide_service_request(wk,rev,id,'approved');exception when others then failed:=true;end;
 if not failed then raise exception 'Stale leave approved';end if;
 update public.staff_hub_weeks set state=s where week_start=wk;
 update public.staff_hub_weeks set roster_edit_owner=null,roster_edit_until=null where week_start=wk;
 perform public.staff_hub_decide_service_request(wk,rev,id,'approved');rev:=rev+1;
 select state into s from public.staff_hub_weeks where week_start=wk;
 if s#>>'{published,cells,0,11}'<>'' or s#>>'{cells,0,11}'<>'' then raise exception 'Leave did not remove shift';end if;
 if s#>>'{serviceRequests,1,planned}'<>'59' or s#>>'{serviceRequests,1,status}'<>'approved' then raise exception 'Leave history lost';end if;
 perform public.staff_hub_save_week_v2(wk,rev,s);
 failed:=false;begin perform public.staff_hub_decide_service_request(wk,rev+1,id,'approved');exception when others then failed:=true;end;
 if not failed then raise exception 'Leave approved twice';end if;
end $$;
rollback;
