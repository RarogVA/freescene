import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source = await readFile(new URL('../../assets/player/audio_preference.js', import.meta.url), 'utf8');
function fixture(english = true) {
  const context = vm.createContext({document: {}});
  vm.runInContext(`(${source})(${english})`, context);
  const api = context.__freesceneAudio;
  const list = [];
  const listeners = [];
  list.addEventListener = (_, listener) => listeners.push(listener);
  const video = {currentSrc: 'episode1', audioTracks: list};
  const track = (language, label = '', enabled = false, extras = {}) => ({language, label, enabled, ...extras});
  const change = () => listeners.forEach(listener => listener());
  return {api, list, video, track, change};
}
for (const code of ['en', 'eng', 'en-US', 'en_GB']) {
  const f = fixture(); const ru = f.track('ru','',true), en = f.track(code);
  f.list.push(ru, en);f.api.refresh(f.video);f.change();
  assert.equal(en.enabled,true);assert.equal(ru.enabled,false);
  // The provider's own selector wins after automatic selection.
  en.enabled=false;ru.enabled=true;f.change();f.api.refresh(f.video);
  assert.equal(ru.enabled,true);assert.equal(en.enabled,false);
}
{
 const f=fixture();const ru=f.track('ru','',true);f.list.push(ru);f.api.refresh(f.video);
 const original=f.track('ja','Original');f.list.push(original);f.api.refresh(f.video);f.change();assert.equal(original.enabled,true);
 const commentary=f.track('en','Commentary'), main=f.track('eng');f.list.push(commentary,main);f.api.refresh(f.video);f.change();assert.equal(main.enabled,true);assert.equal(commentary.enabled,false);
 f.api.manual(f.video);main.enabled=false;ru.enabled=true;f.change();f.api.refresh(f.video);assert.equal(ru.enabled,true);
 // A new source re-evaluates metadata, not the old numeric track position.
 f.video.currentSrc='episode2';f.list.splice(0,f.list.length, f.track('en'),f.track('ru','',true));f.api.refresh(f.video);assert.equal(f.list[0].enabled,true);
}
{
 const f=fixture(false);f.list.push(f.track('ru','',true),f.track('en'));f.api.refresh(f.video);assert.equal(f.list[0].enabled,true);
 const unknown=fixture();unknown.list.push(unknown.track('','Stereo',true),unknown.track('','Track 2'));unknown.api.refresh(unknown.video);assert.equal(unknown.list[0].enabled,true);
 assert.equal(unknown.api.score(unknown.track('ru','English')),0);
 assert.equal(unknown.api.score(unknown.track('und','English')),200);
 const bad=fixture();bad.list.push(bad.track('ru','',true),bad.track('en','',false,{supported:false}));bad.api.refresh(bad.video);assert.equal(bad.list[0].enabled,true);
 const absent=fixture();delete absent.video.audioTracks;absent.api.refresh(absent.video);assert.equal(absent.api.tracks(absent.video).length,0);
}
console.log('Audio preference: languages, original, roles, late tracks, manual override, new source and fallback passed.');
