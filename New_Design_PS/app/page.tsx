import Link from "next/link";

export default function HomePage() {
  const tokens = {
    bg: "#f2ece2",
    panel: "#ffffff",
    border: "#e0dad2",
    text: "#1c2020",
    muted: "#5f5a57",
    primary: "#834078",
    onPrimary: "#ffffff",
    shadow: "0 1px 2px rgba(0,0,0,0.04), 0 8px 24px rgba(0,0,0,0.06)",
    radius: 18,
    surface: "#ffffff",
    surface2: "#f7f2e8",
  };

  const page: React.CSSProperties = {
    minHeight: "100vh",
    background: tokens.bg,
    color: tokens.text,
    fontFamily: "ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial",
  };

  const container: React.CSSProperties = {
    maxWidth: 980,
    margin: "0 auto",
    padding: "40px 16px 56px",
  };

  // Header card WITHOUT the right-side buttons (per your screenshot request)
  const headerCard: React.CSSProperties = {
    background: tokens.panel,
    border: `1px solid ${tokens.border}`,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: 22,
    display: "flex",
    alignItems: "center",
    justifyContent: "flex-start",
    gap: 16,
  };

  const grid: React.CSSProperties = {
    marginTop: 16,
    display: "grid",
    gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))",
    gap: 14,
  };

  const card: React.CSSProperties = {
    background: tokens.surface,
    border: `1px solid ${tokens.border}`,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: 18,
    display: "flex",
    flexDirection: "column",
    gap: 10,
    textDecoration: "none",
    color: tokens.text,
  };

  const cardTop: React.CSSProperties = {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
  };

  const pill: React.CSSProperties = {
    fontSize: 12,
    fontWeight: 800,
    padding: "6px 10px",
    borderRadius: 999,
    background: tokens.surface2,
    border: `1px solid ${tokens.border}`,
    color: tokens.text,
    whiteSpace: "nowrap",
  };

  const primaryBtn: React.CSSProperties = {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    padding: "10px 12px",
    borderRadius: 12,
    border: `1px solid ${tokens.primary}`,
    background: tokens.primary,
    color: tokens.onPrimary,
    fontWeight: 800,
    fontSize: 13,
    textDecoration: "none",
  };

  return (
    <div style={page}>
      <div style={container}>
        

        <div style={grid}>
          {/* Update these hrefs if your routes differ */}
          <Link href="/ExcelParser" style={card}>
            <div style={cardTop}>
              <div style={{ fontWeight: 900, fontSize: 16 }}>Excel Parser</div>
              <div style={pill}>CSV generator</div>
            </div>
            <div style={{ color: tokens.muted, fontSize: 13, lineHeight: "18px" }}>
              Upload an Excel file, map ranges, apply filters, generate Records/Assignments CSV.
            </div>
            <div style={{ marginTop: 6, display: "flex", justifyContent: "flex-end" }}>
              <span style={primaryBtn as any}>Open →</span>
            </div>
          </Link>

          <Link href="/Powershell-ConnectorsTool" style={card}>
            <div style={cardTop}>
              <div style={{ fontWeight: 900, fontSize: 16 }}>PowerShell Connectors Tool</div>
              <div style={pill}>Connectors</div>
            </div>
            <div style={{ color: tokens.muted, fontSize: 13, lineHeight: "18px" }}>
              Manage / generate / connector-related PowerShell utilities and helpers.
            </div>
            <div style={{ marginTop: 6, display: "flex", justifyContent: "flex-end" }}>
              <span style={primaryBtn as any}>Open →</span>
            </div>
          </Link>
        </div>

        
      </div>
    </div>
  );
}
