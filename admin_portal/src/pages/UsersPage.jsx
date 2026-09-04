import React, { useEffect, useMemo, useState } from "react";
import { Search, RefreshCw, Users, Ban, CheckCircle2 } from "lucide-react";
import { api } from "../services/api";
import EmptyState from "../components/EmptyState";

export default function UsersPage() {
  const [users, setUsers] = useState([]);
  const [query, setQuery] = useState("");
  const [error, setError] = useState("");

  async function load() {
    try {
      setError("");
      setUsers(await api.users());
    } catch (err) {
      setError(err.message);
    }
  }

  useEffect(() => {
    load();
  }, []);

  const filtered = useMemo(() => {
    const q = query.toLowerCase();
    return users.filter((u) =>
      [u.email, u.first_name, u.last_name]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(q))
    );
  }, [users, query]);

  async function toggleUser(u) {
    if (u.admin) {
      alert("Administrator accounts cannot be disabled from this view.");
      return;
    }

    try {
      await api.setUserActive(u.id, !u.active);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <h1>Users</h1>
          <p>Accounts created through the mobile application.</p>
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="toolbar">
        <div className="search-box">
          <Search size={18} />
          <input
            placeholder="Search users..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <button className="secondary-button" onClick={load}>
          <RefreshCw size={17} />
          Refresh
        </button>
      </div>

      <div className="panel no-pad">
        {filtered.length ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>User</th>
                  <th>Email</th>
                  <th>Role</th>
                  <th>Status</th>
                  <th>Registered</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {filtered.map((u) => (
                  <tr key={u.id}>
                    <td>
                      <strong>
                        {[u.first_name, u.last_name].filter(Boolean).join(" ") || "Unnamed user"}
                      </strong>
                    </td>
                    <td>{u.email}</td>
                    <td>{u.admin ? "Administrator" : "User"}</td>
                    <td>
                      <span className={`status-badge ${u.active ? "success" : "danger"}`}>
                        {u.active ? "ACTIVE" : "DISABLED"}
                      </span>
                    </td>
                    <td>{new Date(u.created_at).toLocaleString()}</td>
                    <td>
                      {!u.admin && (
                        <button
                          className="icon-button"
                          title={u.active ? "Disable user" : "Enable user"}
                          onClick={() => toggleUser(u)}
                        >
                          {u.active ? <Ban size={18} /> : <CheckCircle2 size={18} />}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState icon={Users} title="No users found" text="No account matches this search." />
        )}
      </div>
    </>
  );
}
