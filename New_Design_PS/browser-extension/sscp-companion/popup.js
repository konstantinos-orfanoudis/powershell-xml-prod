const DEFAULT_APP_URL = "http://localhost:3000";

const appUrlInput = document.getElementById("app-url");
const statusNode = document.getElementById("status");

function setStatus(message) {
  statusNode.textContent = message;
}

async function getStoredAppUrl() {
  const result = await chrome.storage.sync.get(["sscpTutorUrl"]);
  return result.sscpTutorUrl || DEFAULT_APP_URL;
}

async function getActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) {
    throw new Error("No active tab is available.");
  }
  return tab;
}

async function getPageContext() {
  const tab = await getActiveTab();
  const response = await chrome.tabs.sendMessage(tab.id, {
    type: "SSCP_CAPTURE_CONTEXT",
  });
  if (!response?.ok) {
    throw new Error("The page did not return capture data.");
  }
  return response;
}

async function postCapture(mode) {
  const appUrl = appUrlInput.value.trim() || DEFAULT_APP_URL;
  const context = await getPageContext();
  const text =
    mode === "selection"
      ? context.selectionText || context.pageText
      : context.pageText;

  if (!text) {
    throw new Error("There was no readable text on the current page.");
  }

  const response = await fetch(`${appUrl}/api/sscp/extension/capture`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      title: context.title,
      url: context.url,
      selectionText: context.selectionText,
      pageText: text,
    }),
  });
  const json = await response.json();
  if (!response.ok) {
    throw new Error(json.error || "The tutor rejected the capture.");
  }
  return json.capture;
}

async function captureAndOpenQuiz() {
  const appUrl = appUrlInput.value.trim() || DEFAULT_APP_URL;
  const capture = await postCapture("page");
  await chrome.tabs.create({
    url: `${appUrl}/sscp?workspace=library&captureId=${encodeURIComponent(capture.id)}&intent=quiz`,
  });
  return capture;
}

async function readSelection() {
  const context = await getPageContext();
  const text = context.selectionText || context.pageText;
  if (!text) {
    throw new Error("There was no text available to read aloud.");
  }
  chrome.tts.stop();
  chrome.tts.speak(text.slice(0, 3800), {
    rate: 1,
    enqueue: false,
  });
}

document.getElementById("save-url").addEventListener("click", async () => {
  const nextUrl = appUrlInput.value.trim() || DEFAULT_APP_URL;
  await chrome.storage.sync.set({ sscpTutorUrl: nextUrl });
  setStatus(`Saved tutor URL: ${nextUrl}`);
});

document.getElementById("open-tutor").addEventListener("click", async () => {
  const appUrl = appUrlInput.value.trim() || DEFAULT_APP_URL;
  await chrome.tabs.create({ url: `${appUrl}/sscp` });
});

document.getElementById("capture-page").addEventListener("click", async () => {
  try {
    setStatus("Capturing current page...");
    const capture = await postCapture("page");
    setStatus(`Captured: ${capture.title}`);
  } catch (error) {
    setStatus(error.message || "Page capture failed.");
  }
});

document.getElementById("capture-selection").addEventListener("click", async () => {
  try {
    setStatus("Capturing selected text...");
    const capture = await postCapture("selection");
    setStatus(`Captured selection from: ${capture.title}`);
  } catch (error) {
    setStatus(error.message || "Selection capture failed.");
  }
});

document.getElementById("quiz-page").addEventListener("click", async () => {
  try {
    setStatus("Capturing page and opening quiz flow...");
    const capture = await captureAndOpenQuiz();
    setStatus(`Quiz flow ready for: ${capture.title}`);
  } catch (error) {
    setStatus(error.message || "Quiz flow failed.");
  }
});

document.getElementById("read-selection").addEventListener("click", async () => {
  try {
    setStatus("Reading selection...");
    await readSelection();
    setStatus("Browser TTS is speaking the current selection.");
  } catch (error) {
    setStatus(error.message || "Read-aloud failed.");
  }
});

(async () => {
  appUrlInput.value = await getStoredAppUrl();
})();
