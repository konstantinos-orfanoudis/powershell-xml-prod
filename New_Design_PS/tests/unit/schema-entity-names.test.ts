import {
  fileNameToEntityHint,
  sanitizeEntityName,
  sanitizeSchemaEntityNames,
} from "@/lib/schemaEntityNames";

describe("schema entity name normalization", () => {
  it("removes trailing file-format suffixes from entity names", () => {
    expect(sanitizeEntityName("OktaUsersJson")).toBe("OktaUsers");
    expect(sanitizeEntityName("OktaUsers_XML")).toBe("OktaUsers");
    expect(sanitizeEntityName("Account.yaml")).toBe("Account");
  });

  it("preserves names that only mention format words in the middle", () => {
    expect(sanitizeEntityName("JsonWebhookEvent")).toBe("JsonWebhookEvent");
    expect(sanitizeEntityName("XmlPolicyRule")).toBe("XmlPolicyRule");
  });

  it("builds clean entity hints from filenames", () => {
    expect(fileNameToEntityHint("OktaUsers.json")).toBe("OktaUsers");
    expect(fileNameToEntityHint("partner-user_xml.xml")).toBe("partner-user");
    expect(fileNameToEntityHint("schema.wsdl")).toBe("schema");
  });

  it("sanitizes every entity name in a schema payload", () => {
    const schema = sanitizeSchemaEntityNames({
      name: "Connector",
      version: "1.0.0",
      entities: [{ name: "OktaUsersJson" }, { name: "RoleXml" }, { name: "AuditLog" }],
    });

    expect(schema.entities?.map((entity) => entity.name)).toEqual([
      "OktaUsers",
      "Role",
      "AuditLog",
    ]);
  });
});
