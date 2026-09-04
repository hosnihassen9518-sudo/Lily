import React, { createContext, useContext, useEffect, useMemo, useState } from "react";
import { api } from "../services/api";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  async function refreshUser() {
    const token = localStorage.getItem("lily_admin_token");
    if (!token) {
      setUser(null);
      setLoading(false);
      return;
    }

    try {
      const me = await api.me();
      if (!me.is_admin) {
        localStorage.removeItem("lily_admin_token");
        setUser(null);
      } else {
        setUser(me);
      }
    } catch {
      setUser(null);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refreshUser();
  }, []);

  async function login(email, password) {
    const result = await api.login(email, password);
    localStorage.setItem("lily_admin_token", result.access_token);
    const me = await api.me();

    if (!me.is_admin) {
      localStorage.removeItem("lily_admin_token");
      throw new Error("This account is not an administrator.");
    }

    setUser(me);
    return me;
  }

  function logout() {
    localStorage.removeItem("lily_admin_token");
    setUser(null);
  }

  const value = useMemo(
    () => ({ user, loading, login, logout, refreshUser }),
    [user, loading]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  return useContext(AuthContext);
}
