import React, { useEffect, useState } from "react";
import { api } from "../services/api";
import { useAuth } from "../context/AuthContext";
import PermissionMatrix from "../components/PermissionMatrix";
export default function RolesPage({ audience = "portal" }) {
  const { can } = useAuth();
  const prefix = audience === "api" ? "api_roles" : "roles";
  const route = audience === "api" ? "/access/api-roles" : "/access/roles";
  const [roles, setRoles] = useState([]),
    [catalog, setCatalog] = useState({}),
    [selected, setSelected] = useState(null),
    [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(false);
  async function load() {
    try {
      setLoading(true);
      const [r, c] = await Promise.all([
        api.access(route),
        api.access("/access/permissions"),
      ]);
      setRoles(r);
      setCatalog(c.resources);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    setSelected(null);
    setError("");
    load();
  }, [audience]);
  async function save(e) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const editing = Boolean(selected.existing);
      await api.access(
        route + (editing ? "/" + selected.key : ""),
        editing ? "PATCH" : "POST",
        editing
          ? { name: selected.name, permissions: selected.permissions }
          : {
              key: selected.key,
              name: selected.name,
              permissions: selected.permissions,
            },
      );
      setNotice("Role saved. Affected sessions have been revoked.");
      setSelected(null);
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  async function remove(r) {
    if (
      !window.confirm(
        `Delete custom role ${r.name}? Assigned roles must be unassigned first.`,
      )
    )
      return;
    setBusy(true);
    try {
      await api.access(route + "/" + r.key, "DELETE");
      await load();
      setNotice("Role deleted.");
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
          <h1>{audience === "api" ? "API roles" : "Roles"}</h1>
          <p>
            Choose access separately for each feature. Predefined roles are
            locked.
          </p>
        </div>
        {can(prefix + ".create") && (
          <button
            className="primary-button"
            onClick={() =>
              setSelected({
                key: "",
                name: "",
                permissions: [],
                predefined: false,
              })
            }
          >
            Create role
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
        <p>Loading roles…</p>
      ) : (
        <div className="panel table-wrap">
          <table>
            <thead>
              <tr>
                <th>Role</th>
                <th>Type</th>
                <th>Permissions</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {roles.map((r) => (
                <tr key={r.key}>
                  <td>
                    <strong>{r.name}</strong>
                    <small className="access-muted">{r.key}</small>
                  </td>
                  <td>{r.predefined ? "Predefined · locked" : "Custom"}</td>
                  <td>{r.permissions.length}</td>
                  <td>
                    <button
                      className="secondary-button"
                      onClick={() => setSelected({ ...r, existing: true })}
                    >
                      {r.predefined || !can(prefix + ".change")
                        ? "View"
                        : "Edit"}{" "}
                      {r.name}
                    </button>
                    {!r.predefined && can(prefix + ".delete") && (
                      <button
                        className="secondary-button danger-text"
                        disabled={busy}
                        onClick={() => remove(r)}
                      >
                        Delete {r.name}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {!roles.length && <p className="access-panel">No roles yet.</p>}
        </div>
      )}
      {selected && (
        <section className="panel access-panel">
          <h2>
            {selected.predefined
              ? "Predefined role"
              : Boolean(selected.existing)
                ? "Edit role"
                : "New role"}
          </h2>
          <form onSubmit={save}>
            <div className="form-grid">
              <label>
                Role key
                <input
                  required
                  pattern="[a-z][a-z0-9_]{2,79}"
                  value={selected.key}
                  disabled={selected.predefined || Boolean(selected.existing)}
                  onChange={(e) =>
                    setSelected({ ...selected, key: e.target.value })
                  }
                />
              </label>
              <label>
                Name
                <input
                  required
                  maxLength={120}
                  value={selected.name}
                  disabled={selected.predefined}
                  onChange={(e) =>
                    setSelected({ ...selected, name: e.target.value })
                  }
                />
              </label>
            </div>
            <PermissionMatrix
              catalog={catalog}
              value={selected.permissions}
              onChange={(permissions) =>
                setSelected({ ...selected, permissions })
              }
              disabled={
                selected.predefined ||
                busy ||
                !can(
                  prefix + (Boolean(selected.existing) ? ".change" : ".create"),
                )
              }
            />
            <div className="access-actions">
              {!selected.predefined &&
                can(
                  prefix + (Boolean(selected.existing) ? ".change" : ".create"),
                ) && (
                  <button className="primary-button" disabled={busy}>
                    Save role
                  </button>
                )}
              <button
                type="button"
                className="secondary-button"
                onClick={() => setSelected(null)}
              >
                Close
              </button>
            </div>
          </form>
        </section>
      )}
    </>
  );
}
