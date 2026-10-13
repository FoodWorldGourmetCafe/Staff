begin;
do $$
declare wk date:=date '2098-01-20';cells jsonb;s jsonb;failed boolean;
begin
 select jsonb_agg(to_jsonb(array_fill(''::text,array[14]))) into cells from public.staff_hub_directory;
 cells:=jsonb_set(cells,'{0,9}','"59"');
 s:=jsonb_build_object('cells',cells,'published',jsonb_build_object('cells',cells,'at','2098-01-20'),'requests','[]'::jsonb,'transfers','[]'::jsonb,'cleaning','{}'::jsonb,'serviceRequests',jsonb_build_array(jsonb_build_object('id','retired-pending','kind','leave','row',0,'col',9,'planned','59','status','pending'),jsonb_build_object('id','retired-approved','kind','leave','row',0,'col',11,'planned','59','status','approved')));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 insert into public.staff_hub_weeks(week_start,state,revision) values(wk,s,1);
 perform set_config('request.jwt.claim.sub','',true);
 failed:=false;begin perform public.staff_hub_submit_service_request(wk,1,jsonb_build_object('kind','leave','row',0,'col',9,'planned','59'));exception when others then failed:=sqlerrm='Leave requests are no longer available';end;
 if not failed then raise exception 'Retired leave submission accepted';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 failed:=false;begin perform public.staff_hub_decide_service_request(wk,1,'retired-pending','approved');exception when others then failed:=sqlerrm='Leave requests are no longer available';end;
 if not failed then raise exception 'Retired leave approval accepted';end if;
 if (select state from public.staff_hub_weeks where week_start=wk) is distinct from s then raise exception 'Retirement modified history or roster';end if;
end $$;
rollback;
