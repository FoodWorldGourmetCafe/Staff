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
  if(name==='staff_hub_decide_service_request'){approved=clone(args);const q=state.serviceRequests.find(q=>q.id===args.p_id);q.status=args.p_status;if(q.status==='approved'){if(q.kind==='withdraw')state.cells[q.row][q.col]='unavailable';else state.cleaning[q.day]=q.actual;}return {data:{revision:++revision}};}
  throw Error('Unexpected RPC: '+name);
 }};window.supabase={createClient:()=>client};
 for(const match of roster.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)){if(/\bsrc=|application\/json/.test(match[1]))continue;window.eval(match[2]);}
 await tick();await tick();
 const $=id=>window.document.getElementById(id);
 assert.equal($('staff-mode').getAttribute('aria-pressed'),'true');
 window.document.querySelector('[data-row="0"][data-col="3"]').click();assert.equal($('service-request').open,true);assert.equal(state.cells[0][3],'59');
 await $('service-form').onsubmit({preventDefault(){}});assert.equal(submitted.p_request.kind,'withdraw');assert.equal(state.cells[0][3],'59');assert.equal($('service-request').open,false);
 session={user:{id:'owner'}};callback('SIGNED_IN',session);await tick();await tick();assert.equal($('admin-mode').getAttribute('aria-pressed'),'true');assert.equal($('approvals-open').textContent,'Pending · 1');
 $('approvals-open').click();assert.deepEqual([...window.document.querySelectorAll('.approval-category h3')].map(x=>x.textContent),['申请划班 · 待审批 1','工时变化 · 待审批 0','Bathroom · 待审批 0']);
 const button=[...$('approvals-list').querySelectorAll('button')].find(b=>b.textContent==='Approve');await button.onclick();assert.equal(approved.p_status,'approved');assert.equal(state.cells[0][3],'unavailable');assert.equal($('approvals-open').textContent,'Pending · 0');
 $('staff-mode').click();const preference=window.localStorage.getItem('staffhub.roster.mode');$('staff-mode').click();assert.equal(window.localStorage.getItem('staffhub.roster.mode'),preference);callback('TOKEN_REFRESHED',session);await tick();assert.equal($('staff-mode').getAttribute('aria-pressed'),'true');
 $('admin-mode').click();await tick();await tick();assert.equal($('admin-mode').getAttribute('aria-pressed'),'true');window.dispatchEvent(new window.MessageEvent('message',{source:window.parent,data:{channel:'staff-hub-roster',action:'admin'}}));await tick();assert.equal($('admin-mode').getAttribute('aria-pressed'),'true');
 session=null;callback('SIGNED_OUT',null);await tick();assert.equal($('staff-mode').getAttribute('aria-pressed'),'true');
 const bathroom=window.document.querySelector('[data-cleaning-request="1"]');bathroom.click();assert.equal($('service-request').open,true);$('service-cleaner').value='1';await $('service-form').onsubmit({preventDefault(){}});assert.equal(submitted.p_request.kind,'cleaning');assert.deepEqual(submitted.p_request.actual,[1]);
 assert.equal(window.document.querySelectorAll('.roster-instructions li').length,3);assert.equal(window.document.querySelectorAll('aside.owner').length,0);
 console.log(file+': full page initialization, draft submission, categorized approval, red line, mode persistence, idempotent admin message, logout and Bathroom submission passed');
 await window.happyDOM.abort();
}
