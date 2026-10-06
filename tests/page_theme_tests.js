const assert=require('node:assert/strict');
const fs=require('node:fs'); const vm=require('node:vm'); const path=require('node:path');
const script=fs.readFileSync(path.join(__dirname,'../engine/page_theme_js.h'),'utf8').split('R"JS(')[1].split(')JS"')[0];
let time=0, next=1, reads=0, mutations, connected=false;
const timers=new Map(), events=new Map(), messages=[];
function add(name,fn) { if(!events.has(name)) events.set(name,[]); events.get(name).push(fn); }
function fire(name) { for(const fn of events.get(name)||[]) fn(); }
function advance(ms) {
 const end=time+ms;
 while(true) {
  let id, job;
  for(const [key,value] of timers) if(value.at<=end && (!job||value.at<job.at)) { id=key; job=value; }
  if(!job) break;
  timers.delete(id); time=job.at; job.fn();
 }
 time=end;
}
const root={parentElement:null};
const document={hidden:false,documentElement:root,body:root,addEventListener:add,
 createElement:()=>({getContext:()=>({clearRect(){},fillRect(){},getImageData:()=>({data:[18,18,18,255]})})}),
 elementFromPoint:()=>root,querySelectorAll:()=>[]};
const window={addEventListener:add,webkit:{messageHandlers:{slateTheme:{postMessage:v=>messages.push(v)}}}};
vm.runInNewContext(script,{document,window,innerWidth:1000,innerHeight:800,
 getComputedStyle:()=>{ reads++; return {backgroundColor:'#121212',colorScheme:'dark'}; },
 setTimeout:(fn,ms)=>{const id=next++; timers.set(id,{fn,at:time+ms}); return id;},clearTimeout:id=>timers.delete(id),
 MutationObserver:class {constructor(fn){mutations=fn;} observe(){connected=true;} disconnect(){connected=false;}}});
advance(300); assert.equal(messages.length,1); assert.ok(connected);
document.hidden=true; fire('visibilitychange');
assert.equal(connected,false); assert.equal(timers.size,0);
const before=reads;
for(let i=0;i<1000;i++) mutations();
fire('resize'); advance(60000);
assert.equal(reads,before,'hidden tabs perform no theme layout/color reads');
assert.equal(timers.size,0,'hidden tabs own no theme timers');
document.hidden=false; fire('visibilitychange'); assert.ok(connected);
advance(300); assert.ok(reads>before,'foregrounding refreshes the latest color');
fire('pagehide'); assert.equal(timers.size,0); assert.equal(connected,false);
fire('pageshow'); advance(300); assert.ok(connected,'page cache restores monitoring');
console.log('Hidden theme checks: 0 layout reads / 0 timers across 1000 mutations and 60 seconds; foreground and page-cache resume passed');
