const save = document.querySelector('#save');
const status = document.querySelector('#status');

save.addEventListener('click', async () => {
  save.disabled = true;
  try {
    const [tab] = await chrome.tabs.query({
      active: true,
      currentWindow: true,
    });
    if (!/^https?:\/\//i.test(tab?.url || '')) {
      status.textContent = 'Open a web page first.';
      return;
    }
    // The custom protocol opens the app's review flow; capture never saves silently.
    window.location.href = `thelist-capture://save?url=${encodeURIComponent(tab.url)}`;
    status.textContent = 'If nothing opens, enable browser capture in The List settings.';
  } catch {
    status.textContent = 'The page could not be opened in The List. Try again.';
  } finally {
    save.disabled = false;
  }
});
