const fs=require('fs'),vm=require('vm'),assert=require('assert');
for(const file of ['index.html']){
 const outer=fs.readFileSync(file,'utf8');const roster=JSON.parse(outer.match(/id="embeddedRoster">([\s\S]*?)<\/script>/)[1]);
 for(const [label,html] of [['outer',outer],['roster',roster]]){let n=0;for(const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)){if(/application\/json|\bsrc=/.test(match[1]))continue;new vm.Script(match[2],{filename:file+':'+label+':'+(++n)});}}
 assert(!outer.includes("if(document.hidden)send('lock')"));assert(!outer.includes("pagehide',()=>send('lock')"));
 const calls=[],w={cells:[['','','59']],published:null};const context={record:()=>w,isAdmin:false,rosterLoading:false,lockBusy:false,openServiceRequest:(...args)=>calls.push(args)};vm.createContext(context);
 const open=roster.slice(roster.indexOf('function openRequest('),roster.indexOf("$('request-form').onsubmit"));vm.runInContext(open,context);context.openRequest(0,2);assert.deepEqual(calls,[['withdraw',0,2]]);context.isAdmin=true;context.openRequest(0,2);assert.equal(calls.length,1);context.isAdmin=false;context.rosterLoading=true;context.openRequest(0,2);assert.equal(calls.length,1);
 const modeStart=roster.indexOf('let modeRequest=0,verifiedAdminUser=null;');
 const modeEnd=roster.indexOf('const CLEANING_KEY=',modeStart);
 const storage=new Map(),elements=new Map(),messages=[];
 const element=id=>{
  if(!elements.has(id))elements.set(id,{hidden:true,close(){},click(){return this.onclick?.();}});
  return elements.get(id);
 };
 let session=null;
 const rosterDb={
  auth:{getSession:async()=>({data:{session}})},
  from:()=>({select:()=>({eq:(_,id)=>({maybeSingle:async()=>({data:id==='owner'?{user_id:id}:null})})})})
 };
 const mode={isAdmin:false,$:element,rosterDb,notify(){},parent:{postMessage:message=>messages.push(message)},localStorage:{getItem:key=>storage.get(key),setItem:(key,value)=>storage.set(key,value)}};
 vm.createContext(mode);
 const visibilityRule=roster.match(/function render\(\)\{([^;]+;)/)[1];
 vm.runInContext('function render(){'+visibilityRule+'} function switchMode(admin){isAdmin=admin;render();}\n'+roster.slice(modeStart,modeEnd),mode);
 const modeSwitch=element('mode-switch');
 (async()=>{
  await mode.restoreAdminMode('INITIAL_SESSION',null);
  assert(modeSwitch.hidden);
  session={user:{id:'staff'}};
  await mode.restoreAdminMode('SIGNED_IN',session);
  assert(modeSwitch.hidden);
  await mode.showUnlock();
  assert.equal(messages[0].action,'login');
  session={user:{id:'owner'}};
  await mode.restoreAdminMode('SIGNED_IN',session);
  assert(mode.isAdmin&&!modeSwitch.hidden);
  element('staff-mode').click();
  assert(!mode.isAdmin&&!modeSwitch.hidden);
  await mode.restoreAdminMode('TOKEN_REFRESHED',session);
  assert(!mode.isAdmin&&!modeSwitch.hidden);
  await element('admin-mode').click();
  assert(mode.isAdmin&&!modeSwitch.hidden);
  element('staff-mode').click();
  await mode.restoreAdminMode('SIGNED_OUT',null);
  assert(!mode.isAdmin&&modeSwitch.hidden);
  await mode.restoreAdminMode('INITIAL_SESSION',session);
  assert(!mode.isAdmin&&!modeSwitch.hidden);
  console.log(file+': JavaScript syntax, draft request routing and roster mode visibility passed');
 })().catch(error=>{
  console.error(error);
  process.exitCode=1;
 });
}
