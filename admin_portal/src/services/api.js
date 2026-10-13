const API_BASE =
  import.meta.env.VITE_API_BASE_URL || "http://127.0.0.1:6100/api/v1";

async function request(path, options = {}) {
  const token = localStorage.getItem("lily_admin_token");

  const headers = {
    ...(options.body instanceof FormData ? {} : { "Content-Type": "application/json" }),
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...(options.headers || {}),
  };

  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers,
  });

  if (response.status === 401) {
    localStorage.removeItem("lily_admin_token");
    if (!path.includes("/auth/login")) {
      window.location.href = "/login";
    }
  }

  if (!response.ok) {
    let message = `Request failed (${response.status})`;
    try {
      const data = await response.json();
      message = data.detail || data.message || message;
    } catch {}
    throw new Error(message);
  }

  if (response.status === 204) return null;

  const contentType = response.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    return response.json();
  }
  return response;
}

export const api = {
  mobileSessionPolicy: () => request('/admin/mobile-session-policy'),
  setMobileSessionPolicy: (payload) => request('/admin/mobile-session-policy', {method:'PATCH',body:JSON.stringify(payload)}),
  login: (email, password) =>
    request("/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    }),

  me: () => request("/auth/me"),

  dashboard: () => request("/admin/dashboard"),
  homes: () => request("/admin/homes"),
  deviceTypes: () => request("/device-types"),
  createDeviceType: (payload) => request("/admin/device-types", {
    method: "POST",
    body: JSON.stringify(payload),
  }),
  users: () => request("/admin/users"),
  setUserActive: (userId, active) =>
    request(`/admin/users/${userId}/active`, {
      method: "PATCH",
      body: JSON.stringify({ active }),
    }),

  deviceCredentials: (id) => request(`/admin/device-inventory/${id}/credentials`),
  downloadDeviceConfig: (id) => request(`/admin/device-inventory/${id}/config`),
  resyncDevice: (id) => request(`/admin/device-inventory/${id}/resync`, {method:'POST'}),
  exportDevices: (fields) => request('/admin/devices/export.csv'+(fields ? '?fields='+encodeURIComponent(fields.join(',')) : '')),
  deviceModels: () => request('/admin/device-models'),
  deviceFeatures: () => request('/admin/device-features'),
  createDeviceModel: (payload) => request('/admin/device-models', {method:'POST',body:JSON.stringify(payload)}),
  updateDeviceModel: (key,payload) => request(`/admin/device-models/${encodeURIComponent(key)}`, {method:'PATCH',body:JSON.stringify(payload)}),
  deleteDeviceModel: (key) => request(`/admin/device-models/${encodeURIComponent(key)}`, {method:'DELETE'}),
  generateDevice: (payload) => request('/admin/device-inventory', {method: 'POST', body: JSON.stringify(payload)}),
  devices: () => request("/devices/admin/all"),
  createDevice: (payload) =>
    request("/devices/admin", {
      method: "POST",
      body: JSON.stringify(payload),
    }),
  setDeviceDisabled: (deviceId, disabled) =>
    request(`/devices/admin/${deviceId}/disabled`, {
      method: "PATCH",
      body: JSON.stringify({ disabled }),
    }),
  deleteDevice: (deviceId) =>
    request(`/devices/admin/${deviceId}`, { method: "DELETE" }),

  music: () => request("/music/admin/all"),
  uploadMusic: (formData) =>
    request("/music/admin/upload", {
      method: "POST",
      body: formData,
    }),
  setMusicEnabled: (musicId, enabled) =>
    request(`/music/admin/${musicId}/enabled`, {
      method: "PATCH",
      body: JSON.stringify({ enabled }),
    }),
  deleteMusic: (musicId) =>
    request(`/music/admin/${musicId}`, { method: "DELETE" }),
};

export { API_BASE };
