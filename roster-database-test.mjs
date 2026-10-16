import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';
const db=new PGlite();await db.waitReady;
await db.exec(`create role anon;create role authenticated;create schema auth;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table public.admin_users(user_id uuid primary key);insert into admin_users values('00000000-0000-0000-0000-000000000001');
create table public.staff_hub_directory(slot integer primary key,name text,active boolean not null default true,created_at timestamptz default now(),retired_at timestamptz);insert into staff_hub_directory(slot,name,active) values(0,'Alice',true),(1,'Bob',true),(2,'Former',false);
create table public.staff_hub_weeks(week_start date primary key,state jsonb,revision bigint,updated_at timestamptz default now());
create function public.staff_hub_is_admin() returns boolean language sql as $$select exists(select 1 from public.admin_users where user_id=auth.uid())$$;
create function public.staff_hub_shift_minutes(code text) returns integer language plpgsql as $$declare times text[];begin
 if code in ('','unavailable') then return 0;end if;
 times:=case code when '103' then array['10:00','15:00'] when '113' then array['11:00','15:00'] when '1033' then array['10:30','15:00'] when '1133' then array['11:30','15:00'] when '58' then array['17:00','20:00'] when '59' then array['17:00','21:00'] else array[substring(code,8,5),substring(code,14,5)] end;
 if code is null or times[1] is null or times[2] is null then raise exception 'Invalid shift';end if;
 return extract(epoch from (times[2]::time-times[1]::time))/60;end$$;
create function public.staff_hub_get_week_v2(p_week date) returns jsonb language sql as $$select coalesce((select jsonb_build_object('state',state,'revision',revision) from public.staff_hub_weeks where week_start=p_week),jsonb_build_object('state',null,'revision',0))$$;
create function public.staff_hub_save_week(p_week date,p_revision bigint,p_state jsonb) returns jsonb language plpgsql as $$begin return public.staff_hub_save_week_v2(p_week,p_revision,p_state);end$$;
`);
for(const file of ['roster-rename-staff.sql','roster-rename-staff.sql','roster-rename-staff-test.sql','roster-publish-lock.sql','roster-actual-adjustments.sql','roster-draft-request-lock.sql','roster-service-requests.sql','roster-service-requests.sql','roster-service-requests-test.sql','roster-leave-requests.sql','roster-leave-requests.sql','roster-leave-requests-test.sql','roster-unavailable-swap.sql','roster-unavailable-swap.sql','roster-unavailable-swap-test.sql','roster-disable-leave.sql','roster-disable-leave.sql','roster-disable-leave-test.sql','roster-staff-membership.sql','roster-staff-membership.sql','roster-staff-membership-test.sql','roster-staff-membership-integration-test.sql','roster-access-hardening.sql','roster-access-hardening.sql']){
 try{await db.exec(fs.readFileSync(file,'utf8'));console.log(file+': passed');}catch(e){console.log(file+': FAILED: '+e.message);console.log(e.where||'');process.exitCode=1;break;}
}
await db.close();

