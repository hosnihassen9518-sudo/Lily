import React, { useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";
import { api } from "../services/api";

export default function HomesPage() {
  const [rows, setRows] = useState([]);
  const [error, setError] = useState("");

  async function load() {
    try {
      setError("");
      setRows(await api.homes());
    } catch (err) { setError(err.message); }
  }

  useEffect(() => { load(); }, []);

  return <>
    <div className="page-heading">
      <div><h1>Homes</h1><p>Smart-home containers registered by platform users.</p></div>
      <button className="secondary-button" onClick={load}><RefreshCw size={17}/>Refresh</button>
    </div>
    {error && <div className="alert error">{error}</div>}
    <div className="panel"><div className="table-wrap"><table>
      <thead><tr><th>Home</th><th>Owner</th><th>Timezone</th><th>Rooms</th><th>Devices</th><th>Created</th></tr></thead>
      <tbody>{rows.map(h => <tr key={h.id}>
        <td><strong>{h.name}</strong></td><td>{h.owner_email || `User ${h.owner_id}`}</td><td>{h.timezone}</td><td>{h.rooms}</td><td>{h.devices}</td><td>{new Date(h.created_at).toLocaleString()}</td>
      </tr>)}{!rows.length && <tr><td colSpan="6" className="empty-row">No homes yet.</td></tr>}</tbody>
    </table></div></div>
  </>;
}
