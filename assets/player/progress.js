(function install(config, target, inheritedSink) {
  const window = target || globalThis;
  const document = window.document;
  const getComputedStyle = window.getComputedStyle.bind(window);
  if (window.__freescenePlayback?.document === document) return;
  let sink = window.FreeScenePlayback || inheritedSink;
  const topFrame = window === window.top;
  let enabled = topFrame;
  let restored = false;
  let selected = null;
  let lastSent = 0;
  const scope = () => topFrame && config.rootSelector
    ? document.querySelector(config.rootSelector) : document;
  const visible = element => {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
  };
  const report = force => {
    const video = selected;
    if (!enabled || !video || !video.isConnected || !restored) return;
    if (!Number.isFinite(video.duration) || video.duration <= 0) return; // Live streams have no bookmark.
    if (!force && Date.now() - lastSent < 1000) return;
    lastSent = Date.now();
    sink?.postMessage(JSON.stringify({
      position: Math.round(video.currentTime * 1000),
      duration: Math.round(video.duration * 1000), ended: video.ended,
      playing: !video.paused && !video.ended && !video.seeking && video.readyState >= 3
    }));
  };
  const refresh = () => {
    if (!enabled) return;
    const root = scope();
    if (!root) return;
    const videos = [...root.querySelectorAll('video')].filter(video =>
      visible(video) && video.readyState >= 1 && Number.isFinite(video.duration) && video.duration > 0 &&
      !video.closest('.ad,.ads,.advertisement,.video-ads,.ima-ad-container') &&
      // Do not apply a movie bookmark to a short preroll.
      !(config.duration > 0 && video.duration * 1000 < config.duration * 0.8)
    ).sort((a, b) => b.duration - a.duration);
    const video = videos[0];
    if (video && video !== selected) {
      selected = video;
      for (const event of ['timeupdate', 'pause', 'ended', 'seeking', 'seeked', 'waiting', 'playing']) {
        video.addEventListener(event, () => { if (video === selected) report(event !== 'timeupdate'); });
      }
    }
    if (selected && !restored) {
      try {
        if (config.position >= 0) {
          selected.currentTime = Math.min(config.position / 1000, Math.max(0, selected.duration - 1));
        }
        restored = true;
      } catch (_) { /* Metadata/seekable ranges may arrive on the next tick. */ }
    }
    report(false);
    // Enable only the visible branch selected by the provider adapter. This also
    // reaches nested cross-origin players and frames inserted after page load.
    for (const frame of root.querySelectorAll('iframe')) {
      if (visible(frame)) {
        try {
          if (frame.contentDocument) {
            install(config, frame.contentWindow, sink);
            frame.contentWindow.__freescenePlayback?.activate(sink);
          }
        } catch (_) {}
        frame.contentWindow?.postMessage({type: 'freescene-playback-enable'}, '*');
      }
    }
  };
  window.__freescenePlayback = {flush: () => report(true), document, activate(parentSink) {sink ||= parentSink; enabled = true; refresh();}};
  window.addEventListener('message', event => {
    if (event.source === window.parent && window !== window.parent && event.data?.type === 'freescene-playback-enable') {
      enabled = true;
      refresh();
    }
  });
  document.addEventListener('loadedmetadata', refresh, true);
  window.addEventListener('pagehide', () => report(true));
  setInterval(refresh, 1000);
  refresh();
})
