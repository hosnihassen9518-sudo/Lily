import React, { useEffect, useState } from "react";
import { api } from "../services/api";
import { useAuth } from "../context/AuthContext";
import PermissionMatrix from "../components/PermissionMatrix";
export default function AccessUsersPage() {
  const { can, user } = useAuth();
  const [reset, setReset] = useState(null);
  const [users, setUsers] = useState([]),
    [roles, setRoles] = useState([]),
    [catalog, setCatalog] = useState({}),
    [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false),
    [loading, setLoading] = useState(true),
    [selected, setSelected] = useState(null),
    [draft, setDraft] = useState(null);
  async function load() {
    try {
      const u = await api.access("/access/users");
      setUsers(u);
      if (can("roles.read")) setRoles(await api.access("/access/roles"));
      if (can("delegation.change"))
        setCatalog((await api.access("/access/permissions")).resources);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    load();
  }, []);
  async function run(fn) {
    setBusy(true);
    setError("");
    try {
      await fn();
      setNotice("Saved. Affected sessions have been revoked.");
      setSelected(null);
      setDraft(null);
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  function choices(value, change) {
    return <label>Assigned role<select aria-label="Assigned role" value={value.length === 1 ? value[0] : ""} onChange={e=>change(e.target.value ? [e.target.value] : [])}>
      <option value="">No role</option>{roles.map(r=><option key={r.key} value={r.key}>{r.name}</option>)}
    </select>{value.length > 1 && <span role="alert">Multiple roles detected. Select one role to resolve.</span>}</label>;
  }
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>Administrators</h1>
          <p>Assign roles and manage account access.</p>
        </div>
        {can("administrators.create") && (
          <button
            className="primary-button"
            onClick={() => setDraft({ email: "", password: "", roles: [] })}
          >
            Create account
          </button>
        )}
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
      {loading ? (
        <p>Loading users…</p>
      ) : (
        <div className="panel table-wrap">
          <table>
            <thead>
              <tr>
                <th>Account</th>
                <th>Roles</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.id}>
                  <td>{u.email}</td>
                  <td>{u.roles.join(", ") || "No role"}</td>
                  <td>{u.active ? "Active" : "Disabled"}</td>
                  <td>
                    {user?.roles?.includes("superuser") && <button className="secondary-button" onClick={() => setReset({id:u.id,email:u.email,password:""})}>Reset password for {u.email}</button>}
                    {can("roles.assign") && (
                      <button
                        className="secondary-button"
                        onClick={() => setSelected({ ...u })}
                      >
                        Edit access for {u.email}
                      </button>
                    )}
                    {can("administrators.change") && (
                      <button
                        className="secondary-button"
                        disabled={busy}
                        onClick={() =>
                          run(() =>
                            api.access(
                              `/access/users/${u.id}/active`,
                              "PATCH",
                              { active: !u.active },
                            ),
                          )
                        }
                      >
                        {u.active ? "Disable" : "Enable"}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {reset && <section className="panel"><h2>Reset password for {reset.email}</h2>
        <p>All sessions for this account will be revoked.</p>
        <form className="form-grid" onSubmit={e => {e.preventDefault(); run(async () => {await api.access(`/access/users/${reset.id}/password`, "POST", {password:reset.password}); setReset(null);});}}>
          <label>New password<input type="password" autoComplete="new-password" minLength={12} maxLength={72} required value={reset.password} onChange={e=>setReset({...reset,password:e.target.value})}/></label>
          <button className="primary-button" disabled={busy}>Reset password</button>
          <button type="button" className="secondary-button" onClick={()=>setReset(null)}>Cancel</button>
        </form></section>}
      {draft && (
        <section className="panel access-panel">
          <h2>Create account</h2>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              run(() => api.access("/access/users", "POST", draft));
            }}
            className="form-grid"
          >
            <label>
              Email
              <input
                required
                type="email"
                autoComplete="off"
                value={draft.email}
                onChange={(e) => setDraft({ ...draft, email: e.target.value })}
              />
            </label>
            <label>
              Initial password
              <input
                required
                type="password"
                autoComplete="new-password"
                minLength={12}
                maxLength={72}
                value={draft.password}
                onChange={(e) =>
                  setDraft({ ...draft, password: e.target.value })
                }
              />
            </label>
            {can("roles.assign") &&
              choices(draft.roles, (roles) => setDraft({ ...draft, roles }))}
            <div className="access-actions">
              <button className="primary-button" disabled={busy}>
                Create account
              </button>
              <button
                type="button"
                className="secondary-button"
                onClick={() => setDraft(null)}
              >
                Cancel
              </button>
            </div>
          </form>
        </section>
      )}
      {selected && (
        <section className="panel access-panel">
          <h2>Access for {selected.email}</h2>
          {choices(selected.roles, (roles) =>
            setSelected({ ...selected, roles }),
          )}
          <div className="access-actions">
            <button
              className="primary-button"
              disabled={busy}
              onClick={() =>
                run(() =>
                  api.access(`/access/users/${selected.id}/roles`, "PUT", {
                    roles: selected.roles,
                  }),
                )
              }
            >
              Save assigned roles
            </button>
            <button
              className="secondary-button"
              onClick={() => setSelected(null)}
            >
              Close
            </button>
          </div>
          {can("delegation.change") && (
            <>
              <h3>Permissions this administrator may grant</h3>
              <PermissionMatrix
                catalog={catalog}
                value={selected.ceiling}
                onChange={(ceiling) => setSelected({ ...selected, ceiling })}
              />
              <button
                className="primary-button"
                disabled={busy}
                onClick={() =>
                  run(() =>
                    api.access(`/access/users/${selected.id}/ceiling`, "PUT", {
                      permissions: selected.ceiling,
                    }),
                  )
                }
              >
                Save grant ceiling
              </button>
            </>
          )}
        </section>
      )}
    </>
  );
}
