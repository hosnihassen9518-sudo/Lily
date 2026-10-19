import React, { useEffect, useState } from "react";
import { api } from "../services/api";
import { useAuth } from "../context/AuthContext";
export default function ApiAccessPage() {
  const { can } = useAuth();
  const [rows, setRows] = useState([]),
    [roles, setRoles] = useState([]),
    [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false),
    [loading, setLoading] = useState(true),
    [secret, setSecret] = useState(null),
    [editing, setEditing] = useState(null);
  const [form, setForm] = useState({
    name: "",
    roles: [],
    expires_at: "",
    rate_limit: 120,
    all: false,
    devices: "",
    homes: "",
  });
  async function load() {
    try {
      setRows(await api.access("/access/api-credentials"));
      if (can("api_roles.read"))
        setRoles(await api.access("/access/api-roles"));
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    load();
  }, []);
  function choices(value, change) {
    return <label>Assigned role<select aria-label="Assigned role" value={value.length === 1 ? value[0] : ""} onChange={e=>change(e.target.value ? [e.target.value] : [])}>
      <option value="">No role</option>{roles.map(r=><option key={r.key} value={r.key}>{r.name}</option>)}
    </select>{value.length > 1 && <span role="alert">Multiple roles detected. Select one role to resolve.</span>}</label>;
  }
  function ids(text) {
    if (!text.trim()) return [];
    const values = text.split(",").map((x) => Number(x.trim()));
    if (values.some((x) => !Number.isInteger(x) || x < 1))
      throw new Error("Use positive resource IDs separated by commas.");
    return [...new Set(values)];
  }
  async function create(e) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const payload = {
        name: form.name,
        roles: form.roles,
        expires_at: new Date(form.expires_at).toISOString(),
        rate_limit: Number(form.rate_limit),
        scope: {
          all: form.all,
          devices: ids(form.devices),
          homes: ids(form.homes),
        },
      };
      const result = await api.access(
        "/access/api-credentials",
        "POST",
        payload,
      );
      setSecret(result.secret);
      setForm({ ...form, name: "", roles: [] });
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  async function revoke(r) {
    if (!window.confirm(`Revoke ${r.name} and its active API sessions?`))
      return;
    setBusy(true);
    try {
      await api.access("/access/api-credentials/" + r.id, "DELETE");
      setNotice("Credential and its sessions revoked.");
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
          <h1>API access</h1>
          <p>
            Issue scoped credentials, then exchange them for short-lived API
            sessions.
          </p>
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
      {secret && (
        <section
          className="panel access-panel"
          role="region"
          aria-label="New API credential"
        >
          <h2>Save this credential now</h2>
          <p>It is shown once. Keep it in your integration's secret storage.</p>
          <textarea aria-label="API credential" readOnly value={secret} />
          <button className="secondary-button" onClick={() => setSecret(null)}>
            I have saved it — close
          </button>
        </section>
      )}
      {can("api_credentials.create") && can("api_roles.assign") && (
        <section className="panel access-panel">
          <h2>Create API credential</h2>
          <form onSubmit={create}>
            <div className="form-grid">
              <label>
                Name
                <input
                  required
                  maxLength={120}
                  value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                />
              </label>
              <label>
                Expires at
                <input
                  required
                  type="datetime-local"
                  value={form.expires_at}
                  onChange={(e) =>
                    setForm({ ...form, expires_at: e.target.value })
                  }
                />
              </label>
              <label>
                Requests per minute
                <input
                  type="number"
                  min="1"
                  max="120"
                  value={form.rate_limit}
                  onChange={(e) =>
                    setForm({ ...form, rate_limit: e.target.value })
                  }
                />
              </label>
              <label>
                Device IDs
                <input
                  placeholder="1, 2"
                  value={form.devices}
                  onChange={(e) =>
                    setForm({ ...form, devices: e.target.value })
                  }
                />
              </label>
              <label>
                Home IDs
                <input
                  placeholder="1, 2"
                  value={form.homes}
                  onChange={(e) => setForm({ ...form, homes: e.target.value })}
                />
              </label>
            </div>
            <h3>API roles</h3>
            {choices(form.roles, (roles) => setForm({ ...form, roles }))}
            {can("resources.all") && (
              <label className="access-check">
                <input
                  type="checkbox"
                  checked={form.all}
                  onChange={(e) => setForm({ ...form, all: e.target.checked })}
                />
                All resources
              </label>
            )}
            <button
              className="primary-button"
              disabled={busy || !form.roles.length}
            >
              Create credential
            </button>
          </form>
        </section>
      )}
      {loading ? (
        <p>Loading credentials…</p>
      ) : (
        <div className="panel table-wrap">
          <table>
            <thead>
              <tr>
                <th>Name / public ID</th>
                <th>Roles / scope</th>
                <th>Expires / last used</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td>
                    <strong>{r.name}</strong>
                    <small className="access-muted">{r.id}</small>
                  </td>
                  <td>
                    {r.roles.join(", ")}
                    <small className="access-muted">
                      {r.scope.all
                        ? "All resources"
                        : `Devices: ${r.scope.devices?.join(", ") || "none"} · Homes: ${r.scope.homes?.join(", ") || "none"}`}
                    </small>
                  </td>
                  <td>
                    {new Date(r.expires_at).toLocaleString()}
                    <small className="access-muted">
                      Last used:{" "}
                      {r.last_used_at
                        ? new Date(r.last_used_at).toLocaleString()
                        : "Never"}
                    </small>
                  </td>
                  <td>
                    {r.revoked_at
                      ? "Revoked"
                      : new Date(r.expires_at) < new Date()
                        ? "Expired"
                        : "Active"}
                  </td>
                  <td>
                    {!r.revoked_at && can("api_credentials.revoke") && (
                      <button
                        className="secondary-button danger-text"
                        disabled={busy}
                        onClick={() => revoke(r)}
                      >
                        Revoke {r.name}
                      </button>
                    )}
                    {!r.revoked_at && can("api_roles.assign") && (
                      <button
                        className="secondary-button"
                        onClick={() => setEditing({ ...r })}
                      >
                        Assign roles to {r.name}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {!rows.length && (
            <p className="access-panel">No API credentials yet.</p>
          )}
        </div>
      )}
      {editing && (
        <section className="panel access-panel">
          <h2>API roles for {editing.name}</h2>
          {choices(editing.roles, (roles) => setEditing({ ...editing, roles }))}
          <div className="access-actions">
            <button
              className="primary-button"
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                try {
                  await api.access(
                    `/access/api-credentials/${editing.id}/roles`,
                    "PUT",
                    { roles: editing.roles },
                  );
                  setEditing(null);
                  setNotice("API roles updated. Previous sessions revoked.");
                  await load();
                } catch (e) {
                  setError(e.message);
                } finally {
                  setBusy(false);
                }
              }}
            >
              Save API roles
            </button>
            <button
              className="secondary-button"
              onClick={() => setEditing(null)}
            >
              Cancel
            </button>
          </div>
        </section>
      )}
    </>
  );
}
