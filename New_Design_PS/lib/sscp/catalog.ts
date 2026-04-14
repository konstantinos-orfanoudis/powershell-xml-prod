import {
  CisspDomain,
  CisspDomainId,
  LearningResource,
  SscpDomain,
  SscpDomainId,
  SourceCitation,
} from "@/lib/sscp/types";

const SSCP_OUTLINE_URL =
  "https://www.isc2.org/certifications/sscp/sscp-certification-exam-outline";
const CISSP_OUTLINE_URL =
  "https://www.isc2.org/certifications/cissp/cissp-certification-exam-outline";

function officialCitation(
  id: string,
  sourceName: string,
  label: string,
  url: string,
  note?: string,
): SourceCitation {
  return {
    id,
    label,
    sourceName,
    trustLevel: "official",
    url,
    note,
    accessedAt: new Date().toISOString(),
  };
}

export const SOURCE_POLICY: Record<string, string> = {
  official: "Canonical exam/domain structure used to anchor lessons, drills, and answer review.",
  trusted_live:
    "Trusted external study guides and references used to deepen explanations and reading paths.",
  user_notes:
    "Local PDF study corpus from your selected folder. Used as a supplemental reinforcement layer, not a replacement for the official or trusted sources.",
};

export const SSCP_DOMAINS: SscpDomain[] = [
  {
    id: "security-concepts-practices",
    title: "Security Concepts and Practices",
    weight: 16,
    summary:
      "Focus on core security principles, controls, governance participation, physical security, and the operational practices that make policy real.",
    officialCitation: officialCitation(
      "official-sscp-outline-domain-1",
      "ISC2",
      "SSCP Exam Outline",
      SSCP_OUTLINE_URL,
      "Official outline is the canonical SSCP source.",
    ),
    glossary: [
      "CIA triad",
      "accountability",
      "least privilege",
      "segregation of duties",
      "administrative control",
      "technical control",
      "physical control",
      "change management",
    ],
    objectives: [
      {
        id: "sscp-1-ethics",
        domainId: "security-concepts-practices",
        title: "Comply with codes of ethics and professional responsibility",
        summary:
          "Apply ISC2 and organizational ethics in day-to-day operational security decisions.",
        keywords: ["ethics", "professional conduct", "organizational code"],
        cisspBridgeTopics: ["security-risk-management"],
      },
      {
        id: "sscp-1-concepts",
        domainId: "security-concepts-practices",
        title: "Understand core security concepts",
        summary:
          "Use confidentiality, integrity, availability, accountability, non-repudiation, least privilege, and separation of duties correctly.",
        keywords: ["cia", "non-repudiation", "least privilege", "sod"],
        cisspBridgeTopics: ["security-risk-management", "asset-security"],
      },
      {
        id: "sscp-1-controls",
        domainId: "security-concepts-practices",
        title: "Identify and maintain security controls and compliance activities",
        summary:
          "Match technical, administrative, and physical controls to operational needs and compliance expectations.",
        keywords: ["controls", "compliance", "baselines", "standards"],
        cisspBridgeTopics: ["security-assessment-testing", "security-operations"],
      },
      {
        id: "sscp-1-operations",
        domainId: "security-concepts-practices",
        title: "Participate in asset, change, awareness, and physical security operations",
        summary:
          "Support secure operational hygiene across assets, changes, awareness efforts, and physical environments.",
        keywords: ["asset management", "change control", "awareness", "physical security"],
        cisspBridgeTopics: ["security-operations", "asset-security"],
      },
    ],
  },
  {
    id: "access-controls",
    title: "Access Controls",
    weight: 15,
    summary:
      "Cover access control concepts, authentication methods, identity lifecycle work, and operational administration of access models.",
    officialCitation: officialCitation(
      "official-sscp-outline-domain-2",
      "ISC2",
      "SSCP Exam Outline",
      SSCP_OUTLINE_URL,
    ),
    glossary: [
      "authentication",
      "authorization",
      "accounting",
      "RBAC",
      "ABAC",
      "PAM",
      "proofing",
      "provisioning",
    ],
    objectives: [
      {
        id: "sscp-2-concepts",
        domainId: "access-controls",
        title: "Understand access control concepts",
        summary:
          "Choose control approaches that align users, subjects, objects, and business need.",
        keywords: ["access control", "subjects", "objects", "permissions"],
        cisspBridgeTopics: ["identity-access-management", "security-risk-management"],
      },
      {
        id: "sscp-2-authentication",
        domainId: "access-controls",
        title: "Implement and maintain authentication methods",
        summary:
          "Support passwords, MFA, certificates, federation, and operational authentication hardening.",
        keywords: ["mfa", "federation", "passwords", "authentication"],
        cisspBridgeTopics: ["identity-access-management", "security-architecture-engineering"],
      },
      {
        id: "sscp-2-lifecycle",
        domainId: "access-controls",
        title: "Support the identity management lifecycle",
        summary:
          "Handle proofing, provisioning, entitlement changes, deprovisioning, reporting, and monitoring.",
        keywords: ["identity lifecycle", "joiner mover leaver", "entitlements", "provisioning"],
        cisspBridgeTopics: ["identity-access-management", "security-operations"],
      },
      {
        id: "sscp-2-models",
        domainId: "access-controls",
        title: "Understand and administer access control models",
        summary:
          "Apply mandatory, discretionary, role-based, rule-based, and attribute-based access concepts appropriately.",
        keywords: ["dac", "mac", "rbac", "abac", "rule-based"],
        cisspBridgeTopics: ["identity-access-management", "security-architecture-engineering"],
      },
    ],
  },
  {
    id: "risk-identification-monitoring-analysis",
    title: "Risk Identification, Monitoring and Analysis",
    weight: 15,
    summary:
      "Address risk management, legal and regulatory concerns, security assessment work, and operating monitoring systems effectively.",
    officialCitation: officialCitation(
      "official-sscp-outline-domain-3",
      "ISC2",
      "SSCP Exam Outline",
      SSCP_OUTLINE_URL,
    ),
    glossary: [
      "risk register",
      "threat modeling",
      "cvss",
      "ioc",
      "risk appetite",
      "risk treatment",
      "vulnerability assessment",
      "monitoring",
    ],
    objectives: [
      {
        id: "sscp-3-risk",
        domainId: "risk-identification-monitoring-analysis",
        title: "Understand risk management and treatment",
        summary:
          "Use risk visibility, frameworks, tolerance, and treatment options to guide practical decisions.",
        keywords: ["risk treatment", "risk appetite", "frameworks", "threat modeling"],
        cisspBridgeTopics: ["security-risk-management", "security-assessment-testing"],
      },
      {
        id: "sscp-3-legal",
        domainId: "risk-identification-monitoring-analysis",
        title: "Understand legal and regulatory concerns",
        summary:
          "Recognize privacy, jurisdiction, contractual, and regulatory constraints affecting security operations.",
        keywords: ["privacy", "jurisdiction", "regulation", "legal"],
        cisspBridgeTopics: ["security-risk-management", "asset-security"],
      },
      {
        id: "sscp-3-assessment",
        domainId: "risk-identification-monitoring-analysis",
        title: "Perform security assessment activities",
        summary:
          "Support vulnerability management, scanning, testing, and evidence-driven assessment work.",
        keywords: ["vulnerability management", "assessment", "scanning", "testing"],
        cisspBridgeTopics: ["security-assessment-testing", "security-operations"],
      },
      {
        id: "sscp-3-monitoring",
        domainId: "risk-identification-monitoring-analysis",
        title: "Operate and analyze monitoring systems",
        summary:
          "Collect, maintain, and interpret monitoring data to detect meaningful security signals.",
        keywords: ["siem", "monitoring", "analysis", "telemetry", "logging"],
        cisspBridgeTopics: ["security-operations", "security-assessment-testing"],
      },
    ],
  },
  {
    id: "incident-response-recovery",
    title: "Incident Response and Recovery",
    weight: 14,
    summary:
      "Focus on incident preparation, detection, containment, eradication, recovery, and resilience planning.",
    officialCitation: officialCitation(
      "official-sscp-outline-domain-4",
      "ISC2",
      "SSCP Exam Outline",
      SSCP_OUTLINE_URL,
    ),
    glossary: [
      "incident response plan",
      "containment",
      "eradication",
      "recovery",
      "lessons learned",
      "forensics",
      "backup",
      "bcp",
      "drp",
    ],
    objectives: [
      {
        id: "sscp-4-program",
        domainId: "incident-response-recovery",
        title: "Build and support incident response capability",
        summary:
          "Define roles, scope, communication paths, and priorities before an incident occurs.",
        keywords: ["incident program", "playbook", "communications", "scope"],
        cisspBridgeTopics: ["security-operations", "security-risk-management"],
      },
      {
        id: "sscp-4-response",
        domainId: "incident-response-recovery",
        title: "Perform detection, analysis, containment, eradication, and recovery",
        summary:
          "Handle incidents through the core operational lifecycle with evidence and coordination.",
        keywords: ["detection", "analysis", "containment", "eradication", "recovery"],
        cisspBridgeTopics: ["security-operations", "security-assessment-testing"],
      },
      {
        id: "sscp-4-resilience",
        domainId: "incident-response-recovery",
        title: "Apply backup, recovery, continuity, and disaster recovery concepts",
        summary:
          "Use resilience planning to restore critical services and reduce business impact.",
        keywords: ["backup", "restore", "rto", "rpo", "disaster recovery"],
        cisspBridgeTopics: ["security-operations", "security-risk-management"],
      },
      {
        id: "sscp-4-lessons",
        domainId: "incident-response-recovery",
        title: "Capture lessons learned and improve controls",
        summary:
          "Translate incidents into operational improvements, reporting, and stronger preventive controls.",
        keywords: ["lessons learned", "post-incident", "improvement", "metrics"],
        cisspBridgeTopics: ["security-operations", "security-risk-management"],
      },
    ],
  },
  {
    id: "cryptography",
    title: "Cryptography",
    weight: 9,
    summary:
      "Cover encryption foundations, algorithm selection, key management, PKI, and secure application of cryptography.",
    officialCitation: officialCitation(
      "official-sscp-outline-domain-5",
      "ISC2",
      "SSCP Exam Outline",
      SSCP_OUTLINE_URL,
    ),
    glossary: [
      "plaintext",
      "ciphertext",
      "symmetric",
      "asymmetric",
      "hashing",
      "digital signature",
      "pki",
      "key management",
    ],
    objectives: [
      {
        id: "sscp-5-foundations",
        domainId: "cryptography",
        title: "Understand cryptographic concepts and goals",
        summary:
          "Apply encryption, hashing, signatures, and non-repudiation correctly in security contexts.",
        keywords: ["encryption", "hashing", "signatures", "non-repudiation"],
        cisspBridgeTopics: ["security-architecture-engineering", "communication-network-security"],
      },
      {
        id: "sscp-5-algorithms",
        domainId: "cryptography",
        title: "Differentiate common algorithms, protocols, and use cases",
        summary:
          "Choose the right primitive or protocol for confidentiality, integrity, transport, and identity assurance.",
        keywords: ["aes", "rsa", "tls", "ipsec", "protocols"],
        cisspBridgeTopics: ["security-architecture-engineering", "communication-network-security"],
      },
      {
        id: "sscp-5-keys",
        domainId: "cryptography",
        title: "Support key management and PKI operations",
        summary:
          "Manage certificates, trust, storage, rotation, lifecycle, and revocation concerns.",
        keywords: ["pki", "certificates", "rotation", "revocation", "trust"],
        cisspBridgeTopics: ["identity-access-management", "security-architecture-engineering"],
      },
      {
        id: "sscp-5-data-protection",
        domainId: "cryptography",
        title: "Protect data in transit, at rest, and in use",
        summary:
          "Map cryptographic controls to where data lives and how it moves through systems.",
        keywords: ["data at rest", "data in transit", "key storage", "tokenization"],
        cisspBridgeTopics: ["asset-security", "security-architecture-engineering"],
      },
    ],
  },
  {
    id: "network-communications-security",
    title: "Network and Communications Security",
    weight: 16,
    summary:
      "Focus on network fundamentals, secure design, segmentation, transport protections, wireless, and monitoring.",
    officialCitation: officialCitation(
      "official-sscp-outline-domain-6",
      "ISC2",
      "SSCP Exam Outline",
      SSCP_OUTLINE_URL,
    ),
    glossary: [
      "tcp/ip",
      "segmentation",
      "firewall",
      "ids",
      "ips",
      "vpn",
      "zero trust",
      "wireless security",
    ],
    objectives: [
      {
        id: "sscp-6-fundamentals",
        domainId: "network-communications-security",
        title: "Understand network architecture and protocols",
        summary:
          "Use TCP/IP, ports, protocols, routing, and transport behavior when reasoning about secure operations.",
        keywords: ["tcp/ip", "ports", "protocols", "routing", "udp"],
        cisspBridgeTopics: ["communication-network-security", "security-architecture-engineering"],
      },
      {
        id: "sscp-6-design",
        domainId: "network-communications-security",
        title: "Apply secure network design and segmentation",
        summary:
          "Use boundaries, segmentation, isolation, and trust reduction to limit blast radius.",
        keywords: ["segmentation", "trust boundaries", "dmz", "microsegmentation"],
        cisspBridgeTopics: ["communication-network-security", "security-architecture-engineering"],
      },
      {
        id: "sscp-6-defense",
        domainId: "network-communications-security",
        title: "Operate network defense and monitoring controls",
        summary:
          "Support firewalls, IDS/IPS, proxies, VPNs, telemetry, and secure remote access.",
        keywords: ["firewall", "ids", "ips", "proxy", "vpn", "remote access"],
        cisspBridgeTopics: ["communication-network-security", "security-operations"],
      },
      {
        id: "sscp-6-modern",
        domainId: "network-communications-security",
        title: "Protect wireless, cloud, and hybrid communication paths",
        summary:
          "Apply secure communication principles across modern and mixed infrastructure environments.",
        keywords: ["wireless", "cloud", "hybrid", "zero trust", "sase"],
        cisspBridgeTopics: ["communication-network-security", "security-operations"],
      },
    ],
  },
  {
    id: "systems-application-security",
    title: "Systems and Application Security",
    weight: 15,
    summary:
      "Address secure system and software lifecycle concerns, endpoint hardening, application risk, and operational protection.",
    officialCitation: officialCitation(
      "official-sscp-outline-domain-7",
      "ISC2",
      "SSCP Exam Outline",
      SSCP_OUTLINE_URL,
    ),
    glossary: [
      "secure baseline",
      "hardening",
      "secure sdlc",
      "patching",
      "malware defense",
      "endpoint security",
      "vulnerability remediation",
    ],
    objectives: [
      {
        id: "sscp-7-lifecycle",
        domainId: "systems-application-security",
        title: "Support secure system lifecycle activities",
        summary:
          "Apply secure baseline, hardening, configuration, and maintenance practices to operational systems.",
        keywords: ["hardening", "configuration management", "baseline", "maintenance"],
        cisspBridgeTopics: ["security-architecture-engineering", "security-operations"],
      },
      {
        id: "sscp-7-applications",
        domainId: "systems-application-security",
        title: "Understand application security and secure development concerns",
        summary:
          "Recognize common software risks and support secure development and deployment decisions.",
        keywords: ["secure sdlc", "application security", "code review", "owasp"],
        cisspBridgeTopics: ["software-development-security", "security-assessment-testing"],
      },
      {
        id: "sscp-7-vuln-remediation",
        domainId: "systems-application-security",
        title: "Handle vulnerability, patching, and remediation operations",
        summary:
          "Coordinate remediation with operational constraints and business risk in mind.",
        keywords: ["patching", "remediation", "vulnerabilities", "exceptions"],
        cisspBridgeTopics: ["security-operations", "security-assessment-testing"],
      },
      {
        id: "sscp-7-platforms",
        domainId: "systems-application-security",
        title: "Protect endpoints, mobile, and cloud-hosted workloads",
        summary:
          "Extend system and application security expectations across modern platform types.",
        keywords: ["endpoint", "mobile", "cloud workload", "edr", "malware"],
        cisspBridgeTopics: ["security-operations", "software-development-security"],
      },
    ],
  },
];

