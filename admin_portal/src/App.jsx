import React from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { useAuth } from "./context/AuthContext";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import DevicesPage from "./pages/DevicesPage";
import UsersPage from "./pages/AccessUsersPage";
import RolesPage from "./pages/RolesPage";
import ApiAccessPage from "./pages/ApiAccessPage";
import SessionsPage from "./pages/SessionsPage";
import AuditPage from "./pages/AuditPage";
import PermissionGate from "./components/PermissionGate";
import MusicPage from "./pages/MusicPage";
import HomesPage from "./pages/HomesPage";
import DeviceTypesPage from "./pages/DeviceTypesPage";
import Layout from "./components/Layout";
import SettingsPage from "./pages/SettingsPage";

function Protected({ children }) {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div className="center-screen">
        <div className="spinner" />
      </div>
    );
  }

  return user ? children : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      <Route
        path="/"
        element={
          <Protected>
            <Layout />
          </Protected>
        }
      >
        <Route
          index
          element={
            <PermissionGate permission="dashboard.read" denial>
              <DashboardPage />
            </PermissionGate>
          }
        />
        <Route
          path="devices"
          element={
            <PermissionGate permission="devices.read" denial>
              <DevicesPage />
            </PermissionGate>
          }
        />
        <Route
          path="inventory"
          element={
            <PermissionGate permission="inventory.read" denial>
              <DevicesPage inventoryOnly />
            </PermissionGate>
          }
        />
        <Route
          path="homes"
          element={
            <PermissionGate permission="homes.read" denial>
              <HomesPage />
            </PermissionGate>
          }
        />
        <Route
          path="device-types"
          element={
            <PermissionGate permission="models.read" denial>
              <DeviceTypesPage />
            </PermissionGate>
          }
        />
        <Route
          path="users"
          element={
            <PermissionGate permission="users.read" denial>
              <UsersPage />
            </PermissionGate>
          }
        />
        <Route
          path="music"
          element={
            <PermissionGate permission="music.read" denial>
              <MusicPage />
            </PermissionGate>
          }
        />
        <Route
          path="roles"
          element={
            <PermissionGate permission="roles.read" denial>
              <RolesPage />
            </PermissionGate>
          }
        />
        <Route
          path="api-roles"
          element={
            <PermissionGate permission="api_roles.read" denial>
              <RolesPage audience="api" />
            </PermissionGate>
          }
        />
        <Route
          path="api-access"
          element={
            <PermissionGate permission="api_credentials.read" denial>
              <ApiAccessPage />
            </PermissionGate>
          }
        />
        <Route path="sessions" element={<SessionsPage />} />
        <Route
          path="audit"
          element={
            <PermissionGate permission="audit.read" denial>
              <AuditPage />
            </PermissionGate>
          }
        />
        <Route
          path="settings"
          element={
            <PermissionGate permission="settings.read" denial>
              <SettingsPage />
            </PermissionGate>
          }
        />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
