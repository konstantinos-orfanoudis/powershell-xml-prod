chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "SSCP_CAPTURE_CONTEXT") return;

  const selectionText = String(window.getSelection?.()?.toString?.() || "").trim();
  const pageText = String(document.body?.innerText || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 12000);

  sendResponse({
    ok: true,
    title: document.title || "Untitled page",
    url: window.location.href,
    selectionText,
    pageText,
  });
  return true;
});

document.documentElement.dataset.sscpCompanionReady = "true";
document.documentElement.dataset.sscpCompanionRuntimeId = chrome.runtime.id;