export const CISSP_DOMAINS: CisspDomain[] = [
  {
    id: "security-risk-management",
    title: "Security and Risk Management",
    weight: 16,
    summary:
      "Bring governance, policy, risk, compliance, professional ethics, and business alignment into every security decision.",
    officialCitation: officialCitation(
      "official-cissp-outline-domain-1",
      "ISC2",
      "CISSP Exam Outline",
      CISSP_OUTLINE_URL,
    ),
  },
  {
    id: "asset-security",
    title: "Asset Security",
    weight: 10,
    summary:
      "Focus on classification, ownership, handling, retention, and protection of information assets across their lifecycle.",
    officialCitation: officialCitation(
      "official-cissp-outline-domain-2",
      "ISC2",
      "CISSP Exam Outline",
      CISSP_OUTLINE_URL,
    ),
  },
  {
    id: "security-architecture-engineering",
    title: "Security Architecture and Engineering",
    weight: 13,
    summary:
      "Expand operational knowledge into architecture, trust, resilience, secure design, and control selection at system scale.",
    officialCitation: officialCitation(
      "official-cissp-outline-domain-3",
      "ISC2",
      "CISSP Exam Outline",
      CISSP_OUTLINE_URL,
    ),
  },
  {
    id: "communication-network-security",
    title: "Communication and Network Security",
    weight: 13,
    summary:
      "Frame network security decisions around architecture, protected communications, and enterprise design tradeoffs.",
    officialCitation: officialCitation(
      "official-cissp-outline-domain-4",
      "ISC2",
      "CISSP Exam Outline",
      CISSP_OUTLINE_URL,
    ),
  },
  {
    id: "identity-access-management",
    title: "Identity and Access Management (IAM)",
    weight: 13,
    summary:
      "Scale operational IAM into enterprise identity strategy, trust management, and governance-aware access decisions.",
    officialCitation: officialCitation(
      "official-cissp-outline-domain-5",
      "ISC2",
      "CISSP Exam Outline",
      CISSP_OUTLINE_URL,
    ),
  },
  {
    id: "security-assessment-testing",
    title: "Security Assessment and Testing",
    weight: 12,
    summary:
      "Move from running controls to validating them, measuring them, and proving their effectiveness over time.",
    officialCitation: officialCitation(
      "official-cissp-outline-domain-6",
      "ISC2",
      "CISSP Exam Outline",
      CISSP_OUTLINE_URL,
    ),
  },
  {
    id: "security-operations",
    title: "Security Operations",
    weight: 13,
    summary:
      "Treat operations as resilient business capability, not only as tactical incident handling or tool administration.",
    officialCitation: officialCitation(
      "official-cissp-outline-domain-7",
      "ISC2",
      "CISSP Exam Outline",
      CISSP_OUTLINE_URL,
    ),
  },
  {
    id: "software-development-security",
    title: "Software Development Security",
    weight: 10,
    summary:
      "Think beyond secure coding into development governance, lifecycle assurance, and architecture-aware software risk decisions.",
    officialCitation: officialCitation(
      "official-cissp-outline-domain-8",
      "ISC2",
      "CISSP Exam Outline",
      CISSP_OUTLINE_URL,
    ),
  },
];

