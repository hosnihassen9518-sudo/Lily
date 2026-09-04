import React from "react";

export default function StatusBadge({ status }) {
  const normalized = String(status || "UNKNOWN").toUpperCase();
  const cls =
    normalized === "ONLINE"
      ? "success"
      : normalized === "INVENTORY"
      ? "neutral"
      : normalized === "DISABLED"
      ? "danger"
      : "warning";

  return <span className={`status-badge ${cls}`}>{normalized}</span>;
}
