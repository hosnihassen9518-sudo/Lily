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
  const [types, setTypes] = useState([]);
  const [models, setModels] = useState([]);
  const [generated, setGenerated] = useState(null);
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({device_type_id: '', model_key: ''});
  useEffect(() => {
    Promise.all([api.deviceTypes(), api.deviceModels()]).then(([t, m]) => {
      setTypes(t); setModels(m);
    }).catch(err => setError(err.message));
  }, []);
  function downloadHeader() {
    const url = URL.createObjectURL(new Blob([generated.config_header], {type: 'text/plain'}));
    const anchor = document.createElement('a');
    anchor.href = url; anchor.download = generated.filename; anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

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
    if (creating) return;
    setCreating(true); setError('');
    try {
      setGenerated(await api.generateDevice({...form, device_type_id: Number(form.device_type_id)}));
      await load();
    } catch (err) { setError(err.message); }
    finally { setCreating(false); }
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
        <Modal title="Add inventory device" onClose={() => { if (!creating) setShowCreate(false); }}>
          {generated ? <div className="form-grid">
            <strong>{generated.serial_number}</strong>
            <p>Save this file now. The device secret cannot be retrieved later.</p>
            <p>Copy it to the selected firmware target as include/device_config.h, then build and upload with PlatformIO.</p>
            <button className="primary-button" onClick={downloadHeader}>Download ESP32 configuration</button>
            <button className="secondary-button" onClick={() => { if (confirm("Have you saved the configuration file? Its secret cannot be retrieved later.")) setGenerated(null); }}>Create another device</button>
          </div> : <form className="form-grid" onSubmit={createDevice}>
            <label>Device type
              <select required value={form.device_type_id} onChange={e => setForm({device_type_id: e.target.value, model_key: ''})}>
                <option value="">Select a type</option>
                {types.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
              </select>
            </label>
            <label>Model
              <select required value={form.model_key} onChange={e => setForm({...form, model_key: e.target.value})}>
                <option value="">Select a compatible model</option>
                {models.filter(m => m.device_type_id === Number(form.device_type_id)).map(m => <option key={m.key} value={m.key}>{m.name}</option>)}
              </select>
            </label>
            {form.device_type_id && !models.some(m => m.device_type_id === Number(form.device_type_id)) && <p>No supported firmware model is available for this type.</p>}
            <div className="modal-actions">
              <button type="button" className="secondary-button" disabled={creating} onClick={() => setShowCreate(false)}>Cancel</button>
              <button className="primary-button" disabled={creating}>{creating ? 'Creating…' : 'Generate device'}</button>
            </div>
          </form>}
        </Modal>
      )}
    </>
  );
}
