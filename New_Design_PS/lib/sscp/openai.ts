import OpenAI from "openai";

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const OPENAI_BASE_URL = process.env.OPENAI_BASE_URL;
const OPENAI_MODEL = process.env.OPENAI_MODEL || "gpt-5.4";

let cachedClient: OpenAI | null = null;

export function hasOpenAIConfig(): boolean {
  return Boolean(OPENAI_API_KEY);
}

export function getOpenAIClient(): OpenAI {
  if (!OPENAI_API_KEY) {
    throw new Error("OPENAI_API_KEY is not configured on the server.");
  }
  if (!cachedClient) {
    cachedClient = new OpenAI({
      apiKey: OPENAI_API_KEY,
      ...(OPENAI_BASE_URL ? { baseURL: OPENAI_BASE_URL } : {}),
    });
  }
  return cachedClient;
}

export function getOpenAIModel(): string {
  return OPENAI_MODEL;
}

export async function createStructuredResponse<T>({
  name,
  description,
  schema,
  instructions,
  input,
  tools,
  include,
  timeoutMs = Number(process.env.OPENAI_TIMEOUT_MS || 15_000),
}: {
  name: string;
  description: string;
  schema: { [key: string]: unknown };
  instructions: string;
  input: string;
  tools?: Array<Record<string, unknown>>;
  include?: string[];
  timeoutMs?: number;
}): Promise<T> {
  const client = getOpenAIClient();
  const response = await new Promise<any>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`Structured response ${name} timed out after ${timeoutMs}ms.`));
    }, timeoutMs);

    client.responses
      .create({
        model: getOpenAIModel(),
        instructions,
        input,
        tools,
        include: include as any,
        text: {
          format: {
            type: "json_schema",
            name,
            description,
            schema,
            strict: true,
          },
        },
      } as any)
      .then((result) => {
        clearTimeout(timer);
        resolve(result);
      })
      .catch((error) => {
        clearTimeout(timer);
        reject(error);
      });
  });

  const payload = response.output_text?.trim();
  if (!payload) {
    throw new Error(`Structured response ${name} returned no JSON output.`);
  }
  return JSON.parse(payload) as T;
}
