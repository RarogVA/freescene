(function install(config, target, inheritedSink) {
  const window = target || globalThis;
  const document = window.document;
  const getComputedStyle = window.getComputedStyle.bind(window);
  if (window.__freesceneControls?.document === document) return;
  try { config.prepare?.(window); } catch (_) {}
  const topFrame = window === window.top;
  let enabled = topFrame, native = true, selected = null, lastReport = 0;
  const hidden = new Map();
  let sink = window.webkit?.messageHandlers?.FreeSceneControls || inheritedSink;
  const scope = () => topFrame && config.rootSelector ? document.querySelector(config.rootSelector) : document;
  const visible = element => {
    const rect = element.getBoundingClientRect(), style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden';
  };
  const restore = () => {
    for (const [element, value] of hidden) {
      if (value === null) element.removeAttribute('style'); else element.setAttribute('style', value);
    }
    hidden.clear();
    if (selected && selected.__freesceneOriginalControls !== undefined) selected.controls = selected.__freesceneOriginalControls;
  };
  const conceal = element => {
    if (!hidden.has(element)) hidden.set(element, element.getAttribute('style'));
    element.style.setProperty('visibility', 'hidden', 'important');
    element.style.setProperty('pointer-events', 'none', 'important');
  };
  const present = video => {
    if (!native || !video) return;
    if (video.__freesceneOriginalControls === undefined) video.__freesceneOriginalControls = video.controls;
    video.controls = false;
    // Keep the media in its original DOM: player frameworks retain their event
    // handlers, DRM session and source selection. Only sibling UI is concealed.
    let branch = video;
    while (branch && branch !== document.body) {
      const parent = branch.parentElement;
      if (!parent) break;
      for (const sibling of parent.children) {
        if (sibling !== branch && !['SCRIPT','STYLE','LINK'].includes(sibling.tagName)) conceal(sibling);
      }
      branch = parent;
    }
  };
  const forward = command => {
    const root = scope();
    if (!root) return;
    for (const frame of root.querySelectorAll('iframe')) {
      if (!visible(frame)) continue;
      // document.open can discard a same-origin frame's message listeners while
      // keeping its Window and bridge object alive. Call that bridge directly.
      try {
        const bridge = frame.contentDocument && frame.contentWindow.__freesceneControls;
        if (bridge?.document === frame.contentDocument) { bridge.command(command); continue; }
      } catch (_) {}
      frame.contentWindow?.postMessage({type: 'freescene-controls', command}, '*');
    }
  };
  let motionVideo = null, motionPosition = 0, motionTime = 0, movingUntil = 0;
  const physicallyPlaying = video => {
    const now = performance.now();
    if (video !== motionVideo) {
      motionVideo = video; motionPosition = video.currentTime; motionTime = now; movingUntil = 0;
    }
    const delta = video.currentTime - motionPosition;
    const elapsed = Math.max(0, now - motionTime) / 1000;
    if (video.paused || video.ended || video.seeking || !video.isConnected ||
        delta < 0 || delta > Math.max(.5, elapsed * (video.playbackRate || 1) * 2)) movingUntil = 0;
    else if (delta > 0) movingUntil = now + 1200;
    motionPosition = video.currentTime; motionTime = now;
    return movingUntil > now;
  };
  const report = () => {
    if (!selected || !enabled || !selected.isConnected || !visible(selected)) return;
    const now = Date.now(); if (now - lastReport < 200) return; lastReport = now;
    const video = selected;
    sink?.postMessage({
      position: Number.isFinite(video.currentTime) ? video.currentTime : 0,
      duration: Number.isFinite(video.duration) ? video.duration : 0,
      paused: video.paused, ended: video.ended, buffering: video.readyState < 3,
      playing: physicallyPlaying(video),
      volume: video.volume, muted: video.muted, seekable: video.seekable.length > 0
    });
  };
  const command = value => {
    if (!enabled || !value || typeof value.action !== 'string') return;
    if (value.action === 'native') { native = value.value === true; restore(); present(selected); }
    const video = selected;
    if (video && video.isConnected && visible(video)) {
      switch (value.action) {
        case 'toggle': if (video.paused) video.play().catch(() => {}); else video.pause(); break;
        case 'seek': if (Number.isFinite(value.value) && Number.isFinite(video.duration)) video.currentTime = Math.max(0, Math.min(video.duration, value.value)); break;
        case 'skip': if (Number.isFinite(value.value) && Math.abs(value.value) <= 10 && Number.isFinite(video.duration)) video.currentTime = Math.max(0, Math.min(video.duration, video.currentTime + value.value)); break;
        case 'mute': video.muted = !video.muted; break;
        case 'volume': if (Number.isFinite(value.value)) {video.muted = false; video.volume = Math.max(0, Math.min(1, value.value));} break;
      }
      report();
    } else forward(value);
  };
  const refresh = () => {
    if (!enabled) return;
    const root = scope(); if (!root) return;
    const videos = [...root.querySelectorAll('video')].filter(video => visible(video) && (video.readyState >= 1 || video.currentSrc || video.getAttribute('src')) && !video.closest('.ad,.ads,.advertisement,.video-ads,.ima-ad-container'));
    videos.sort((a,b) => (Number.isFinite(b.duration) ? b.duration : 0) - (Number.isFinite(a.duration) ? a.duration : 0));
    if (selected !== (videos[0] || null)) {restore(); selected = videos[0] || null;}
    present(selected); report();
    for (const frame of root.querySelectorAll('iframe')) if (visible(frame)) {
      // document.write/srcdoc players do not always receive a WebKit document-start
      // script. Same-origin frames can install the bridge without changing URLs.
      try { if (frame.contentDocument) { install({prepare: config.prepare}, frame.contentWindow, sink); frame.contentWindow.__freesceneControls?.activate(native, sink); } } catch (_) {}
      frame.contentWindow?.postMessage({type:'freescene-controls-enable', native}, '*');
    }
  };
  window.__freesceneControls = {command, refresh, document, activate(value, parentSink) {sink ||= parentSink; enabled = true; native = value; refresh();}};
  window.addEventListener('message', event => {
    if (window === window.parent || event.source !== window.parent) return;
    if (event.data?.type === 'freescene-controls-enable') { enabled = true; native = event.data.native === true; refresh(); }
    else if (event.data?.type === 'freescene-controls') command(event.data.command);
  });
  for (const name of ['play','pause','timeupdate','volumechange','waiting','playing','ended','seeking','seeked']) document.addEventListener(name, report, true);
  setInterval(refresh, 500);
  refresh();
})
