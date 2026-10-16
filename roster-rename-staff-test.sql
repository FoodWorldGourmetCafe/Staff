do $$ begin
 begin perform public.staff_hub_rename_staff(0,'Changed');raise exception 'Unauthorized rename accepted';exception when others then if sqlerrm='Unauthorized rename accepted' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$ begin
 perform public.staff_hub_rename_staff(0,'  Alice   Smith  ');
 if (select name from public.staff_hub_directory where slot=0)<>'Alice Smith' then raise exception 'Name normalization failed';end if;
 begin perform public.staff_hub_rename_staff(0,'bob');raise exception 'Duplicate accepted';exception when others then if sqlerrm='Duplicate accepted' then raise;end if;end;
 begin perform public.staff_hub_rename_staff(2,'Former renamed');raise exception 'Inactive accepted';exception when others then if sqlerrm='Inactive accepted' then raise;end if;end;
 begin perform public.staff_hub_rename_staff(0,' ');raise exception 'Empty accepted';exception when others then if sqlerrm='Empty accepted' then raise;end if;end;
 perform public.staff_hub_rename_staff(0,'Alice');
end $$;
select set_config('request.jwt.claim.sub','',false);
