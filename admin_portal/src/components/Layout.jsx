import React, { useState } from "react";
import { NavLink, Outlet } from "react-router-dom";
import {
  LayoutDashboard,
  Cpu,
  Users,
  Music2,
  LogOut,
  Menu,
  X,
  House,
  Shapes,
  Settings,
} from "lucide-react";
import { useAuth } from "../context/AuthContext";

const items = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard, end: true },
  { to: "/homes", label: "Homes", icon: House },
  { to: "/devices", label: "Devices", icon: Cpu },
  { to: "/device-types", label: "Device Types", icon: Shapes },
  { to: "/users", label: "Users", icon: Users },
  { to: "/music", label: "Music", icon: Music2 },
  { to: '/settings', label: 'Settings', icon: Settings },
];

export default function Layout() {
  const { user, logout } = useAuth();
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <div className="app-shell">
      <aside className={`sidebar ${mobileOpen ? "open" : ""}`}>
        <div className="brand">
          <div className="brand-mark">L</div>
          <div>
            <div className="brand-name">Lily</div>
            <div className="brand-sub">Admin Portal</div>
          </div>
          <button
            className="icon-button sidebar-close"
            onClick={() => setMobileOpen(false)}
          >
            <X size={20} />
          </button>
        </div>

        <nav className="nav-list">
          {items.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              onClick={() => setMobileOpen(false)}
              className={({ isActive }) =>
                `nav-item ${isActive ? "active" : ""}`
              }
            >
              <Icon size={19} />
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>

        <div className="sidebar-footer">
          <div className="admin-identity">
            <div className="avatar">{(user?.email || "A")[0].toUpperCase()}</div>
            <div className="identity-text">
              <strong>Administrator</strong>
              <span>{user?.email}</span>
            </div>
          </div>

          <button className="logout-button" onClick={logout}>
            <LogOut size={18} />
            Sign out
          </button>
        </div>
      </aside>

      <main className="main-panel">
        <header className="topbar">
          <button className="icon-button mobile-menu" onClick={() => setMobileOpen(true)}>
            <Menu size={22} />
          </button>
          <div>
            <strong>Lily Device Platform</strong>
            <span>Administration</span>
          </div>
        </header>

        <div className="content">
          <Outlet />
        </div>
      </main>

      {mobileOpen && (
        <div className="sidebar-overlay" onClick={() => setMobileOpen(false)} />
      )}
    </div>
  );
}
