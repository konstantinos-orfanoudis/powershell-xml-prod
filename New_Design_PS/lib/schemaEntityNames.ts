const FORMAT_SUFFIX_PATTERN = "json|xml|yaml|yml|csv|tsv|txt|text|pdf|wsdl|xsd";

export function sanitizeEntityName(name: string): string {
  let current = (name ?? "").trim();
  if (!current) return current;

  while (true) {
    const next = current
      .replace(new RegExp(`\\.(${FORMAT_SUFFIX_PATTERN})$`, "i"), "")
      .replace(new RegExp(`([_\\-\\s]+)(${FORMAT_SUFFIX_PATTERN})$`, "i"), "")
      .replace(
        /(Json|JSON|Xml|XML|Yaml|YAML|Yml|YML|Csv|CSV|Tsv|TSV|Txt|TXT|Text|TEXT|Pdf|PDF|Wsdl|WSDL|Xsd|XSD)$/,
        ""
      )
      .trim();

    if (!next || next === current) return current;
    current = next;
  }
}

export function fileNameToEntityHint(fileName: string): string {
  const trimmed = (fileName ?? "").trim();
  if (!trimmed) return "Entity";
  const withoutPath = trimmed.split(/[\\/]/).pop() ?? trimmed;
  return sanitizeEntityName(withoutPath) || "Entity";
}

type SchemaLikeEntity = { name?: string };
type SchemaLike = { entities?: SchemaLikeEntity[] };

export function sanitizeSchemaEntityNames<T extends SchemaLike>(schema: T): T {
  if (!schema || !Array.isArray(schema.entities)) return schema;

  return {
    ...schema,
    entities: schema.entities.map((entity) => ({
      ...entity,
      name: sanitizeEntityName(String(entity?.name ?? "")),
    })),
  };
}
