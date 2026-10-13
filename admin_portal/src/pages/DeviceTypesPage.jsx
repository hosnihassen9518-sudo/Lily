import React, { useEffect, useState } from "react";
import { api } from "../services/api";

export default function DeviceTypesPage() {
  const [rows, setRows] = useState([]);
  const [error, setError] = useState("");
  const [notice,setNotice] = useState("");
  const [key, setKey] = useState("");
  const [name, setName] = useState("");
  const [caps, setCaps] = useState("");
  const [models, setModels] = useState([]);
  const [features, setFeatures] = useState([]);
  const emptyModel = {key:'',name:'',device_type_id:'',hardware_version:'1.0',firmware_target:'esp32_device',capabilities:[]};
  const [model,setModel] = useState(emptyModel);
  const [editing,setEditing] = useState(false);
  const [deleting,setDeleting] = useState(null);
  const [busy,setBusy] = useState(false);
  const [ready,setReady] = useState(false);

  async function load() { try { setError(""); const [types,models,features] = await Promise.all([api.deviceTypes(),api.deviceModels(),api.deviceFeatures()]); setRows(types);setModels(models);setFeatures(features);setReady(true); } catch (e) { setError(e.message); } }
  useEffect(() => { load(); }, []);

  function toggleFeature(key,checked) {
    setModel(current=>{
      const selected=new Set(current.capabilities);
      if (checked) {selected.add(key);if (['brightness','rgb'].includes(key)) {selected.add('light');selected.add('power');}if(key==='light')selected.add('power');if(key==='volume') selected.add('audio');}
      else {selected.delete(key);if(key==='power'){selected.delete('light');selected.delete('brightness');selected.delete('rgb');}if(key==='light'){selected.delete('brightness');selected.delete('rgb');}if(key==='audio')selected.delete('volume');}
      return {...current,capabilities:features.map(f=>f.key).filter(k=>selected.has(k))};
    });
  }
  async function saveModel(e) {
    e.preventDefault();if(busy)return;setBusy(true);setError('');setNotice('');
    try {
      const {key,...fields}=model;const payload={...fields,device_type_id:Number(model.device_type_id)};
      const response=editing?await api.updateDeviceModel(key,payload):await api.createDeviceModel({key,...payload});
      setModel(emptyModel);setEditing(false);await load();
      if(response?.schedule_sync_pending?.length)setNotice('Model saved. Schedule updates are waiting for the server or devices to reconnect.');
    }catch(e){setError(e.message);}finally{setBusy(false);}
  }
  async function deleteModel() {
    if(busy)return;setBusy(true);setError('');
    try {await api.deleteDeviceModel(deleting.key);if(model.key===deleting.key){setModel(emptyModel);setEditing(false);}setDeleting(null);await load();}
    catch(e){setError(e.message);}finally{setBusy(false);}
  }

  async function create(e) {
    e.preventDefault();
    try {
      await api.createDeviceType({ key, name, capabilities: caps.split(",").map(v => v.trim()).filter(Boolean) });
      setKey(""); setName(""); setCaps(""); await load();
    } catch (e) { setError(e.message); }
  }

  return <>
    <div className="page-heading"><div><h1>Models & features</h1><p>Choose the controls supported by each hardware model.</p></div></div>
    {error && <div className="alert error" role="alert">{error}</div>}
    {notice&&<div className="alert" role="status">{notice}</div>}
    <div className="panel" style={{marginBottom:20}}>
      <div className="panel-header"><div><h2>{editing?'Edit model':'Add model'}</h2><p>Model keys identify factory devices and cannot be changed.</p></div></div>
      <form onSubmit={saveModel} className="form-grid" style={{padding:20}}>
        <label>Model key<input required maxLength={80} disabled={editing||busy} value={model.key} onChange={e=>setModel({...model,key:e.target.value})}/></label>
        <label>Model name<input required maxLength={80} disabled={busy} value={model.name} onChange={e=>setModel({...model,name:e.target.value})}/></label>
        <label>Device type<select required disabled={busy} value={model.device_type_id} onChange={e=>setModel({...model,device_type_id:e.target.value})}><option value="">Choose type</option>{rows.map(t=><option key={t.id} value={t.id}>{t.name}</option>)}</select></label>
        <label>Hardware version<input required disabled={busy} value={model.hardware_version} onChange={e=>setModel({...model,hardware_version:e.target.value})}/></label>
        <label>Firmware target<select disabled={busy} value={model.firmware_target} onChange={e=>setModel({...model,firmware_target:e.target.value})}><option value="esp32_device">ESP32 device</option><option value="esp32_test_light">ESP32 test light</option></select></label>
        <fieldset style={{gridColumn:'1 / -1'}} disabled={busy||!ready}><legend>Supported features</legend><p>Light requires Power. Brightness and RGB require Light. Volume requires Audio. Selecting these features also selects their prerequisite. Removing a prerequisite removes its dependent features. No selection enables no controls.</p><div className="model-features">{features.map(f=><label key={f.key}><input type="checkbox" aria-label={f.name} checked={model.capabilities.includes(f.key)} onChange={e=>toggleFeature(f.key,e.target.checked)}/><span><strong>{f.name}</strong><small>{f.description}</small></span></label>)}</div></fieldset>
        <div><button className="primary-button" disabled={busy||!ready} type="submit">{busy?'Saving…':editing?'Save model':'Create model'}</button>{editing&&<button className="secondary-button" disabled={busy} type="button" onClick={()=>{setModel(emptyModel);setEditing(false);}}>Cancel edit</button>}</div>
      </form>
    </div>
    {deleting&&<div className="panel" style={{padding:20,marginBottom:20}} role="alertdialog" aria-label="Delete model"><p>Delete {deleting.name}? Models used by devices cannot be deleted.</p><button className="danger-button" disabled={busy} onClick={deleteModel}>Confirm delete</button><button className="secondary-button" disabled={busy} onClick={()=>setDeleting(null)}>Cancel deletion</button></div>}
    <div className="panel" style={{marginBottom:20}}><div className="table-wrap"><table><thead><tr><th>Model</th><th>Type</th><th>Hardware / firmware</th><th>Features</th><th>Actions</th></tr></thead><tbody>{models.map(m=><tr key={m.key}><td><strong>{m.name}</strong><div className="mono">{m.key}</div></td><td>{rows.find(t=>t.id===m.device_type_id)?.name||m.device_type_id}</td><td>{m.hardware_version}<div>{m.firmware_target}</div></td><td>{m.capabilities?.join(', ')||'No controls'}</td><td><button disabled={busy} aria-label={`Edit ${m.name}`} onClick={()=>{setModel({...m,capabilities:[...(m.capabilities||[])]});setEditing(true);setError('');}}>Edit</button><button disabled={busy} aria-label={`Delete ${m.name}`} onClick={()=>setDeleting(m)}>Delete</button></td></tr>)}{!models.length&&<tr><td colSpan="5" className="empty-row">{ready?'No device models.':'Loading models…'}</td></tr>}</tbody></table></div></div>
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
