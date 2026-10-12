import React, {useEffect, useState} from 'react';
import {api} from '../services/api';
export default function SettingsPage() {
  const [months,setMonths]=useState(3);
  const [busy,setBusy]=useState(true);
  const [message,setMessage]=useState('');
  useEffect(() => { api.mobileSessionPolicy().then(p=>setMonths(p.months)).catch(e=>setMessage(e.message)).finally(()=>setBusy(false)); },[]);
  async function save(e) {
    e.preventDefault(); setBusy(true); setMessage('');
    try { const saved=await api.setMobileSessionPolicy({months:Number(months)}); setMonths(saved.months); setMessage('Settings saved.'); }
    catch(e) { setMessage(e.message); } finally { setBusy(false); }
  }
  return <><div className="page-heading"><h1>Settings</h1></div><form className="panel form-grid" onSubmit={save}>
    <h2>Mobile login duration</h2>
    <p>Users stay signed in for this many months after login. The default is three months. Changes apply to future logins; existing sessions keep their expiry date.</p>
    <label>Months<input type="number" min="1" max="12" step="1" required value={months} onChange={e=>setMonths(e.target.value)}/></label>
    <button className="primary-button" disabled={busy}>Save</button>
    {message && <p role="status">{message}</p>}
  </form></>;
}
