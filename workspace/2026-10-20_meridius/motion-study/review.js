// Local video review only; no network calls, analytics or persistence.
if (new URLSearchParams(location.search).get('theme') === 'dark') document.documentElement.dataset.reviewTheme = 'dark';
document.querySelectorAll('.study').forEach(section => {
  const video = section.querySelector('video');
  const output = section.querySelector('output');
  const update = () => { output.textContent = `${video.currentTime.toFixed(2)} s · frame ${Math.round(video.currentTime * 30)} · ${video.playbackRate}×`; };
  ['timeupdate', 'loadedmetadata', 'seeked', 'ratechange'].forEach(event => video.addEventListener(event, update));
  section.querySelectorAll('button').forEach(button => button.addEventListener('click', () => {
    if (button.dataset.rate) video.playbackRate = Number(button.dataset.rate);
    if (button.dataset.step || button.dataset.seek) {
      video.pause();
      // Seek to the first captured frame at/after a marker, then advance
      // exactly one displayed frame. Fractional event times stay in source.
      const time = button.dataset.seek ? Math.ceil(Number(button.dataset.seek) * 30) / 30 : (Math.round(video.currentTime * 30) + Number(button.dataset.step)) / 30;
      video.currentTime = Math.max(0, Math.min(video.duration - 1 / 30, time));
    }
    if (button.dataset.action === 'replay') {
      document.querySelectorAll('video').forEach(other => { if (other !== video) other.pause(); });
      video.currentTime = 0;
      video.play().catch(() => { output.textContent = 'Use the video Play control to start playback.'; });
    }
    update();
  }));
  update();
});
