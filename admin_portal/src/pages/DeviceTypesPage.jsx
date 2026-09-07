import React, { useEffect, useState } from "react";
import { api } from "../services/api";

export default function DeviceTypesPage() {
  const [rows, setRows] = useState([]);
  const [error, setError] = useState("");
  const [key, setKey] = useState("");
  const [name, setName] = useState("");
  const [caps, setCaps] = useState("");

  async function load() { try { setError(""); setRows(await api.deviceTypes()); } catch (e) { setError(e.message); } }
  useEffect(() => { load(); }, []);

  async function create(e) {
    e.preventDefault();
    try {
      await api.createDeviceType({ key, name, capabilities: caps.split(",").map(v => v.trim()).filter(Boolean) });
      setKey(""); setName(""); setCaps(""); await load();
    } catch (e) { setError(e.message); }
  }

  return <>
    <div className="page-heading"><div><h1>Device Types</h1><p>Define generic hardware classes and their capabilities.</p></div></div>
    {error && <div className="alert error">{error}</div>}
    <div className="panel" style={{marginBottom: 20}}><div className="panel-header"><div><h2>Add device type</h2><p>Capabilities are comma separated, for example power, brightness, rgb.</p></div></div>
      <form onSubmit={create} className="form-grid" style={{padding: 20}}>
        <label>Key<input value={key} onChange={e=>setKey(e.target.value)} placeholder="smart_light" required/></label>
        <label>Name<input value={name} onChange={e=>setName(e.target.value)} placeholder="Smart Light" required/></label>
        <label style={{gridColumn:'1 / -1'}}>Capabilities<input value={caps} onChange={e=>setCaps(e.target.value)} placeholder="power, brightness, rgb"/></label>
        <div><button className="primary-button" type="submit">Create type</button></div>
      </form>
    </div>
    <div className="panel"><div className="table-wrap"><table><thead><tr><th>Name</th><th>Key</th><th>Capabilities</th></tr></thead>
      <tbody>{rows.map(t=><tr key={t.id}><td><strong>{t.name}</strong></td><td className="mono">{t.key}</td><td>{t.capabilities.join(", ") || "—"}</td></tr>)}{!rows.length&&<tr><td colSpan="3" className="empty-row">No device types.</td></tr>}</tbody>
    </table></div></div>
  </>;
}
