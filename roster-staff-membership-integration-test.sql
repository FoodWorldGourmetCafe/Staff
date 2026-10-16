-- Isolated integration scenarios. All fixtures roll back.
begin;
do $$
declare wk date:=public.staff_hub_membership_week();owner uuid;cells jsonb;s jsonb;rev bigint;fresh integer;request_id text;failed boolean;prior jsonb;
begin
 select user_id into owner from public.admin_users limit 1;
 perform set_config('request.jwt.claim.sub',owner::text,true);
 select jsonb_agg(to_jsonb(array_fill(''::text,array[14]))) into cells from public.staff_hub_directory;
 cells:=jsonb_set(cells,'{0,3}','"59"');
 s:=jsonb_build_object('cells',cells,'published',null,'requests','[]'::jsonb,'transfers','[]'::jsonb,'cleaning','{}'::jsonb);
 perform public.staff_hub_save_week_v2(wk,0,s);
 perform public.staff_hub_save_week_v2(wk-7,0,s);
 perform public.staff_hub_save_week_v2(wk+7,0,s);
 select state into prior from public.staff_hub_weeks where week_start=wk;
 perform public.staff_hub_add_staff_v3('Integration New');
 select slot into fresh from public.staff_hub_directory where name='Integration New';
 select state,revision into s,rev from public.staff_hub_weeks where week_start=wk;
 if jsonb_array_length(s->'cells')<>(select count(*) from public.staff_hub_directory) or s#>>'{cells,0,3}'<>'59' then raise exception 'Directory expansion lost shifts or left invalid rows';end if;
 if public.staff_hub_staff_active_in_week(fresh,wk-7) or not public.staff_hub_staff_active_in_week(fresh,wk) then raise exception 'Join boundary failed';end if;
 perform public.staff_hub_remove_staff_v3(0);
 if not public.staff_hub_staff_active_in_week(0,wk) or public.staff_hub_staff_active_in_week(0,wk+7) or not public.staff_hub_staff_active_in_week(0,wk-7) then raise exception 'Departure boundary failed';end if;
 -- A departing employee can still edit availability and request withdrawal this week.
 perform set_config('request.jwt.claim.sub','',true);
 s:=jsonb_set(s,'{cells,0,4}','"unavailable"');perform public.staff_hub_save_week_v2(wk,rev,s);rev:=rev+1;
 perform public.staff_hub_submit_service_request(wk,rev,jsonb_build_object('kind','withdraw','row',0,'col',3,'planned','59'));rev:=rev+1;
 select state#>>'{serviceRequests,0,id}' into request_id from public.staff_hub_weeks where week_start=wk;
 perform set_config('request.jwt.claim.sub',owner::text,true);
 perform public.staff_hub_decide_service_request(wk,rev,request_id,'rejected');rev:=rev+1;
 perform set_config('request.jwt.claim.sub','',true);
 perform public.staff_hub_submit_service_request(wk,rev,jsonb_build_object('kind','cleaning','day',(wk+1)::text,'planned','[]'::jsonb,'actual','[0]'::jsonb));rev:=rev+1;
 select state#>>'{serviceRequests,1,id}' into request_id from public.staff_hub_weeks where week_start=wk;
 perform set_config('request.jwt.claim.sub',owner::text,true);
 perform public.staff_hub_decide_service_request(wk,rev,request_id,'approved');rev:=rev+1;
 select state into s from public.staff_hub_weeks where week_start=wk;
 s:=jsonb_set(s,'{published}',jsonb_build_object('cells',s->'cells','at',clock_timestamp()));perform public.staff_hub_save_week_v2(wk,rev,s);rev:=rev+1;
 -- Same-week cover/swap remains available after marking departure.
 s:=jsonb_set(s,'{cells,0,3}','""');s:=jsonb_set(s,'{cells,1,3}','"59"');s:=jsonb_set(s,'{published,cells}',s->'cells');
 s:=jsonb_set(s,'{transfers}',jsonb_build_array(jsonb_build_object('from',0,'to',1,'col',3,'source','59','target','','status','approved')));
 perform set_config('request.jwt.claim.sub','',true);perform public.staff_hub_save_week_v2(wk,rev,s);
 -- Following week: departing employee may not mark availability or submit requests.
 select state,revision into s,rev from public.staff_hub_weeks where week_start=wk+7;
 s:=jsonb_set(s,'{cells,0,4}','"unavailable"');failed:=false;
 begin perform public.staff_hub_save_week_v2(wk+7,rev,s);exception when others then failed:=true;end;if not failed then raise exception 'Retired employee edited future availability';end if;
 failed:=false;begin perform public.staff_hub_submit_service_request(wk+7,rev,jsonb_build_object('kind','withdraw','row',0,'col',3,'planned','59'));exception when others then failed:=true;end;if not failed then raise exception 'Retired employee submitted future request';end if;
 -- Before joining: new employee cannot edit a historic week.
 select state,revision into s,rev from public.staff_hub_weeks where week_start=wk-7;
 s:=jsonb_set(s,array['cells',fresh::text,'4'],'"unavailable"');failed:=false;
 begin perform public.staff_hub_save_week_v2(wk-7,rev,s);exception when others then failed:=true;end;if not failed then raise exception 'New employee edited pre-join week';end if;
end $$;
rollback;
