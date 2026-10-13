import fs from 'node:fs';import assert from 'node:assert/strict';import {Window} from 'happy-dom';
const tick=()=>new Promise(r=>setTimeout(r,30));
for(const file of ['index.html','christmas.html']){
 const html=fs.readFileSync(file,'utf8'),roster=JSON.parse(html.match(/id="embeddedRoster">([\s\S]*?)<\/script>/)[1]);
 const window=new Window({url:'https://example.test',settings:{disableJavaScriptEvaluation:true,disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});
 window.document.write(roster);window.ResizeObserver=class{observe(){}};window.setInterval=()=>0;window.clearInterval=()=>{};
 const directory=[{slot:0,name:'Alice',active:true},{slot:1,name:'Bob',active:true},{slot:2,name:'Former',active:false}];let state={cells:directory.map(()=>Array(14).fill('')),published:null,requests:[],transfers:[],cleaning:{}};state.cells[0][3]='59';let revision=1,session=null,callback,submitted,approved;
 const clone=x=>JSON.parse(JSON.stringify(x));
 const auth={getSession:async()=>({data:{session}}),onAuthStateChange:cb=>{callback=cb;return{};}};
 const client={auth,from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:session?{user_id:session.user.id}:null})})})}),rpc:async(name,args)=>{
  if(name==='staff_hub_list_staff')return {data:directory};
  if(name.startsWith('staff_hub_get_week'))return {data:{state:clone(state),revision}};
  if(name==='staff_hub_roster_lock_status')return {data:{version:1,can_edit:false}};
  if(name.startsWith('staff_hub_save_week')){state=clone(args.p_state);return {data:{revision:++revision}};}
  if(name==='staff_hub_submit_service_request'){submitted=clone(args);state.serviceRequests||=[];state.serviceRequests.push({...args.p_request,id:'request-'+state.serviceRequests.length,status:'pending'});return {data:{revision:++revision}};}
  if(name==='staff_hub_decide_service_request'){approved=clone(args);const q=state.serviceRequests.find(q=>q.id===args.p_id);q.status=args.p_status;if(q.status==='approved'){if(q.kind==='withdraw')state.cells[q.row][q.col]='unavailable';else if(q.kind==='leave'){state.cells[q.row][q.col]='';state.published.cells[q.row][q.col]='';}else state.cleaning[q.day]=q.actual;}return {data:{revision:++revision}};}
  throw Error('Unexpected RPC: '+name);
 }};window.supabase={createClient:()=>client};
 for(const match of roster.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)){if(/\bsrc=|application\/json/.test(match[1]))continue;window.eval(match[2]+(match[2].includes('function loadWeekFromSupabase')?';window.testSwap=()=>{transferProposal={from:0,to:1,col:9,source:record().published.cells[0][9],target:record().published.cells[1][9],week:dateKey(week)};};window.testLoad=loadWeekFromSupabase;window.testTotal=()=>total(record().published.cells[0].map((code,c)=>adjustedShift(record(),0,c,code)));':''));}
 await tick();await tick();
 const $=id=>window.document.getElementById(id);
 assert.equal($('staff-mode').getAttribute('aria-pressed'),'true');
 window.document.querySelector('[data-row="0"][data-col="3"]').click();assert.equal($('service-request').open,true);assert.equal(state.cells[0][3],'59');
 await $('service-form').onsubmit({preventDefault(){}});assert.equal(submitted.p_request.kind,'withdraw');assert.equal(state.cells[0][3],'59');assert.equal($('service-request').open,false);
 session={user:{id:'owner'}};callback('SIGNED_IN',session);await tick();await tick();assert.equal($('admin-mode').getAttribute('aria-pressed'),'true');assert.equal($('approvals-open').textContent,'Pending · 1');
 $('approvals-open').click();assert.deepEqual([...window.document.querySelectorAll('.approval-category h3')].map(x=>x.textContent),['申请划班 · 待审批 1','请假 · 待审批 0','工时变化 · 待审批 0','Bathroom · 待审批 0']);
 assert.equal(window.document.querySelectorAll('.approval-tabs button').length,4);
 const categories=[...window.document.querySelectorAll('.approval-category')];
 assert.equal(categories.filter(x=>!x.hidden).length,1);
 const tabs=[...window.document.querySelectorAll('.approval-tabs button')];tabs[2].click();assert.equal(categories[2].hidden,false);assert.equal(categories[0].hidden,true);tabs[0].click();
 assert.equal(window.document.querySelectorAll('.approval-category-header button').length,4);
 assert.ok([...window.document.querySelectorAll('.approval-history')].every(x=>!x.open));
 const button=[...$('approvals-list').querySelectorAll('button')].find(b=>b.textContent==='Approve');await button.onclick();assert.equal(approved.p_status,'approved');assert.equal(state.cells[0][3],'unavailable');assert.equal($('approvals-open').textContent,'Pending · 0');
 assert.equal(window.document.querySelector('.approval-history').querySelectorAll('section').length,1);
 $('staff-mode').click();const preference=window.localStorage.getItem('staffhub.roster.mode');$('staff-mode').click();assert.equal(window.localStorage.getItem('staffhub.roster.mode'),preference);callback('TOKEN_REFRESHED',session);await tick();assert.equal($('staff-mode').getAttribute('aria-pressed'),'true');
 $('admin-mode').click();await tick();await tick();assert.equal($('admin-mode').getAttribute('aria-pressed'),'true');window.dispatchEvent(new window.MessageEvent('message',{source:window.parent,data:{channel:'staff-hub-roster',action:'admin'}}));await tick();assert.equal($('admin-mode').getAttribute('aria-pressed'),'true');
 session=null;callback('SIGNED_OUT',null);await tick();assert.equal($('staff-mode').getAttribute('aria-pressed'),'true');
 const bathroom=window.document.querySelector('[data-cleaning-request="1"]');bathroom.click();assert.equal($('service-request').open,true);$('service-cleaner').value='1';await $('service-form').onsubmit({preventDefault(){}});assert.equal(submitted.p_request.kind,'cleaning');assert.deepEqual(submitted.p_request.actual,[1]);
 assert.equal(window.document.querySelectorAll('.roster-instructions li').length,3);assert.equal(window.document.querySelectorAll('aside.owner').length,0);
 state.cells[0][11]='59';state.published={cells:clone(state.cells),at:new Date().toISOString()};
 await window.testLoad();
 window.document.querySelector('[data-row="0"][data-col="11"]').click();assert.equal($('request').open,true);
 $('request-leave').click();assert.equal($('service-request').open,true);assert.ok($('service-context').textContent.includes('17:00–21:00'));
 await $('service-form').onsubmit({preventDefault(){}});assert.equal(submitted.p_request.kind,'leave');assert.equal(submitted.p_request.col,11);assert.equal(state.published.cells[0][11],'59');
 session={user:{id:'owner'}};callback('SIGNED_IN',session);await tick();await tick();$('approvals-open').click();
 const leaveGroup=window.document.querySelector('[data-category="请假"].approval-category');assert.ok(leaveGroup.textContent.includes('17:00–21:00'));
 await [...leaveGroup.querySelectorAll('button')].find(b=>b.textContent==='Approve').onclick();assert.equal(state.published.cells[0][11],'');assert.equal(state.cells[0][11],'');
 assert.equal(window.document.querySelector('[data-row="0"][data-col="11"] .red-line'),null);assert.equal(window.document.querySelector('[data-row="0"][data-col="11"]').textContent,'');assert.equal(window.testTotal(),0);
 $('approvals').close();$('staff-mode').click();
 state.cells[0][9]='59';state.cells[1][9]='unavailable';state.published.cells=clone(state.cells);await window.testLoad();
 window.testSwap();$('transfer-submit').click();assert.equal($('confirm').open,true);assert.ok($('confirm-text').textContent.includes('agreed'));assert.equal(state.cells[0][9],'59');
 $('confirm').querySelector('[data-close]').click();assert.equal(state.cells[0][9],'59');assert.equal(state.cells[1][9],'unavailable');
 window.testSwap();$('transfer-submit').click();$('confirm-action').click();await new Promise(r=>setTimeout(r,400));
 assert.equal(state.cells[0][9],'unavailable');assert.equal(state.cells[1][9],'59');assert.equal(state.published.cells[1][9],'59');assert.equal(state.transfers.at(-1).availabilityConfirmed,true);
 assert.equal(window.document.querySelector('[data-row="1"][data-col="9"]').textContent,'5-9');
 console.log(file+': full page initialization, draft submission, categorized approval, red line, mode persistence, idempotent admin message, logout, Bathroom submission and published Saturday leave approval/hours passed');
 await window.happyDOM.abort();
}
