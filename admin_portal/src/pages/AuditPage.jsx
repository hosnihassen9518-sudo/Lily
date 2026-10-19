import React, { useEffect, useState } from "react";
import { api } from "../services/api";
export default function AuditPage() {
  const [rows, setRows] = useState([]),
    [error, setError] = useState(""),
    [loading, setLoading] = useState(true);
  async function load() {
    setLoading(true);
    try {
      setRows(await api.access("/access/audit"));
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    load();
  }, []);
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>Audit log</h1>
          <p>Administrative changes and access events. Secrets are excluded.</p>
        </div>
        <button className="secondary-button" onClick={load}>
          Refresh
        </button>
      </div>
      {error && (
        <div className="alert error" role="alert">
          {error}
        </div>
      )}
      {loading ? (
        <p>Loading audit log…</p>
      ) : (
        <div className="panel table-wrap">
          <table>
            <thead>
              <tr>
                <th>When</th>
                <th>Actor</th>
                <th>Action</th>
                <th>Target</th>
                <th>Result</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td>{new Date(r.created_at).toLocaleString()}</td>
                  <td>{r.actor_id ?? "System"}</td>
                  <td>{r.action}</td>
                  <td>{r.target || "—"}</td>
                  <td>{r.result}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {!rows.length && <p className="access-panel">No audit events yet.</p>}
        </div>
      )}
    </>
  );
}
