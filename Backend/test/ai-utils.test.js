const { cleanAiResponse, parseAiQuestion } = require("../all_imports");

// The AI is asked for strict JSON and routinely answers with something else
// anyway. cleanAiResponse/parseAiQuestion are the only thing standing between
// that chatter and a 500 on /api/v1/ai/question.

describe("cleanAiResponse", () => {
  test("returns bare JSON untouched", () => {
    const raw = '{"question":"Chi dei due cucina meglio?"}';

    expect(cleanAiResponse(raw)).toBe(raw);
  });

  test("strips a ```json code fence", () => {
    expect(cleanAiResponse('```json\n{"question":"Chi dei due?"}\n```')).toBe(
      '{"question":"Chi dei due?"}'
    );
  });

  test("strips a fence with no language tag", () => {
    expect(cleanAiResponse('```\n{"question":"Chi dei due?"}\n```')).toBe(
      '{"question":"Chi dei due?"}'
    );
  });

  test("drops a prose preamble and a trailing sign-off", () => {
    expect(
      cleanAiResponse(
        'Ecco la domanda che hai chiesto:\n{"question":"Chi dei due?"}\n\nSpero sia utile!'
      )
    ).toBe('{"question":"Chi dei due?"}');
  });

  test("trims surrounding whitespace", () => {
    expect(cleanAiResponse('  \n {"question":"Chi dei due?"} \n ')).toBe(
      '{"question":"Chi dei due?"}'
    );
  });

  test("keeps a brace character that belongs to the payload", () => {
    const raw = '{"question":"Chi sceglie {questo}?"}';

    expect(cleanAiResponse(raw)).toBe(raw);
  });

  // Without a complete pair there is nothing safe to slice out, so the text is
  // returned as-is and parseAiQuestion is left to fail loudly.
  test("returns text with no braces unchanged", () => {
    expect(cleanAiResponse("  Mi dispiace, non posso rispondere.  ")).toBe(
      "Mi dispiace, non posso rispondere."
    );
  });

  test("returns text with an unclosed object unchanged", () => {
    expect(cleanAiResponse('{"question":"Chi dei due?')).toBe('{"question":"Chi dei due?');
  });
});

describe("parseAiQuestion", () => {
  test("returns the trimmed question", () => {
    expect(parseAiQuestion('{"question":"  Chi dei due?  "}', 160)).toEqual({
      question: "Chi dei due?",
    });
  });

  test("truncates a question longer than the token budget", () => {
    const long = "a".repeat(1000);

    expect(parseAiQuestion(JSON.stringify({ question: long }), 10).question).toHaveLength(40);
  });

  test("does not truncate a question at exactly the token budget", () => {
    const question = "b".repeat(40);

    expect(parseAiQuestion(JSON.stringify({ question }), 10).question).toBe(question);
  });

  test("returns an empty question when the field is missing", () => {
    expect(parseAiQuestion('{"answer":"Chi dei due?"}', 160)).toEqual({ question: "" });
  });

  test("coerces a non-string question", () => {
    expect(parseAiQuestion('{"question":42}', 160)).toEqual({ question: "42" });
  });

  test("throws on text that is not JSON", () => {
    expect(() => parseAiQuestion("Mi dispiace, non posso rispondere.", 160)).toThrow();
  });
});
