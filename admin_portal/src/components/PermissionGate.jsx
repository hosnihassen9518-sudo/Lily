import React from "react";
import { useAuth } from "../context/AuthContext";
export default function PermissionGate({
  permission,
  children,
  action = false,
  denial = false,
}) {
  const auth = useAuth();
  const allowed = auth?.can(permission) === true;
  if (action)
    return (
      <fieldset
        className="permission-action"
        disabled={!allowed}
        title={allowed ? undefined : "Your role does not allow this action."}
      >
        {children}
      </fieldset>
    );
  return allowed ? (
    children
  ) : denial ? (
    <div className="panel access-panel" role="alert">
      <h1>Access unavailable</h1>
      <p>
        Your role does not allow this feature. Ask your administrator for
        access.
      </p>
    </div>
  ) : null;
}
