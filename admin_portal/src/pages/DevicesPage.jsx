import React, { useEffect, useMemo, useState } from "react";
import {
  Plus,
  Search,
  RefreshCw,
  Trash2,
  Ban,
  CheckCircle2,
  Cpu,
} from "lucide-react";
import { api } from "../services/api";
import StatusBadge from "../components/StatusBadge";
import Modal from "../components/Modal";
import EmptyState from "../components/EmptyState";

export default function DevicesPage() {
  const [devices, setDevices] = useState([]);
  const [query, setQuery] = useState("");
  const [showCreate, setShowCreate] = useState(false);
  const [error, setError] = useState("");
  const [form, setForm] = useState({
    serial_number: "",
    device_secret: "",
    model: "LILY-V1",
    hardware_version: "1.0",
  });

  async function load() {
    try {
      setError("");
      setDevices(await api.devices());
    } catch (err) {
      setError(err.message);
    }
  }

  useEffect(() => {
    load();
    const id = setInterval(load, 10000);
    return () => clearInterval(id);
  }, []);

  const filtered = useMemo(() => {
    const q = query.toLowerCase();
    return devices.filter((d) =>
      [d.serial_number, d.name, d.model, d.status]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(q))
    );
  }, [devices, query]);

  async function createDevice(e) {
    e.preventDefault();
    try {
      await api.createDevice(form);
      setShowCreate(false);
      setForm({
        serial_number: "",
        device_secret: "",
        model: "LILY-V1",
        hardware_version: "1.0",
      });
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  async function toggleDisabled(d) {
    const disabled = d.status !== "DISABLED";
    if (!confirm(`${disabled ? "Disable" : "Enable"} ${d.serial_number}?`)) return;
    try {
      await api.setDeviceDisabled(d.id, disabled);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  async function remove(d) {
    if (!confirm(`Permanently delete ${d.serial_number}?`)) return;
    try {
      await api.deleteDevice(d.id);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <h1>Devices</h1>
          <p>Manage factory inventory and monitor deployed devices.</p>
        </div>
        <button className="primary-button" onClick={() => setShowCreate(true)}>
          <Plus size={18} />
          Add device
        </button>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="toolbar">
        <div className="search-box">
          <Search size={18} />
          <input
            placeholder="Search serial, model, name or status..."
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
                  <th>Device</th>
                  <th>Serial</th>
                  <th>Status</th>
                  <th>Firmware</th>
                  <th>Wi-Fi</th>
                  <th>Storage</th>
                  <th>Last seen</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {filtered.map((d) => (
                  <tr key={d.id}>
                    <td>
                      <strong>{d.name || d.model}</strong>
                      <span className="muted-cell">{d.model}</span>
                    </td>
                    <td className="mono">{d.serial_number}</td>
                    <td><StatusBadge status={d.status} /></td>
                    <td>{d.firmware_version || "—"}</td>
                    <td>{d.wifi_rssi ? `${d.wifi_rssi} dBm` : "—"}</td>
                    <td>
                      {typeof d.free_storage === "number"
                        ? `${(d.free_storage / 1024 / 1024).toFixed(1)} MB`
                        : "—"}
                    </td>
                    <td>{d.last_seen ? new Date(d.last_seen).toLocaleString() : "Never"}</td>
                    <td>
                      <div className="row-actions">
                        <button
                          className="icon-button"
                          title={d.status === "DISABLED" ? "Enable" : "Disable"}
                          onClick={() => toggleDisabled(d)}
                        >
                          {d.status === "DISABLED" ? (
                            <CheckCircle2 size={18} />
                          ) : (
                            <Ban size={18} />
                          )}
                        </button>
                        <button
                          className="icon-button danger-text"
                          title="Delete"
                          onClick={() => remove(d)}
                        >
                          <Trash2 size={18} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState
            icon={Cpu}
            title="No devices found"
            text="Add a factory device or change the search filter."
          />
        )}
      </div>

      {showCreate && (
        <Modal title="Add inventory device" onClose={() => setShowCreate(false)}>
          <form className="form-grid" onSubmit={createDevice}>
            <label>
              Serial number
              <input
                value={form.serial_number}
                onChange={(e) => setForm({ ...form, serial_number: e.target.value })}
                placeholder="LILY-000001"
                required
              />
            </label>

            <label>
              Device secret
              <input
                value={form.device_secret}
                onChange={(e) => setForm({ ...form, device_secret: e.target.value })}
                placeholder="At least 16 characters"
                minLength={16}
                required
              />
              <small>This must match the factory secret flashed to the ESP32.</small>
            </label>

            <div className="two-columns">
              <label>
                Model
                <input
                  value={form.model}
                  onChange={(e) => setForm({ ...form, model: e.target.value })}
                  required
                />
              </label>

              <label>
                Hardware version
                <input
                  value={form.hardware_version}
                  onChange={(e) => setForm({ ...form, hardware_version: e.target.value })}
                />
              </label>
            </div>

            <div className="modal-actions">
              <button type="button" className="secondary-button" onClick={() => setShowCreate(false)}>
                Cancel
              </button>
              <button className="primary-button">Create device</button>
            </div>
          </form>
        </Modal>
      )}
    </>
  );
}
