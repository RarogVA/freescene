(function installAudio(english, target) {
  const window = target || globalThis;
  if (window.__freesceneAudio?.document === window.document) return;
  const states = new WeakMap();
  const words = (value, pattern) => new RegExp('(^|[^\\p{L}])(' + pattern + ')([^\\p{L}]|$)', 'iu').test(value || '');
  const score = track => {
    const language = (track.language || '').toLowerCase().replaceAll('_', '-').split('-')[0];
    const known = !['', 'und', 'unk', 'zxx'].includes(language);
    const label = track.label || '';
    const rank = ['en', 'eng'].includes(language) || (!known && words(label, 'english|английский|английская|eng|en')) ? 200
      : words(label, 'original|оригинал|оригинальная') || track.kind === 'original' ? 100 : 0;
    return rank ? rank - (/commentary|комментар|audio description|тифло/iu.test(label) || ['commentary', 'descriptions'].includes(track.kind) ? 10 : 0) : 0;
  };
  const tracks = video => Array.from(video?.audioTracks || []).slice(0, 32);
  const selected = video => tracks(video).filter(t => t.enabled);
  const same = (a, b) => a.length === b.length && a.every((t, i) => t === b[i]);
  const state = video => {
    const source = video.currentSrc || video.getAttribute?.('src') || '';
    let value = states.get(video);
    if (!value || value.source !== source) {
      value = {source, manual: false, expected: selected(video), list: video.audioTracks};
      states.set(video, value);
      video.audioTracks?.addEventListener?.('change', () => {
        if (states.get(video) !== value) return;
        const now = selected(video);
        // Our own change events match expected; a provider/user change wins.
        if (!same(now, value.expected) && value.expected.some(t => tracks(video).includes(t))) value.manual = true;
        value.expected = now;
      });
    }
    return value;
  };
  const refresh = video => {
    if (!video || !english) return;
    const value = state(video);
    if (value.manual) return;
    const available = tracks(video).filter(t => t.supported !== false);
    let best = null, bestScore = 0;
    for (const track of available) {
      const rank = score(track);
      if (rank > bestScore || (rank > 0 && rank === bestScore && track.enabled)) {best = track; bestScore = rank;}
    }
    if (!best || best.enabled) {value.expected = selected(video); return;}
    const before = selected(video);
    try {
      best.enabled = true;
      if (!best.enabled) return;
      for (const track of available) if (track !== best) track.enabled = false;
      value.expected = selected(video);
    } catch (_) {
      for (const track of before) {try {track.enabled = true;} catch (_) {}}
      value.expected = selected(video);
    }
  };
  window.__freesceneAudio = {document: window.document, refresh, score,
    manual(video) {if (video) state(video).manual = true;},
    tracks(video) {return tracks(video).map((track, i) => ({id: String(track.id || i).slice(0,128),
      language: (track.language || '').slice(0,64), kind: (track.kind || '').slice(0,64),
      label: (track.label || track.language || String(i+1)).slice(0,128), selected: !!track.enabled}));}
  };
  window.__freesceneAudioInstall = installAudio;
})