export const TRUSTED_RESOURCE_HOSTS = [
  "www.isc2.org",
  "isc2.org",
  "www.nist.gov",
  "csrc.nist.gov",
  "www.cisa.gov",
  "cisa.gov",
  "owasp.org",
  "learn.microsoft.com",
  "www.microsoft.com",
  "aws.amazon.com",
  "docs.aws.amazon.com",
  "cloud.google.com",
  "developers.google.com",
  "www.youtube.com",
  "youtube.com",
  "youtu.be",
];

export const CURATED_RESOURCES: LearningResource[] = [
  {
    id: "nist-csf-2",
    title: "NIST Cybersecurity Framework 2.0",
    url: "https://www.nist.gov/cyberframework",
    format: "guide",
    sourceName: "NIST",
    sourceType: "trusted_live",
    publishedAt: "2024-02-26",
    domainIds: [
      "security-concepts-practices",
      "risk-identification-monitoring-analysis",
    ],
    difficulty: "foundation",
    timeToConsume: "45-90 min",
    sscpFit: "Strong for control thinking, risk structure, and communication.",
    cisspBridgeValue:
      "Excellent bridge into governance, enterprise risk, and control framing.",
    summary:
      "A modern security framework that helps connect operational controls to business-level risk and governance.",
    whyItMatters:
      "Builds the habit of explaining controls in terms leaders and auditors understand.",
    citations: [
      {
        id: "resource-csf-2",
        label: "NIST Cybersecurity Framework 2.0",
        sourceName: "NIST",
        trustLevel: "trusted_live",
        url: "https://www.nist.gov/cyberframework",
        publishedAt: "2024-02-26",
      },
    ],
  },
  {
    id: "nist-incident-response",
    title: "NIST SP 800-61 Rev. 2 Computer Security Incident Handling Guide",
    url: "https://csrc.nist.gov/pubs/sp/800/61/r2/final",
    format: "guide",
    sourceName: "NIST",
    sourceType: "trusted_live",
    domainIds: [
      "incident-response-recovery",
      "risk-identification-monitoring-analysis",
    ],
    difficulty: "intermediate",
    timeToConsume: "90-120 min",
    sscpFit: "High-value for incident process thinking and operations.",
    cisspBridgeValue:
      "Useful for learning how operational response supports enterprise resilience.",
    summary:
      "A foundational incident handling guide covering preparation, detection, analysis, containment, eradication, recovery, and improvement.",
    whyItMatters:
      "Strengthens both procedural SSCP readiness and the broader operational framing expected in CISSP discussions.",
    citations: [
      {
        id: "resource-800-61",
        label: "NIST SP 800-61 Rev. 2",
        sourceName: "NIST",
        trustLevel: "trusted_live",
        url: "https://csrc.nist.gov/pubs/sp/800/61/r2/final",
      },
    ],
  },
  {
    id: "nist-digital-identity",
    title: "NIST Digital Identity Guidelines",
    url: "https://pages.nist.gov/800-63-4/",
    format: "guide",
    sourceName: "NIST",
    sourceType: "trusted_live",
    domainIds: ["access-controls"],
    difficulty: "intermediate",
    timeToConsume: "60-90 min",
    sscpFit: "Deepens access control and authentication judgment.",
    cisspBridgeValue:
      "Useful for identity assurance, federation, and lifecycle discussions at scale.",
    summary:
      "Identity guidance covering assurance, enrollment, authentication, and lifecycle considerations.",
    whyItMatters:
      "Helps you explain why identity choices succeed or fail beyond just naming an authentication method.",
    citations: [
      {
        id: "resource-800-63",
        label: "NIST Digital Identity Guidelines",
        sourceName: "NIST",
        trustLevel: "trusted_live",
        url: "https://pages.nist.gov/800-63-4/",
      },
    ],
  },
  {
    id: "nist-zero-trust",
    title: "NIST SP 800-207 Zero Trust Architecture",
    url: "https://csrc.nist.gov/pubs/sp/800/207/final",
    format: "guide",
    sourceName: "NIST",
    sourceType: "trusted_live",
    domainIds: ["access-controls", "network-communications-security"],
    difficulty: "advanced",
    timeToConsume: "75-105 min",
    sscpFit: "Useful for understanding modern trust reduction and segmentation concepts.",
    cisspBridgeValue:
      "Very strong bridge into architecture, policy enforcement, and enterprise design tradeoffs.",
    summary:
      "A practical reference for shifting from implicit network trust toward policy-driven, identity-aware access decisions.",
    whyItMatters:
      "Helps connect IAM, segmentation, and telemetry into one security story.",
    citations: [
      {
        id: "resource-800-207",
        label: "NIST SP 800-207",
        sourceName: "NIST",
        trustLevel: "trusted_live",
        url: "https://csrc.nist.gov/pubs/sp/800/207/final",
      },
    ],
  },
  {
    id: "owasp-top-10",
    title: "OWASP Top 10",
    url: "https://owasp.org/www-project-top-ten/",
    format: "guide",
    sourceName: "OWASP",
    sourceType: "trusted_live",
    domainIds: ["systems-application-security"],
    difficulty: "foundation",
    timeToConsume: "35-60 min",
    sscpFit: "High-value for application security vocabulary and risk recognition.",
    cisspBridgeValue:
      "Useful for connecting software risk to governance, testing, and architecture discussions.",
    summary:
      "A concise view of common web application risk patterns and secure design concerns.",
    whyItMatters:
      "Makes application questions more concrete and less abstract.",
    citations: [
      {
        id: "resource-owasp-top10",
        label: "OWASP Top 10",
        sourceName: "OWASP",
        trustLevel: "trusted_live",
        url: "https://owasp.org/www-project-top-ten/",
      },
    ],
  },
  {
    id: "cisa-secure-by-design",
    title: "CISA Secure by Design",
    url: "https://www.cisa.gov/securebydesign",
    format: "guide",
    sourceName: "CISA",
    sourceType: "trusted_live",
    domainIds: ["systems-application-security", "security-concepts-practices"],
    difficulty: "intermediate",
    timeToConsume: "30-45 min",
    sscpFit: "Expands system and application security beyond patching and scanning.",
    cisspBridgeValue:
      "Excellent bridge into strategic design expectations and secure product thinking.",
    summary:
      "CISA guidance on shifting responsibility toward secure defaults and resilient product design.",
    whyItMatters:
      "Helps you reason about what should be fixed structurally instead of only administratively.",
    citations: [
      {
        id: "resource-cisa-secure",
        label: "CISA Secure by Design",
        sourceName: "CISA",
        trustLevel: "trusted_live",
        url: "https://www.cisa.gov/securebydesign",
      },
    ],
  },
  {
    id: "ms-zero-trust",
    title: "Microsoft Learn: Zero Trust Guidance Center",
    url: "https://learn.microsoft.com/en-us/security/zero-trust/",
    format: "guide",
    sourceName: "Microsoft Learn",
    sourceType: "trusted_live",
    domainIds: ["access-controls", "network-communications-security"],
    difficulty: "intermediate",
    timeToConsume: "30-50 min",
    sscpFit: "Good for translating modern access and network ideas into deployment realities.",
    cisspBridgeValue:
      "Helpful for understanding how architectural principles become roadmap and control decisions.",
    summary:
      "A practical library for implementing identity-centric trust and segmentation ideas in enterprise environments.",
    whyItMatters:
      "Connects theory to implementation detail in a way that improves scenario answering.",
    citations: [
      {
        id: "resource-ms-zt",
        label: "Microsoft Learn Zero Trust",
        sourceName: "Microsoft Learn",
        trustLevel: "trusted_live",
        url: "https://learn.microsoft.com/en-us/security/zero-trust/",
      },
    ],
  },
  {
    id: "aws-security-pillar",
    title: "AWS Well-Architected Framework: Security Pillar",
    url: "https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html",
    format: "guide",
    sourceName: "AWS",
    sourceType: "trusted_live",
    domainIds: [
      "network-communications-security",
      "systems-application-security",
      "risk-identification-monitoring-analysis",
    ],
    difficulty: "advanced",
    timeToConsume: "45-75 min",
    sscpFit: "Expands cloud-era operational judgment.",
    cisspBridgeValue:
      "Strong for architectural tradeoffs, resilience, and enterprise design conversations.",
    summary:
      "A cloud-focused security guide that ties monitoring, identity, incident response, and resilience together.",
    whyItMatters:
      "Helps bridge from operational exam prep into broader architectural reasoning.",
    citations: [
      {
        id: "resource-aws-security-pillar",
        label: "AWS Well-Architected Security Pillar",
        sourceName: "AWS",
        trustLevel: "trusted_live",
        url: "https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html",
      },
    ],
  },
];

export const SSCP_TO_CISSP_BRIDGE: Record<SscpDomainId, CisspDomainId[]> = {
  "security-concepts-practices": [
    "security-risk-management",
    "security-operations",
  ],
  "access-controls": [
    "identity-access-management",
    "security-architecture-engineering",
  ],
  "risk-identification-monitoring-analysis": [
    "security-risk-management",
    "security-assessment-testing",
  ],
  "incident-response-recovery": ["security-operations", "security-risk-management"],
  cryptography: [
    "security-architecture-engineering",
    "communication-network-security",
  ],
  "network-communications-security": [
    "communication-network-security",
    "security-architecture-engineering",
  ],
  "systems-application-security": [
    "software-development-security",
    "security-operations",
  ],
};

export function getSscpDomain(domainId: SscpDomainId): SscpDomain {
  const domain = SSCP_DOMAINS.find((entry) => entry.id === domainId);
  if (!domain) {
    throw new Error(`Unknown SSCP domain: ${domainId}`);
  }
  return domain;
}

export function getCisspDomainsForSscp(domainId: SscpDomainId): CisspDomain[] {
  const ids = SSCP_TO_CISSP_BRIDGE[domainId];
  return CISSP_DOMAINS.filter((domain) => ids.includes(domain.id));
}
