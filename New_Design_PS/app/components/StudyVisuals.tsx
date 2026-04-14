"use client";

import React, { useMemo, useState } from "react";

import { DiagramSpec } from "@/lib/sscp/types";

type MindmapBranch = {
  title: string;
  items: string[];
};

export function StudyMindmap({
  title,
  branches,
}: {
  title: string;
  branches: MindmapBranch[];
}) {
  const [activeBranch, setActiveBranch] = useState(branches[0]?.title ?? "");
  const current = useMemo(
    () => branches.find((branch) => branch.title === activeBranch) ?? branches[0],
    [activeBranch, branches],
  );

  return (
    <div className="rounded-[24px] border border-stone-900/10 bg-[radial-gradient(circle_at_top,rgba(245,229,202,0.55),transparent_45%),linear-gradient(180deg,#fffdf9_0%,#f7f1e8_100%)] p-5">
      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Mindmap</div>
      <div className="mt-4 grid gap-4 xl:grid-cols-[220px_minmax(0,1fr)] xl:items-start">
        <div className="flex min-h-[180px] items-center justify-center rounded-[28px] border border-stone-900/10 bg-stone-900 px-5 py-6 text-center text-lg font-semibold text-stone-50 shadow-[0_12px_28px_rgba(28,21,16,0.18)]">
          {title}
        </div>
        <div className="space-y-4">
          <div className="grid gap-3 md:grid-cols-2">
            {branches.map((branch) => (
              <button
                key={branch.title}
                type="button"
                onClick={() => setActiveBranch(branch.title)}
                className={`rounded-[22px] border p-4 text-left transition ${
                  branch.title === current?.title
                    ? "border-stone-900 bg-stone-900 text-stone-50"
                    : "border-stone-900/10 bg-white/85 text-stone-900 hover:border-stone-900/20"
                }`}
              >
                <div className="text-sm font-semibold">{branch.title}</div>
                <div className={`mt-2 text-xs leading-5 ${branch.title === current?.title ? "text-stone-300" : "text-stone-500"}`}>
                  {branch.items[0] ?? "Open this branch to review the linked memory cues."}
                </div>
              </button>
            ))}
          </div>
          {current ? (
            <div className="rounded-[24px] border border-stone-900/10 bg-white/90 p-5">
              <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Active branch</div>
              <h4 className="mt-2 text-lg font-semibold text-stone-900">{current.title}</h4>
              <ul className="mt-4 space-y-2 text-sm leading-6 text-stone-600">
                {current.items.map((item) => (
                  <li key={item}>• {item}</li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

export function StudyFlowDiagram({
  title,
  steps,
}: {
  title: string;
  steps: string[];
}) {
  const [activeStep, setActiveStep] = useState(0);
  return (
    <div className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Diagram</div>
      <div className="mt-2 text-sm font-semibold text-stone-900">{title}</div>
      <div className="mt-3 rounded-[18px] bg-stone-50 px-4 py-3 text-sm text-stone-700">
        <span className="font-semibold text-stone-900">Focus:</span> {steps[activeStep]}
      </div>
      <div className="mt-4 grid gap-3 lg:grid-cols-[repeat(5,minmax(0,1fr))]">
        {steps.map((step, index) => (
          <button
            key={`${title}-${step}`}
            type="button"
            onClick={() => setActiveStep(index)}
            className="relative text-left"
          >
            <div
              className={`rounded-[20px] border px-4 py-4 text-sm leading-6 transition ${
                index === activeStep
                  ? "border-stone-900 bg-stone-900 text-stone-50"
                  : "border-stone-900/10 bg-stone-50 text-stone-700 hover:border-stone-900/20"
              }`}
            >
              <div className="text-[11px] uppercase tracking-[0.18em] text-stone-500">
                Step {index + 1}
              </div>
              <div className={`mt-2 font-medium ${index === activeStep ? "text-stone-50" : "text-stone-900"}`}>{step}</div>
            </div>
            {index < steps.length - 1 ? (
              <div className="hidden lg:flex absolute right-[-18px] top-1/2 h-[2px] w-9 -translate-y-1/2 items-center justify-center bg-stone-300">
                <span className="absolute right-[-2px] h-2 w-2 rotate-45 border-r-2 border-t-2 border-stone-400" />
              </div>
            ) : null}
          </button>
        ))}
      </div>
    </div>
  );
}

export function StudyDiagramExplorer({
  spec,
}: {
  spec: DiagramSpec;
}) {
  const [activeNodeId, setActiveNodeId] = useState(spec.nodes[0]?.id ?? "");
  const activeNode = spec.nodes.find((node) => node.id === activeNodeId) ?? spec.nodes[0];

  return (
    <div className="rounded-[24px] border border-stone-900/10 bg-[linear-gradient(180deg,rgba(255,255,255,0.96),rgba(248,244,237,0.96))] p-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Interactive diagram</div>
          <h4 className="mt-2 text-lg font-semibold text-stone-900">{spec.title}</h4>
        </div>
        <div className="rounded-full border border-stone-900/10 bg-white px-3 py-1 text-xs font-semibold text-stone-600">
          {spec.type}
        </div>
      </div>
      <p className="mt-3 text-sm leading-6 text-stone-600">{spec.summary}</p>
      <div className="mt-4 rounded-[18px] bg-stone-900 px-4 py-3 text-sm text-stone-50">
        <span className="font-semibold">How to use it:</span> {spec.focusPrompt}
      </div>
      <div className="mt-5 grid gap-5 xl:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)]">
        <div className="rounded-[24px] border border-stone-900/10 bg-stone-50/70 p-5">
          <svg viewBox="0 0 760 320" className="h-[320px] w-full">
            {spec.edges.map((edge, index) => {
              const fromIndex = spec.nodes.findIndex((node) => node.id === edge.from);
              const toIndex = spec.nodes.findIndex((node) => node.id === edge.to);
              const startX = 80 + (fromIndex % 3) * 220;
              const startY = 60 + Math.floor(fromIndex / 3) * 140;
              const endX = 80 + (toIndex % 3) * 220;
              const endY = 60 + Math.floor(toIndex / 3) * 140;
              return (
                <g key={`${edge.from}-${edge.to}-${index}`}>
                  <line
                    x1={startX}
                    y1={startY}
                    x2={endX}
                    y2={endY}
                    stroke="rgba(69,58,48,0.28)"
                    strokeWidth="2"
                  />
                  <text
                    x={(startX + endX) / 2}
                    y={(startY + endY) / 2 - 6}
                    textAnchor="middle"
                    fill="rgb(87,83,78)"
                    fontSize="11"
                  >
                    {edge.label}
                  </text>
                </g>
              );
            })}
            {spec.nodes.map((node, index) => {
              const x = 20 + (index % 3) * 220;
              const y = 20 + Math.floor(index / 3) * 140;
              const active = node.id === activeNode?.id;
              return (
                <g
                  key={node.id}
                  onClick={() => setActiveNodeId(node.id)}
                  style={{ cursor: "pointer" }}
                >
                  <rect
                    x={x}
                    y={y}
                    rx="24"
                    ry="24"
                    width="140"
                    height="78"
                    fill={active ? "rgb(28,25,23)" : "rgb(255,255,255)"}
                    stroke={active ? "rgb(28,25,23)" : "rgba(28,25,23,0.12)"}
                    strokeWidth="2"
                  />
                  <text
                    x={x + 70}
                    y={y + 32}
                    textAnchor="middle"
                    fill={active ? "rgb(250,250,249)" : "rgb(28,25,23)"}
                    fontSize="13"
                    fontWeight="700"
                  >
                    {node.label}
                  </text>
                  <text
                    x={x + 70}
                    y={y + 52}
                    textAnchor="middle"
                    fill={active ? "rgba(250,250,249,0.75)" : "rgb(120,113,108)"}
                    fontSize="11"
                  >
                    {node.group}
                  </text>
                </g>
              );
            })}
          </svg>
        </div>
        {activeNode ? (
          <div className="rounded-[24px] border border-stone-900/10 bg-white/90 p-5">
            <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Selected node</div>
            <h5 className="mt-2 text-lg font-semibold text-stone-900">{activeNode.label}</h5>
            <div className="mt-2 rounded-full border border-stone-900/10 px-3 py-1 text-xs font-semibold text-stone-600 w-fit">
              {activeNode.group}
            </div>
            <p className="mt-4 text-sm leading-7 text-stone-600">{activeNode.detail}</p>
            <div className="mt-4 text-sm text-stone-500">
              Click the other nodes to see how the lesson moves from tactical action into broader reasoning.
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}
