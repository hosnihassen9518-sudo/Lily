import React, { useEffect, useState } from "react";
import {
  Cpu,
  Users,
  Music2,
  Wifi,
  Boxes,
  House,
  DoorOpen,
  Activity,
  RefreshCw,
} from "lucide-react";
import { api } from "../services/api";

const cards = [
  { key: "devices_total", label: "Total devices", icon: Cpu },
  { key: "devices_online", label: "Online now", icon: Wifi },
  { key: "devices_inventory", label: "In inventory", icon: Boxes },
  { key: "users", label: "Users", icon: Users },
  { key: "homes", label: "Homes", icon: House },
  { key: "rooms", label: "Rooms", icon: DoorOpen },
  { key: "telemetry_points", label: "Telemetry points", icon: Activity },
  { key: "music_tracks", label: "Music tracks", icon: Music2 },
];

export default function DashboardPage() {
  const [data, setData] = useState(null);
  const [devices, setDevices] = useState([]);
  const [error, setError] = useState("");

  async function load() {
    try {
      setError("");
      const [dashboard, deviceRows] = await Promise.all([
        api.dashboard(),
        api.devices(),
      ]);
      setData(dashboard);
      setDevices(deviceRows.slice(0, 6));
    } catch (err) {
      setError(err.message);
    }
  }

  useEffect(() => {
    load();
    const id = setInterval(load, 15000);
    return () => clearInterval(id);
  }, []);

  return (
    <>
      <div className="page-heading">
        <div>
          <h1>Dashboard</h1>
          <p>Live overview of users, smart homes, inventory, telemetry, and connected devices.</p>
        </div>
        <button className="secondary-button" onClick={load}>
          <RefreshCw size={17} />
          Refresh
        </button>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="stat-grid">
        {cards.map(({ key, label, icon: Icon }) => (
          <div className="stat-card" key={key}>
            <div className="stat-icon">
              <Icon size={22} />
            </div>
            <div>
              <span>{label}</span>
              <strong>{data ? data[key] : "—"}</strong>
            </div>
          </div>
        ))}
      </div>

      <div className="panel">
        <div className="panel-header">
          <div>
            <h2>Recent devices</h2>
            <p>Connection state refreshes automatically every 15 seconds.</p>
          </div>
        </div>

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Device</th>
                <th>Serial</th>
                <th>Status</th>
                <th>Firmware</th>
                <th>Wi-Fi</th>
                <th>Last seen</th>
              </tr>
            </thead>
            <tbody>
              {devices.map((d) => (
                <tr key={d.id}>
                  <td>
                    <strong>{d.name || d.model}</strong>
                    <span className="muted-cell">{d.model}</span>
                  </td>
                  <td className="mono">{d.serial_number}</td>
                  <td>
                    <span className={`status-dot ${d.status.toLowerCase()}`} />
                    {d.status}
                  </td>
                  <td>{d.firmware_version || "—"}</td>
                  <td>{d.wifi_rssi ? `${d.wifi_rssi} dBm` : "—"}</td>
                  <td>{d.last_seen ? new Date(d.last_seen).toLocaleString() : "Never"}</td>
                </tr>
              ))}
              {!devices.length && (
                <tr>
                  <td colSpan="6" className="empty-row">No devices yet.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
