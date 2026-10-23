import fs from 'node:fs';import assert from 'node:assert/strict';import {Window} from 'happy-dom';
const tick=()=>new Promise(r=>setTimeout(r,30));
for(const file of ['index.html']){
 const html=fs.readFileSync(file,'utf8'),roster=JSON.parse(html.match(/id="embeddedRoster">([\s\S]*?)<\/script>/)[1]);
 const window=new Window({url:'https://example.test',settings:{disableJavaScriptEvaluation:true,disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});
 window.document.write(roster);window.ResizeObserver=class{observe(){}};window.setInterval=()=>0;window.clearInterval=()=>{};
 const directory=[{slot:0,name:'Alice',active:true},{slot:1,name:'Bob',active:true},{slot:2,name:'Former',active:false}];let state={cells:directory.map(()=>Array(14).fill('')),published:null,requests:[],transfers:[],cleaning:{}};state.cells[0][3]='59';let revision=1,session=null,callback,submitted,approved,membershipWeek;
 const clone=x=>JSON.parse(JSON.stringify(x));
 const auth={getSession:async()=>({data:{session}}),onAuthStateChange:cb=>{callback=cb;return{};}};
 const client={auth,from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:session?{user_id:session.user.id}:null})})})}),rpc:async(name,args)=>{
  if(name==='staff_hub_add_staff_v3'){directory.push({slot:directory.length,name:args.p_name,active:true,starts_week:membershipWeek});return {};}
  if(name==='staff_hub_remove_staff_v3'){const end=new Date(membershipWeek+'T12:00:00Z');end.setUTCDate(end.getUTCDate()+7);Object.assign(directory[args.p_slot],{active:false,ends_week:end.toISOString().slice(0,10)});return {};}
  if(name==='staff_hub_rename_staff'){directory[args.p_slot].name=args.p_name;return {}; }
  if(name==='staff_hub_list_staff_v3')return {data:directory};
  if(name.startsWith('staff_hub_get_week'))return {data:{state:clone(state),revision}};
  if(name==='staff_hub_roster_lock_status')return {data:{version:1,can_edit:false}};
  if(name.startsWith('staff_hub_save_week')){state=clone(args.p_state);return {data:{revision:++revision}};}
  if(name==='staff_hub_submit_service_request'){submitted=clone(args);state.serviceRequests||=[];state.serviceRequests.push({...args.p_request,id:'request-'+state.serviceRequests.length,status:'pending'});return {data:{revision:++revision}};}
  if(name==='staff_hub_decide_service_request'){approved=clone(args);const q=state.serviceRequests.find(q=>q.id===args.p_id);q.status=args.p_status;if(q.status==='approved'){if(q.kind==='withdraw')state.cells[q.row][q.col]='unavailable';else if(q.kind==='leave'){state.cells[q.row][q.col]='';state.published.cells[q.row][q.col]='';}else state.cleaning[q.day]=q.actual;}return {data:{revision:++revision}};}
  throw Error('Unexpected RPC: '+name);
 }};window.supabase={createClient:()=>client};
 for(const match of roster.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)){if(/\bsrc=|application\/json/.test(match[1]))continue;window.eval(match[2]+(match[2].includes('function loadWeekFromSupabase')?';window.testWeek=()=>dateKey(week);window.testSetWeek=async key=>{week=new Date(key+"T12:00:00");await loadWeekFromSupabase();render();};window.testExport=()=>exportRows({cells:cleanCells(record().cells)});window.testSwap=()=>{transferProposal={from:0,to:1,col:9,source:record().published.cells[0][9],target:record().published.cells[1][9],week:dateKey(week)};};window.testLoad=loadWeekFromSupabase;window.testTotal=()=>total(record().published.cells[0].map((code,c)=>adjustedShift(record(),0,c,code)));':''));}
 await tick();await tick();
 const $=id=>window.document.getElementById(id);
 assert.equal($('staff-mode').getAttribute('aria-pressed'),'true');
 window.document.querySelector('[data-row="0"][data-col="3"]').click();assert.equal($('service-request').open,true);assert.equal(state.cells[0][3],'59');
 await $('service-form').onsubmit({preventDefault(){}});assert.equal(submitted.p_request.kind,'withdraw');assert.equal(state.cells[0][3],'59');assert.equal($('service-request').open,false);
 session={user:{id:'owner'}};callback('SIGNED_IN',session);await tick();await tick();assert.equal($('admin-mode').getAttribute('aria-pressed'),'true');assert.equal($('approvals-open').textContent,'Pending · 1');
 assert.equal($('staff-management-menu').hidden,false);assert.equal($('roster-more'),null);
 assert.ok($('manual-mode').closest('.mode-toolbar'));
 const beforeManual=clone(state);$('manual-mode').click();assert.equal($('manual-mode').getAttribute('aria-pressed'),'true');
 window.document.querySelector('[data-row="0"][data-col="3"]').click();assert.equal($('manual').open,true);assert.deepEqual(state,beforeManual);assert.equal($('manual-start').value,'17:00');assert.equal($('manual-end').value,'21:00');$('manual').close();$('manual-mode').click();assert.equal($('manual-mode').getAttribute('aria-pressed'),'false');
 window.document.querySelector('[data-row="1"][data-col="3"]').click();assert.ok($('table-body').querySelector('[data-row="1"][data-col="3"]').textContent);window.document.querySelector('[data-row="1"][data-col="3"]').click();assert.equal($('table-body').querySelector('[data-row="1"][data-col="3"]').textContent,'');
 

 assert.equal($('staff-rename-open').hidden,false);
 const beforeRename=clone(state);$('staff-rename-open').click();assert.equal($('staff-new-name').value,'Alice');
 $('staff-new-name').value='Bob';await $('staff-manager-form').onsubmit({preventDefault(){}});assert.ok($('staff-manager-error').textContent.includes('already'));assert.equal(directory[0].name,'Alice');
 $('staff-new-name').value='Alice Smith';await $('staff-manager-form').onsubmit({preventDefault(){}});assert.equal(directory[0].name,'Alice Smith');assert.equal($('staff-manager').open,false);assert.deepEqual(state,beforeRename);assert.ok($('table-body').textContent.includes('Alice Smith'));
 $('approvals-open').click();assert.deepEqual([...window.document.querySelectorAll('.approval-category h3')].map(x=>x.textContent),['Shift Removal · Pending 1','Hours Adjustments · Pending 0','Bathroom · Pending 0']);
 assert.equal(window.document.querySelectorAll('.approval-tabs button').length,3);
 const categories=[...window.document.querySelectorAll('.approval-category')];
 assert.equal(categories.filter(x=>!x.hidden).length,1);
 const tabs=[...window.document.querySelectorAll('.approval-tabs button')];tabs[2].click();assert.equal(categories[2].hidden,false);assert.equal(categories[0].hidden,true);tabs[0].click();
 assert.equal(window.document.querySelectorAll('.approval-category-header button').length,3);
 assert.ok([...window.document.querySelectorAll('.approval-history')].every(x=>!x.open));
 const button=[...$('approvals-list').querySelectorAll('button')].find(b=>b.textContent==='Approve');await button.onclick();assert.equal(approved.p_status,'approved');assert.equal(state.cells[0][3],'unavailable');assert.equal($('approvals-open').textContent,'Pending · 0');
 assert.equal(window.document.querySelector('.approval-history').querySelectorAll('section').length,1);
 $('staff-mode').click();const preference=window.localStorage.getItem('staffhub.roster.mode');$('staff-mode').click();assert.equal(window.localStorage.getItem('staffhub.roster.mode'),preference);assert.equal($('staff-management-menu').hidden,true);assert.equal($('roster-more'),null);callback('TOKEN_REFRESHED',session);await tick();assert.equal($('staff-mode').getAttribute('aria-pressed'),'true');
 $('admin-mode').click();await tick();await tick();assert.equal($('admin-mode').getAttribute('aria-pressed'),'true');window.dispatchEvent(new window.MessageEvent('message',{source:window.parent,data:{channel:'staff-hub-roster',action:'admin'}}));await tick();assert.equal($('admin-mode').getAttribute('aria-pressed'),'true');
 session=null;callback('SIGNED_OUT',null);await tick();assert.equal($('staff-mode').getAttribute('aria-pressed'),'true');
 const bathroom=window.document.querySelector('[data-cleaning-request="1"]');bathroom.click();assert.equal($('service-request').open,true);$('service-cleaner').value='1';await $('service-form').onsubmit({preventDefault(){}});assert.equal(submitted.p_request.kind,'cleaning');assert.deepEqual(submitted.p_request.actual,[1]);
 assert.equal(window.document.querySelectorAll('.roster-instructions li').length,3);assert.equal(window.document.querySelectorAll('aside.owner').length,0);
 assert.equal($('request-leave'),null);
 $('approvals').close();$('staff-mode').click();
 state.cells[0][9]='59';state.cells[1][9]='unavailable';state.published={cells:clone(state.cells),at:new Date().toISOString()};await window.testLoad();
 window.testSwap();$('transfer-submit').click();assert.equal($('confirm').open,true);assert.ok($('confirm-text').textContent.includes('agreed'));assert.equal(state.cells[0][9],'59');
 $('confirm').querySelector('[data-close]').click();assert.equal(state.cells[0][9],'59');assert.equal(state.cells[1][9],'unavailable');
 window.testSwap();$('transfer-submit').click();$('confirm-action').click();await new Promise(r=>setTimeout(r,400));
 assert.equal(state.cells[0][9],'unavailable');assert.equal(state.cells[1][9],'59');assert.equal(state.published.cells[1][9],'59');assert.equal(state.transfers.at(-1).availabilityConfirmed,true);
 assert.equal(window.document.querySelector('[data-row="1"][data-col="9"]').textContent,'5-9');
 const originalWeek=window.testWeek(),prior=new Date(originalWeek+'T12:00:00Z'),later=new Date(prior);prior.setUTCDate(prior.getUTCDate()-7);later.setUTCDate(later.getUTCDate()+7);
 $('admin-mode').click();await tick();await tick();
 session={user:{id: "owner"}};callback("SIGNED_IN",session);await tick();await tick();$("admin-mode").click();await tick();await tick();const weeklySnapshot=clone(state);
 membershipWeek=originalWeek;await window.testSetWeek(prior.toISOString().slice(0,10));$('staff-add-open').click();$('staff-new-name').value='New Employee';await $('staff-manager-form').onsubmit({preventDefault(){}});
 assert.ok(!$('table-body').textContent.includes('New Employee'));await window.testSetWeek(originalWeek);assert.ok($('table-body').textContent.includes('New Employee'));
 await window.testSetWeek(prior.toISOString().slice(0,10));assert.ok(!$('table-body').textContent.includes('New Employee'));assert.ok(!window.testExport().some(row=>row[0]==='New Employee'));
 await window.testSetWeek(originalWeek);const hoursBeforeRemoval=$('grand-total').textContent;$('staff-remove-open').click();$('staff-remove-select').value='0';await $('staff-manager-form').onsubmit({preventDefault(){}});assert.ok($('table-body').textContent.includes('Alice Smith'));assert.equal($('grand-total').textContent,hoursBeforeRemoval);assert.ok(window.testExport().some(row=>row[0]==='Alice Smith'));
 await window.testSetWeek(prior.toISOString().slice(0,10));assert.ok($('table-body').textContent.includes('Alice Smith'));assert.ok(window.testExport().some(row=>row[0]==='Alice Smith'));
 await window.testSetWeek(later.toISOString().slice(0,10));assert.ok(!$('table-body').textContent.includes('Alice Smith'));assert.ok($('table-body').textContent.includes('New Employee'));assert.deepEqual(state,weeklySnapshot);
 console.log(file+': full page initialization, draft submission, categorized approval, red line, mode persistence, idempotent admin message, logout, Bathroom submission and unavailable swap second confirmation passed');
 await window.happyDOM.abort();
}

