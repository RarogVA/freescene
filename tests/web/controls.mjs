// Real HTML media + cross-origin iframe exercise of the native control bridge.
// Uses an isolated headless Chrome profile and a generated local video, no accounts.
import {spawn, execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'../..');
const temp=await mkdtemp(join(tmpdir(),'freescene-web-controls-'));
const source=await readFile(join(root,'assets/player/web_controls.js'),'utf8');
execFileSync('ffmpeg',['-v','error','-f','lavfi','-i','color=c=black:s=160x90:r=1','-t','180','-c:v','libx264','-pix_fmt','yuv420p','-g','1','-movflags','+faststart',join(temp,'video.mp4')]);
const media=await readFile(join(temp,'video.mp4'));
const reports=[];
let chrome, socket, server;
try {
  server=createServer((request,response)=>{
    if(request.url==='/media.mp4'){response.writeHead(200,{'Content-Type':'video/mp4','Content-Length':media.length});response.end(media);return;}
    const port=server.address().port;
    const frame=request.url==='/frame';
    const nested=request.url==='/nested';
    response.setHeader('Content-Type','text/html');
    response.end(`<!doctype html><style>html,body{margin:0;background:#17181b}video,iframe{width:640px;height:360px}button{height:40px}</style>
      ${nested ? `<section id="selected"><iframe src="http://localhost:${port}/frame"></iframe></section><iframe style="display:none" src="http://localhost:${port}/frame"></iframe>` : `<video controls muted></video><button id="vendor">Quality / tracks</button>`}
      <script>window.reports=[];window.webkit={messageHandlers:{FreeSceneControls:{postMessage:value=>{window.reports.push(value);if(window!==parent)parent.postMessage({testReport:value},'*')}}}};
      window.addEventListener('message',event=>{if(event.data.testReport)window.reports.push(event.data.testReport)});
      (${source})({rootSelector:${nested ? "'#selected'" : 'null'}});
      ${nested ? '' : `fetch('/media.mp4').then(r=>r.blob()).then(blob=>document.querySelector('video').src=URL.createObjectURL(blob));`}
      </script>`);
  });
  await new Promise(resolve=>server.listen(0,'0.0.0.0',resolve));
  const port=server.address().port;
  chrome=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',['--headless=new','--no-first-run','--no-default-browser-check','--disable-background-networking','--autoplay-policy=no-user-gesture-required','--remote-debugging-port=0','--user-data-dir='+join(temp,'profile'),'about:blank'],{stdio:['ignore','ignore','pipe']});
  const endpoint=await new Promise((resolve,reject)=>{let log='';const timeout=setTimeout(()=>reject(Error('Chrome timeout')),15000);chrome.stderr.on('data',chunk=>{log+=chunk;const match=log.match(/DevTools listening on (ws:\/\/\S+)/);if(match){clearTimeout(timeout);resolve(match[1]);}});chrome.on('error',reject);});
  socket=new WebSocket(endpoint);await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject;});
  let sequence=0;const pending=new Map();
  socket.onmessage=event=>{const msg=JSON.parse(event.data);if(msg.id){const job=pending.get(msg.id);pending.delete(msg.id);msg.error?job.reject(Error(JSON.stringify(msg.error))):job.resolve(msg.result);}};
  const cdp=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));});
  const {targetId}=await cdp('Target.createTarget',{url:'about:blank'});
  const {sessionId}=await cdp('Target.attachToTarget',{targetId,flatten:true});
  const send=(method,params={})=>cdp(method,params,sessionId);
  await send('Page.enable');await send('Runtime.enable');
  const evaluate=async expression=>{const result=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result.value;};
  const until=async expression=>{for(let i=0;i<80;i++){if(await evaluate(expression))return;await new Promise(r=>setTimeout(r,100));}throw Error('Timeout: '+expression);};
  const command=async(action,value)=>evaluate(`window.__freesceneControls.command(${JSON.stringify({action,value})})`);
  for(const route of ['/direct','/nested']){
    await send('Page.navigate',{url:`http://127.0.0.1:${port}${route}`});
    await until('window.reports?.at(-1)?.duration===180');
    assert.equal(await evaluate('window.reports.at(-1).paused'),true);
    await command('toggle');await until('window.reports.at(-1)?.playing===true');
    if(route==='/direct') {
      await evaluate(`Object.defineProperty(document.querySelector('video'),'readyState',{get:()=>2,configurable:true})`);
      await new Promise(r=>setTimeout(r,1500));
      assert.equal(await evaluate('window.reports.at(-1).playing'),true,'Actual video progress counts with HAVE_CURRENT_DATA');
      await evaluate(`delete document.querySelector('video').readyState`);
    }
    await command('seek',120);await until('window.reports.at(-1)?.position>=120');
    await command('toggle');await until('window.reports.at(-1)?.paused===true');
    await command('skip',-10);await until('window.reports.at(-1)?.position<112');
    await command('volume',.25);await until('window.reports.at(-1)?.volume===.25');
    await command('mute');await until('window.reports.at(-1)?.muted===true');
    if(route==='/direct'){
      assert.equal(await evaluate('getComputedStyle(document.querySelector("#vendor")).visibility'),'hidden');
      await command('native',false);
      assert.equal(await evaluate('getComputedStyle(document.querySelector("#vendor")).visibility'),'visible');
      assert.equal(await evaluate('document.querySelector("video").controls'),true);
      await command('native',true);
      assert.equal(await evaluate('getComputedStyle(document.querySelector("#vendor")).visibility'),'hidden');
    }
    reports.push({route,passed:true,actions:['play','pause','seek','skip','volume','mute','provider controls']});
  }
  console.log(JSON.stringify(reports,null,2));
  await cdp('Browser.close');
} finally {
  socket?.close();chrome?.kill();server?.close();
  await new Promise(r=>setTimeout(r,200));await rm(temp,{recursive:true,force:true});
}
