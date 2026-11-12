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
  const report = force => {
    const video = selected;
    if (!enabled || !video || !video.isConnected || !restored) return;
    if (!Number.isFinite(video.duration) || video.duration <= 0) return; // Live streams have no bookmark.
    if (!force && Date.now() - lastSent < 1000) return;
    lastSent = Date.now();
    sink?.postMessage(JSON.stringify({
      position: Math.round(video.currentTime * 1000),
      duration: Math.round(video.duration * 1000), ended: video.ended,
      playing: physicallyPlaying(video)
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
  const command = value => {
    if (!enabled || !value || !['toggle', 'settings', 'audio', 'text', 'speed'].includes(value.action)) return;
    const video = selected;
    if (video?.isConnected && visible(video)) {
      if (value.action === 'toggle') {
        if (video.paused) video.play().catch(() => {}); else video.pause();
      } else if (value.action === 'settings') {
        const tracks = (list, text) => Array.from(list || []).slice(0, 32).map((track, i) => ({
          label: (track.label || track.language || String(i + 1)).slice(0, 128),
          selected: text ? track.mode === 'showing' : track.enabled
        }));
        sink?.postMessage(JSON.stringify({type: 'controls', speed: video.playbackRate,
          audio: tracks(video.audioTracks, false), text: tracks(video.textTracks, true)}));
      } else if (value.action === 'speed' && [.25,.5,.75,1,1.25,1.5,2].includes(value.value)) {
        video.playbackRate = value.value;
      } else if (Number.isInteger(value.value) && value.value >= -1 && value.value < 32) {
        const tracks = value.action === 'audio' ? video.audioTracks : video.textTracks;
        if (tracks && value.value < tracks.length) for (let i = 0; i < tracks.length; i++) {
          if (value.action === 'audio') tracks[i].enabled = i === value.value;
          else tracks[i].mode = i === value.value ? 'showing' : 'disabled';
        }
      }
      return;
    }
    for (const frame of scope()?.querySelectorAll('iframe') || []) {
      if (visible(frame)) frame.contentWindow?.postMessage({type: 'freescene-playback-command', command: value}, '*');
    }
  };
  const toggle = () => command({action: 'toggle'});
  window.__freescenePlayback = {command, toggle, flush: () => report(true), document, activate(parentSink) {sink ||= parentSink; enabled = true; refresh();}};
  window.addEventListener('message', event => {
    if (event.source !== window.parent || window === window.parent) return;
    if (event.data?.type === 'freescene-playback-command') command(event.data.command);
    if (event.data?.type === 'freescene-playback-enable') {
      enabled = true;
      refresh();
    }
  });
  document.addEventListener('loadedmetadata', refresh, true);
  window.addEventListener('pagehide', () => report(true));
  setInterval(refresh, 1000);
  refresh();
})
