"use client";

import React, { useEffect, useRef, useState } from "react";

import { NarrationRequest } from "@/lib/sscp/types";

export default function SscpReaderControls({
  text,
  label,
}: {
  text: string;
  label: string;
}) {
  const [busy, setBusy] = useState<"idle" | "browser" | "ai">("idle");
  const [error, setError] = useState<string>("");
  const [disclosure, setDisclosure] = useState<string>("");
  const audioRef = useRef<HTMLAudioElement | null>(null);

  useEffect(() => {
    return () => {
      window.speechSynthesis?.cancel();
      audioRef.current?.pause();
    };
  }, []);

  async function readBrowser() {
    setError("");
    setDisclosure("");
    setBusy("browser");
    try {
      window.speechSynthesis.cancel();
      const utterance = new SpeechSynthesisUtterance(text);
      utterance.rate = 1;
      utterance.onend = () => setBusy("idle");
      utterance.onerror = () => {
        setBusy("idle");
        setError("Browser read-aloud was interrupted.");
      };
      window.speechSynthesis.speak(utterance);
    } catch (nextError: any) {
      setBusy("idle");
      setError(nextError?.message ?? "Browser read-aloud is unavailable.");
    }
  }

  async function readAi() {
    setError("");
    setBusy("ai");
    try {
      const payload: NarrationRequest = {
        text: text.slice(0, 3900),
        voice: "cedar",
        instructions:
          "Speak clearly and steadily for technical study review. Use calm pacing and emphasize important security terms.",
      };
      const response = await fetch("/api/sscp/narrate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const json = await response.json();
      if (!response.ok) {
        throw new Error(json.error || "AI narration failed.");
      }
      setDisclosure(json.disclosure || "");
      const audio = new Audio(`data:${json.mimeType};base64,${json.data}`);
      audioRef.current = audio;
      audio.onended = () => setBusy("idle");
      audio.onerror = () => {
        setBusy("idle");
        setError("The AI narration audio could not be played.");
      };
      await audio.play();
    } catch (nextError: any) {
      setBusy("idle");
      setError(nextError?.message ?? "AI narration failed.");
    }
  }

  function stopAll() {
    window.speechSynthesis.cancel();
    audioRef.current?.pause();
    audioRef.current = null;
    setBusy("idle");
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <button
        type="button"
        onClick={readBrowser}
        className="rounded-full border border-amber-900/15 bg-white/80 px-3 py-1.5 text-xs font-semibold text-stone-900 transition hover:border-amber-700/30 hover:bg-white"
      >
        Read {label}
      </button>
      <button
        type="button"
        onClick={readAi}
        className="rounded-full border border-stone-900 bg-stone-900 px-3 py-1.5 text-xs font-semibold text-stone-50 transition hover:bg-stone-800"
      >
        AI Voice
      </button>
      <button
        type="button"
        onClick={stopAll}
        className="rounded-full border border-stone-300 bg-stone-100 px-3 py-1.5 text-xs font-semibold text-stone-700 transition hover:bg-stone-200"
      >
        Stop
      </button>
      {busy !== "idle" ? (
        <span className="text-xs text-stone-500">
          {busy === "browser" ? "Browser read-aloud active" : "Generating AI audio"}
        </span>
      ) : null}
      {disclosure ? <span className="text-xs text-stone-500">{disclosure}</span> : null}
      {error ? <span className="text-xs text-rose-700">{error}</span> : null}
    </div>
  );
}
