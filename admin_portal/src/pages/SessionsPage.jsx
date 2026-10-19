import React, { useEffect, useState } from "react";
import { api } from "../services/api";
import { useAuth } from "../context/AuthContext";
export default function SessionsPage() {
  const { user, can } = useAuth();
  const [rows, setRows] = useState([]),
    [target, setTarget] = useState(String(user.id)),
    [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false);
  async function load() {
    setError("");
    try {
      setRows(
        await api.access(
          "/access/sessions?user_id=" + encodeURIComponent(target),
        ),
      );
    } catch (e) {
      setError(e.message);
    }
  }
  useEffect(() => {
    load();
  }, []);
  async function revoke(id) {
    setBusy(true);
    try {
      await api.access("/access/sessions/" + id, "DELETE");
      setNotice("Session revoked.");
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>Sessions</h1>
          <p>Revoked sessions lose access on their next request.</p>
        </div>
      </div>
      {error && (
        <div role="alert" className="alert error">
          {error}
        </div>
      )}
      {notice && (
        <div role="status" className="alert">
          {notice}
        </div>
      )}
      <div className="panel access-panel">
        <form
          className="access-actions"
          onSubmit={(e) => {
            e.preventDefault();
            load();
          }}
        >
          <label>
            Account ID
            <input
              type="number"
              min="1"
              required
              value={target}
              disabled={!can("sessions.read")}
              onChange={(e) => setTarget(e.target.value)}
            />
          </label>
          <button className="secondary-button">Load sessions</button>
          {(Number(target) === user.id || can("sessions.revoke")) && (
            <button
              type="button"
              className="secondary-button danger-text"
              disabled={busy}
              onClick={async () => {
                if (!window.confirm("Revoke all sessions for this account?"))
                  return;
                setBusy(true);
                try {
                  await api.access(
                    `/access/users/${target}/revoke-sessions`,
                    "POST",
                  );
                  setNotice("All sessions revoked.");
                  await load();
                } catch (e) {
                  setError(e.message);
                } finally {
                  setBusy(false);
                }
              }}
            >
              Revoke all sessions
            </button>
          )}
        </form>
      </div>
      <div className="panel table-wrap">
        <table>
          <thead>
            <tr>
              <th>Session</th>
              <th>Type</th>
              <th>Created</th>
              <th>Expires</th>
              <th>Last activity</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((s) => (
              <tr key={s.id}>
                <td>
                  {s.id.slice(0, 12)}
                  {s.id === user.session_id ? " · this session" : ""}
                  <small className="access-muted">
                    {s.revoked_at ? "Revoked" : "Active"}
                  </small>
                </td>
                <td>{s.auth_method}</td>
                <td>{new Date(s.created_at).toLocaleString()}</td>
                <td>{new Date(s.expires_at).toLocaleString()}</td>
                <td>{new Date(s.last_activity).toLocaleString()}</td>
                <td>
                  {!s.revoked_at &&
                    (s.user_id === user.id || can("sessions.revoke")) && (
                      <button
                        className="secondary-button"
                        disabled={busy}
                        onClick={() => revoke(s.id)}
                      >
                        Revoke {s.id.slice(0, 8)}
                      </button>
                    )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!rows.length && <p className="access-panel">No sessions found.</p>}
      </div>
    </>
  );
}
