import React, { useEffect, useMemo, useState } from "react";
import {
  Music2,
  Upload,
  Search,
  Trash2,
  Eye,
  EyeOff,
  RefreshCw,
} from "lucide-react";
import { api } from "../services/api";
import Modal from "../components/Modal";
import EmptyState from "../components/EmptyState";

function formatBytes(bytes) {
  if (!bytes && bytes !== 0) return "—";
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

export default function MusicPage() {
  const [tracks, setTracks] = useState([]);
  const [query, setQuery] = useState("");
  const [showUpload, setShowUpload] = useState(false);
  const [error, setError] = useState("");
  const [uploading, setUploading] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [file, setFile] = useState(null);

  async function load() {
    try {
      setError("");
      setTracks(await api.music());
    } catch (err) {
      setError(err.message);
    }
  }

  useEffect(() => {
    load();
  }, []);

  const filtered = useMemo(() => {
    const q = query.toLowerCase();
    return tracks.filter((t) =>
      [t.title, t.description, t.filename]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(q))
    );
  }, [tracks, query]);

  async function submitUpload(e) {
    e.preventDefault();
    if (!file) return;

    const data = new FormData();
    data.append("title", title);
    data.append("description", description);
    data.append("file", file);

    setUploading(true);
    try {
      await api.uploadMusic(data);
      setShowUpload(false);
      setTitle("");
      setDescription("");
      setFile(null);
      await load();
    } catch (err) {
      setError(err.message);
    } finally {
      setUploading(false);
    }
  }

  async function toggle(track) {
    try {
      await api.setMusicEnabled(track.id, !track.enabled);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  async function remove(track) {
    if (!confirm(`Delete "${track.title}" and its MP3 file?`)) return;
    try {
      await api.deleteMusic(track.id);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <h1>Music library</h1>
          <p>Tracks available for users to download and transfer to their device.</p>
        </div>
        <button className="primary-button" onClick={() => setShowUpload(true)}>
          <Upload size={18} />
          Upload MP3
        </button>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="toolbar">
        <div className="search-box">
          <Search size={18} />
          <input
            placeholder="Search music..."
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
                  <th>Track</th>
                  <th>File</th>
                  <th>Size</th>
                  <th>Availability</th>
                  <th>SHA-256</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {filtered.map((track) => (
                  <tr key={track.id}>
                    <td>
                      <strong>{track.title}</strong>
                      <span className="muted-cell">{track.description || "No description"}</span>
                    </td>
                    <td>{track.filename}</td>
                    <td>{formatBytes(track.filesize)}</td>
                    <td>
                      <span className={`status-badge ${track.enabled ? "success" : "neutral"}`}>
                        {track.enabled ? "AVAILABLE" : "HIDDEN"}
                      </span>
                    </td>
                    <td className="mono checksum">{track.checksum_sha256}</td>
                    <td>
                      <div className="row-actions">
                        <button className="icon-button" onClick={() => toggle(track)}>
                          {track.enabled ? <EyeOff size={18} /> : <Eye size={18} />}
                        </button>
                        <button className="icon-button danger-text" onClick={() => remove(track)}>
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
            icon={Music2}
            title="No music found"
            text="Upload an MP3 to make it available to the mobile application."
          />
        )}
      </div>

      {showUpload && (
        <Modal title="Upload MP3" onClose={() => setShowUpload(false)}>
          <form className="form-grid" onSubmit={submitUpload}>
            <label>
              Title
              <input value={title} onChange={(e) => setTitle(e.target.value)} required />
            </label>

            <label>
              Description
              <textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={3}
              />
            </label>

            <label>
              MP3 file
              <input
                type="file"
                accept=".mp3,audio/mpeg"
                onChange={(e) => setFile(e.target.files?.[0] || null)}
                required
              />
            </label>

            <div className="modal-actions">
              <button type="button" className="secondary-button" onClick={() => setShowUpload(false)}>
                Cancel
              </button>
              <button className="primary-button" disabled={uploading}>
                {uploading ? "Uploading..." : "Upload"}
              </button>
            </div>
          </form>
        </Modal>
      )}
    </>
  );
}
