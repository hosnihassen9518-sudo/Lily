import { NavLink, Outlet, useLocation } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import PermissionGate from "../components/PermissionGate";
import RateLimits from "./RateLimits";
import React, { useEffect, useState } from "react";
import { api } from "../services/api";
function SessionSettings() {
  const [months, setMonths] = useState(3);
  const [busy, setBusy] = useState(true);
  const [message, setMessage] = useState("");
  useEffect(() => {
    api
      .mobileSessionPolicy()
      .then((p) => setMonths(p.months))
      .catch((e) => setMessage(e.message))
      .finally(() => setBusy(false));
  }, []);
  async function save(e) {
    e.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      const saved = await api.setMobileSessionPolicy({
        months: Number(months),
      });
      setMonths(saved.months);
      setMessage("Settings saved.");
    } catch (e) {
      setMessage(e.message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <div className="page-heading">
        <h1>Settings</h1>
      </div>
      <form className="panel form-grid" onSubmit={save}>
        <h2>Mobile login duration</h2>
        <p>
          Users stay signed in for this many months after login. The default is
          three months. Changes apply to future logins; existing sessions keep
          their expiry date.
        </p>
        <label>
          Months
          <input
            type="number"
            min="1"
            max="12"
            step="1"
            required
            value={months}
            onChange={(e) => setMonths(e.target.value)}
          />
        </label>
        <PermissionGate permission="settings.change" action>
          <button className="primary-button" disabled={busy}>
            Save
          </button>
        </PermissionGate>
        {message && <p role="status">{message}</p>}
      </form>
    </>
  );
}

export default function SettingsPage() {
  const {can} = useAuth();
  const location = useLocation();
  const sections = [
    ["administrators", "Administrators", "users.read"],
    ["roles", "Roles", "roles.read"],
    ["api-roles", "API Roles", "api_roles.read"],
    ["api-access", "API Access", "api_credentials.read"],
    ["sessions", "Sessions", null],
    ["audit", "Audit", "audit.read"],
  ];
  return <>
    <nav aria-label="Settings sections" className="access-actions" style={{flexWrap:"wrap", marginBottom:20}}>
      {can("settings.read") && <NavLink className="secondary-button" to="/settings" end>General</NavLink>}
      {sections.filter(([, ,permission]) => !permission || can(permission)).map(([path,label]) =>
        <NavLink key={path} className={({isActive}) => isActive ? "primary-button" : "secondary-button"} to={`/settings/${path}`}>{label}</NavLink>)}
    </nav>
    {location.pathname.replace(/\/$/, "") === "/settings" ?
      (can("settings.read") ? <><SessionSettings/><RateLimits/></> : <p>Select a settings section.</p>) : <Outlet/>}
  </>;
}
