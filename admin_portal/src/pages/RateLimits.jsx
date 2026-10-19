import React, { useEffect, useState } from "react";
import { api } from "../services/api";
import { useAuth } from "../context/AuthContext";
export default function RateLimits() {
  const { can } = useAuth();
  const [values, setValues] = useState(null),
    [message, setMessage] = useState(""),
    [busy, setBusy] = useState(false);
  useEffect(() => {
    api
      .access("/access/rate-limits")
      .then(setValues)
      .catch((e) => setMessage(e.message));
  }, []);
  return (
    <section className="panel access-panel">
      <h2>Rate limits</h2>
      <p>
        Limits apply across sessions and backend workers. Only a superuser can
        increase ceilings.
      </p>
      {message && (
        <div role="status" className="alert">
          {message}
        </div>
      )}
      {values && (
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            try {
              await api.access("/access/rate-limits", "PUT", values);
              setMessage("Rate limits saved.");
            } catch (e) {
              setMessage(e.message);
            } finally {
              setBusy(false);
            }
          }}
        >
          <fieldset
            disabled={!can("settings.change") || busy}
            style={{ border: 0, padding: 0 }}
          >
            <div className="form-grid">
              {Object.entries(values).map(([key, value]) => (
                <label key={key}>
                  {key.replaceAll("_", " ")}
                  {key === "login_account" ? " / 15 minutes" : " / minute"}
                  <input
                    required
                    type="number"
                    min="1"
                    max="100000"
                    value={value}
                    onChange={(e) =>
                      setValues({ ...values, [key]: Number(e.target.value) })
                    }
                  />
                </label>
              ))}
            </div>
            <button className="primary-button">Save rate limits</button>
          </fieldset>
        </form>
      )}
    </section>
  );
}
