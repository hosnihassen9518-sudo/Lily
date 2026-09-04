const API_BASE =
  import.meta.env.VITE_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

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
  login: (email, password) =>
    request("/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    }),

  me: () => request("/auth/me"),

  dashboard: () => request("/admin/dashboard"),
  users: () => request("/admin/users"),
  setUserActive: (userId, active) =>
    request(`/admin/users/${userId}/active`, {
      method: "PATCH",
      body: JSON.stringify({ active }),
    }),

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
