-- Rename globally without changing staff slots or weekly roster data.
begin;
create or replace function public.staff_hub_rename_staff(p_slot integer,p_name text)
returns void language plpgsql security definer set search_path='' as $$
declare normalized text:=btrim(regexp_replace(p_name,'[[:space:]]+',' ','g'));
begin
 if not coalesce(public.staff_hub_is_admin(),false) then raise exception 'Administrator access required';end if;
 if normalized is null or char_length(normalized) not between 1 and 40 then raise exception 'Enter an employee name with 1–40 characters.';end if;
 lock table public.staff_hub_directory in share row exclusive mode;
 if not exists(select 1 from public.staff_hub_directory where slot=p_slot and active) then raise exception 'Active employee not found';end if;
 if exists(select 1 from public.staff_hub_directory where active and slot<>p_slot and lower(name)=lower(normalized)) then raise exception 'An employee already has this name. Add a surname or another identifier.';end if;
 update public.staff_hub_directory set name=normalized where slot=p_slot and active;
end $$;
revoke all on function public.staff_hub_rename_staff(integer,text) from public,anon;
grant execute on function public.staff_hub_rename_staff(integer,text) to authenticated;
commit;
