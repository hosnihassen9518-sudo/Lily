import PermissionGate from "../components/PermissionGate";
import React, { useEffect, useMemo, useState } from "react";
import {
  Plus,
  Search,
  RefreshCw,
  Trash2,
  Ban,
  CheckCircle2,
  Cpu,
  KeyRound,
  Download,
  FileSpreadsheet,
} from "lucide-react";
import { api } from "../services/api";
import StatusBadge from "../components/StatusBadge";
import Modal from "../components/Modal";
import EmptyState from "../components/EmptyState";

export default function DevicesPage({ inventoryOnly = false }) {
  const [devices, setDevices] = useState([]);
  const [query, setQuery] = useState("");
  const [showCreate, setShowCreate] = useState(false);
  const [error, setError] = useState("");
  const [types, setTypes] = useState([]);
  const [models, setModels] = useState([]);
  const [generated, setGenerated] = useState(null);
  const [creating, setCreating] = useState(false);
  const [credentials, setCredentials] = useState(null);
  const [showExport, setShowExport] = useState(false);
  const exportFields = [
    "id",
    "serial_number",
    "name",
    "model",
    "hardware_version",
    "status",
    "owner_id",
    "device_type",
    "home_id",
    "room_id",
    "firmware_version",
    "online",
    "last_seen",
    "last_connected_at",
    "last_disconnected_at",
    "activated_at",
    "created_at",
    "wifi_rssi",
    "free_heap",
    "free_storage",
    "light_enabled",
    "brightness",
    "color_r",
    "color_g",
    "color_b",
    "audio_loaded",
    "audio_playing",
    "volume",
    "device_secret",
  ];
  const [columns, setColumns] = useState([
    "serial_number",
    "name",
    "model",
    "device_type",
    "status",
    "owner_id",
    "last_seen",
  ]);
  const [notice, setNotice] = useState("");
  function download(text, filename, type = "text/plain") {
    const url = URL.createObjectURL(new Blob([text], { type }));
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  async function showCredentials(d) {
    try {
      setCredentials(await api.deviceCredentials(d.id));
    } catch (err) {
      setError(err.message);
    }
  }
  async function downloadConfig(d) {
    try {
      const response = await api.downloadDeviceConfig(d.id);
      download(await response.text(), d.serial_number + "-device_config.h");
    } catch (err) {
      setError(err.message);
    }
  }
  async function resync(d) {
    try {
      const result = await api.resyncDevice(d.id);
      setNotice(result.detail);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }
  async function exportCsv() {
    try {
      const response = await api.exportDevices(columns);
      download(await response.text(), "lily-devices.csv", "text/csv");
      setShowExport(false);
    } catch (err) {
      setError(err.message);
    }
  }
  const [form, setForm] = useState({ device_type_id: "", model_key: "" });
  async function refreshCatalog() {
    try {
      const [t, m] = await Promise.all([api.deviceTypes(), api.deviceModels()]);
      setTypes(t);
      setModels(m);
      setForm((current) =>
        m.some(
          (model) =>
            model.key === current.model_key &&
            model.device_type_id === Number(current.device_type_id),
        )
          ? current
          : { ...current, model_key: "" },
      );
    } catch (err) {
      setError(err.message);
    }
  }
  useEffect(() => {
    Promise.all([api.deviceTypes(), api.deviceModels()])
      .then(([t, m]) => {
        setTypes(t);
        setModels(m);
      })
      .catch((err) => setError(err.message));
  }, []);
  function downloadHeader() {
    const url = URL.createObjectURL(
      new Blob([generated.config_header], { type: "text/plain" }),
    );
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = generated.filename;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  async function load() {
    try {
      setError("");
      setDevices(
        await (inventoryOnly ? api.access("/admin/inventory") : api.devices()),
      );
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
        .some((v) => String(v).toLowerCase().includes(q)),
    );
  }, [devices, query]);

  async function createDevice(e) {
    e.preventDefault();
    if (creating) return;
    setCreating(true);
    setError("");
    try {
      setGenerated(
        await api.generateDevice({
          ...form,
          device_type_id: Number(form.device_type_id),
        }),
      );
      await load();
    } catch (err) {
      setError(err.message);
    } finally {
      setCreating(false);
    }
  }

  async function toggleDisabled(d) {
    const disabled = d.status !== "DISABLED";
    if (!confirm(`${disabled ? "Disable" : "Enable"} ${d.serial_number}?`))
      return;
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
          <h1>{inventoryOnly ? "Inventory" : "Devices"}</h1>
          <p>Manage factory inventory and monitor deployed devices.</p>
        </div>
        <PermissionGate permission="inventory.create" action>
          <button
            className="primary-button"
            onClick={() => {
              setShowCreate(true);
              refreshCatalog();
            }}
          >
            <Plus size={18} />
            Add device
          </button>
        </PermissionGate>
      </div>

      {error && <div className="alert error">{error}</div>}
      {notice && <div className="alert success">{notice}</div>}

      <div className="toolbar">
        <div className="search-box">
          <Search size={18} />
          <input
            placeholder="Search serial, model, name or status..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <PermissionGate permission="devices.export" action>
          <button
            className="secondary-button"
            onClick={() => {
              setCredentials(null);
              setShowExport(true);
            }}
          >
            <FileSpreadsheet size={17} />
            Export CSV
          </button>
        </PermissionGate>
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
                    <td>
                      <StatusBadge status={d.status} />
                    </td>
                    <td>{d.firmware_version || "—"}</td>
                    <td>{d.wifi_rssi ? `${d.wifi_rssi} dBm` : "—"}</td>
                    <td>
                      {typeof d.free_storage === "number"
                        ? `${(d.free_storage / 1024 / 1024).toFixed(1)} MB`
                        : "—"}
                    </td>
                    <td>
                      {d.last_seen
                        ? new Date(d.last_seen).toLocaleString()
                        : "Never"}
                    </td>
                    <td>
                      <div className="row-actions">
                        <PermissionGate
                          permission="inventory.export_secrets"
                          action
                        >
                          <button
                            className="icon-button"
                            title="Show credentials"
                            onClick={() => showCredentials(d)}
                          >
                            <KeyRound size={18} />
                          </button>
                        </PermissionGate>
                        <PermissionGate
                          permission="inventory.export_secrets"
                          action
                        >
                          <button
                            className="icon-button"
                            title="Download config file"
                            onClick={() => downloadConfig(d)}
                          >
                            <Download size={18} />
                          </button>
                        </PermissionGate>
                        <PermissionGate permission="inventory.change" action>
                          <button
                            className="icon-button"
                            title="Resync"
                            disabled={
                              !d.online ||
                              d.status === "RESET_PENDING" ||
                              d.status === "DISABLED"
                            }
                            onClick={() => resync(d)}
                          >
                            <RefreshCw size={18} />
                          </button>
                        </PermissionGate>
                        <PermissionGate permission="devices.change" action>
                          <button
                            className="icon-button"
                            title={
                              d.status === "DISABLED" ? "Enable" : "Disable"
                            }
                            onClick={() => toggleDisabled(d)}
                          >
                            {d.status === "DISABLED" ? (
                              <CheckCircle2 size={18} />
                            ) : (
                              <Ban size={18} />
                            )}
                          </button>
                        </PermissionGate>
                        <PermissionGate permission="devices.delete" action>
                          <button
                            className="icon-button danger-text"
                            title="Remove device"
                            onClick={() => remove(d)}
                          >
                            <Trash2 size={18} />
                          </button>
                        </PermissionGate>
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

      {credentials && (
        <Modal title="Device credentials" onClose={() => setCredentials(null)}>
          <div className="form-grid">
            <label>
              Serial number
              <input readOnly value={credentials.serial_number} />
            </label>
            <label>
              Device secret
              <input
                className="mono"
                readOnly
                value={credentials.device_secret}
              />
            </label>
            <p>Only share these with the device you are configuring.</p>
          </div>
        </Modal>
      )}
      {showExport && (
        <Modal title="Choose fields" wide onClose={() => setShowExport(false)}>
          <div className="form-grid">
            <p>
              Select columns for the CSV. Older devices may have no recoverable
              secret.
            </p>
            <button
              className="secondary-button"
              onClick={() =>
                setColumns(exportFields.filter((f) => f !== "device_secret"))
              }
            >
              All standard information
            </button>
            <button
              className="secondary-button"
              onClick={() => setColumns(exportFields)}
            >
              All fields, including device secret
            </button>
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit,minmax(180px,1fr))",
                gap: 8,
              }}
            >
              {exportFields.map((field) => (
                <label
                  key={field}
                  style={{ display: "flex", gap: 8, alignItems: "center" }}
                >
                  <input
                    type="checkbox"
                    style={{ width: "auto" }}
                    checked={columns.includes(field)}
                    onChange={(e) =>
                      setColumns(
                        e.target.checked
                          ? [...columns, field]
                          : columns.filter((c) => c !== field),
                      )
                    }
                  />
                  {field.replaceAll("_", " ")}
                </label>
              ))}
            </div>
            <PermissionGate permission="devices.export" action>
              <button
                className="primary-button"
                disabled={!columns.length}
                onClick={exportCsv}
              >
                Download CSV
              </button>
            </PermissionGate>
          </div>
        </Modal>
      )}
      {showCreate && (
        <Modal
          title="Add inventory device"
          onClose={() => {
            if (!creating) setShowCreate(false);
          }}
        >
          {generated ? (
            <div className="form-grid">
              <strong>{generated.serial_number}</strong>
              <label>
                Device secret
                <input
                  className="mono"
                  readOnly
                  value={generated.device_secret || ""}
                />
              </label>
              <p>
                Keep the configuration private. You can retrieve it again from
                the device actions.
              </p>
              <p>
                Copy it to the selected firmware target as
                include/device_config.h, then build and upload with PlatformIO.
              </p>
              <PermissionGate permission="inventory.export_secrets" action>
                <button className="primary-button" onClick={downloadHeader}>
                  Download ESP32 configuration
                </button>
              </PermissionGate>
              <PermissionGate permission="inventory.create" action>
                <button
                  className="secondary-button"
                  onClick={() => {
                    setGenerated(null);
                  }}
                >
                  Create another device
                </button>
              </PermissionGate>
            </div>
          ) : (
            <form className="form-grid" onSubmit={createDevice}>
              <label>
                Device type
                <select
                  required
                  value={form.device_type_id}
                  onChange={(e) =>
                    setForm({ device_type_id: e.target.value, model_key: "" })
                  }
                >
                  <option value="">Select a type</option>
                  {types.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Model
                <select
                  required
                  value={form.model_key}
                  onChange={(e) =>
                    setForm({ ...form, model_key: e.target.value })
                  }
                >
                  <option value="">Select a compatible model</option>
                  {models
                    .filter(
                      (m) => m.device_type_id === Number(form.device_type_id),
                    )
                    .map((m) => (
                      <option key={m.key} value={m.key}>
                        {m.name}
                      </option>
                    ))}
                </select>
              </label>
              {form.device_type_id &&
                !models.some(
                  (m) => m.device_type_id === Number(form.device_type_id),
                ) && (
                  <p>No supported firmware model is available for this type.</p>
                )}
              <div className="modal-actions">
                <PermissionGate permission="inventory.create" action>
                  <button
                    type="button"
                    className="secondary-button"
                    disabled={creating}
                    onClick={() => setShowCreate(false)}
                  >
                    Cancel
                  </button>
                </PermissionGate>
                <PermissionGate permission="inventory.create" action>
                  <button className="primary-button" disabled={creating}>
                    {creating ? "Creating…" : "Generate device"}
                  </button>
                </PermissionGate>
              </div>
            </form>
          )}
        </Modal>
      )}
    </>
  );
}
