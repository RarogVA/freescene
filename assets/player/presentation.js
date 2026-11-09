(initialMode => {
  const modes = ['contain', 'cover', 'fill'];
  if (window.__freescenePresentation) {
    window.__freescenePresentation.setMode(initialMode);
    return;
  }
  let mode = modes[initialMode] ? initialMode : 0;
  let scheduled = false;
  const send = (frame, data) => frame?.postMessage(data, '*');
  const broadcast = () => {
    for (const frame of document.querySelectorAll('iframe')) {
      send(frame.contentWindow, {type: 'freescene-presentation', mode});
    }
  };
  const apply = () => {
    scheduled = false;
    if (!document.documentElement) return;
    let style = document.getElementById('freescene-presentation-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'freescene-presentation-style';
      document.documentElement.append(style);
    }
    const css = `html,body{background:#000!important}video{background:#000!important;object-fit:${modes[mode]}!important;width:100%!important;height:100%!important}`;
    if (style.textContent !== css) style.textContent = css;
    for (const video of document.querySelectorAll('video')) {
      // Provider wrappers can otherwise paint themed or ambient letterboxing.
      for (let parent = video.parentElement; parent; parent = parent.parentElement) {
        parent.style.setProperty('background-color', '#000', 'important');
        parent.style.setProperty('background-image', 'none', 'important');
      }
    }
  };
  const schedule = () => {
    if (scheduled) return;
    scheduled = true;
    setTimeout(apply, 0);
  };
  const setMode = value => {
    if (!Number.isInteger(value) || !modes[value]) return;
    mode = value;
    apply();
    broadcast();
  };
  window.__freescenePresentation = {setMode};
  window.addEventListener('message', event => {
    const data = event.data;
    if (event.source === window.parent && window.parent !== window && data?.type === 'freescene-presentation') {
      setMode(data.mode);
    } else if (data?.type === 'freescene-presentation-ready') {
      for (const frame of document.querySelectorAll('iframe')) {
        if (frame.contentWindow === event.source) send(event.source, {type: 'freescene-presentation', mode});
      }
    }
  });
  new MutationObserver(schedule).observe(document, {childList: true, subtree: true});
  document.addEventListener('DOMContentLoaded', () => { apply(); broadcast(); }, {once: true});
  document.addEventListener('loadedmetadata', schedule, true);
  apply();
  if (window.parent !== window) send(window.parent, {type: 'freescene-presentation-ready'});
})
