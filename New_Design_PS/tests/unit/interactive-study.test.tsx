// @vitest-environment jsdom

import React from "react";
import { fireEvent, render, screen } from "@testing-library/react";

import { CheckpointLab, FlashcardDeck } from "@/app/components/InteractiveStudy";

describe("interactive study components", () => {
  it("reveals flashcard answers", () => {
    render(
      <FlashcardDeck
        cards={[
          {
            id: "card-1",
            front: "What is least privilege?",
            back: "Grant only the access required for the job.",
            hint: "Think access scope.",
          },
        ]}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: /reveal answer/i }));
    expect(screen.getByText(/grant only the access required/i)).toBeInTheDocument();
  });

  it("shows remediation when a checkpoint answer is wrong", () => {
    const onMiss = vi.fn();
    render(
      <CheckpointLab
        checkpoints={[
          {
            id: "check-1",
            format: "single_select",
            prompt: "Which answer is best?",
            options: [
              { id: "a", label: "A", text: "Correct" },
              { id: "b", label: "B", text: "Wrong" },
            ],
            correctOptionIds: ["a"],
            expectedAnswer: "A is correct because it aligns with the control objective.",
            remediation: "Return to the worked example before moving on.",
            coachingTip: "Name the control action first.",
            objectiveId: "obj-1",
          },
        ]}
        onMiss={onMiss}
      />,
    );

    fireEvent.click(screen.getByLabelText(/b\. wrong/i));
    fireEvent.click(screen.getByRole("button", { name: /check answer/i }));

    expect(onMiss).toHaveBeenCalledWith("Return to the worked example before moving on.");
    expect(screen.getByText(/return to the worked example/i)).toBeInTheDocument();
  });
});
