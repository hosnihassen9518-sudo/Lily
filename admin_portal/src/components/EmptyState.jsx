import React from "react";

export default function EmptyState({ icon: Icon, title, text }) {
  return (
    <div className="empty-state">
      {Icon && <Icon size={36} strokeWidth={1.5} />}
      <h3>{title}</h3>
      <p>{text}</p>
    </div>
  );
}
