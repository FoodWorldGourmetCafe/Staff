begin;
do $$
declare wk date:=date '2098-01-13';s jsonb;cells jsonb;after_state jsonb;q jsonb;failed boolean;
begin
 select jsonb_agg(to_jsonb(array_fill(''::text,array[14]))) into cells from public.staff_hub_directory;
 cells:=jsonb_set(jsonb_set(cells,'{0,11}','"59"'),'{1,11}','"unavailable"');
 s:=jsonb_build_object('cells',cells,'published',jsonb_build_object('cells',cells,'at','2098-01-13'),'requests','[]'::jsonb,'transfers','[]'::jsonb,'cleaning','{}'::jsonb);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 insert into public.staff_hub_weeks(week_start,state,revision) values(wk,s,1);
 perform set_config('request.jwt.claim.sub','',true);
 q:=jsonb_build_object('from',0,'to',1,'col',11,'source','59','target','unavailable','status','approved');
 cells:=jsonb_set(jsonb_set(cells,'{0,11}','"unavailable"'),'{1,11}','"59"');
 after_state:=jsonb_set(jsonb_set(jsonb_set(s,'{cells}',cells),'{published,cells}',cells),'{transfers}',jsonb_build_array(q));
 failed:=false;begin perform public.staff_hub_save_week_v2(wk,1,after_state);exception when others then failed:=true;end;
 if not failed then raise exception 'Unavailable swap did not require second confirmation';end if;
 after_state:=jsonb_set(after_state,'{transfers,0,availabilityConfirmed}','true');
 perform public.staff_hub_save_week_v2(wk,1,after_state);
 select state into s from public.staff_hub_weeks where week_start=wk;
 if s#>>'{cells,1,11}'<>'59' or s#>>'{published,cells,0,11}'<>'unavailable' then raise exception 'Swap failed';end if;
 -- Owner approvals on a locked roster also validate the confirmation marker.
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 perform public.staff_hub_save_week_v2(wk,2,s);
end $$;
rollback;
