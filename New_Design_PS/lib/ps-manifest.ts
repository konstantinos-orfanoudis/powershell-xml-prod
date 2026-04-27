function findBalancedParentheses(text: string, openIdx: number): string | null {
  let depth = 0;
  let start = -1;
  let inSingle = false;
  let inDouble = false;

  for (let i = openIdx; i < text.length; i++) {
    const ch = text[i];

    if (!inDouble && ch === "'" && text[i - 1] !== "`") {
      inSingle = !inSingle;
      continue;
    }

    if (!inSingle && ch === '"' && text[i - 1] !== "`") {
      inDouble = !inDouble;
      continue;
    }

    if (inSingle || inDouble) continue;

    if (ch === "(") {
      if (depth === 0) start = i + 1;
      depth += 1;
      continue;
    }

    if (ch === ")") {
      depth -= 1;
      if (depth === 0 && start >= 0) {
        return text.slice(start, i);
      }
    }
  }

  return null;
}

function extractAssignmentBlock(text: string, propertyName: string) {
  const directArray = new RegExp(`${propertyName}\\s*=\\s*@\\(`, "i");
  const directArrayMatch = directArray.exec(text);

  if (directArrayMatch && directArrayMatch.index != null) {
    const openIdx = text.indexOf("(", directArrayMatch.index);
    if (openIdx >= 0) {
      return findBalancedParentheses(text, openIdx);
    }
  }

  const scalarMatch = new RegExp(
    `${propertyName}\\s*=\\s*(['"])([\\s\\S]*?)\\1`,
    "i"
  ).exec(text);

  return scalarMatch?.[2] ?? null;
}

function extractQuotedStrings(text: string) {
  return Array.from(text.matchAll(/(['"])(.*?)\1/g)).map((match) => match[2].trim());
}

export type ParsedPsManifest = {
  rootModule?: string;
  functionsToExport: string[];
  wildcardFunctionsToExport: boolean;
};

export function parsePsModuleManifest(text: string): ParsedPsManifest {
  const rootModuleMatch = /RootModule\s*=\s*(['"])(.*?)\1/i.exec(text);
  const rootModule = rootModuleMatch?.[2]?.trim() || undefined;

  const exportBlock = extractAssignmentBlock(text, "FunctionsToExport");
  if (!exportBlock) {
    return {
      rootModule,
      functionsToExport: [],
      wildcardFunctionsToExport: false,
    };
  }

  const quoted = extractQuotedStrings(exportBlock).filter(Boolean);
  const wildcardFunctionsToExport =
    quoted.some((value) => value === "*") || exportBlock.trim() === "*";

  return {
    rootModule,
    functionsToExport: quoted.filter((value) => value !== "*"),
    wildcardFunctionsToExport,
  };
}
