import React from "react";
export default function PermissionMatrix({
  catalog = {},
  value = [],
  onChange,
  disabled = false,
  allowed,
}) {
  const actions = [...new Set(Object.values(catalog).flat())];
  function toggle(p, checked) {
    onChange(checked ? [...value, p] : value.filter((x) => x !== p));
  }
  return (
    <div className="table-wrap">
      <table className="permission-matrix">
        <thead>
          <tr>
            <th>Feature</th>
            {actions.map((a) => (
              <th key={a}>{a.replaceAll("_", " ")}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {Object.entries(catalog).map(([resource, verbs]) => (
            <tr key={resource}>
              <th>{resource.replaceAll("_", " ")}</th>
              {actions.map((a) => (
                <td key={a}>
                  {verbs.includes(a) ? (
                    <input
                      type="checkbox"
                      aria-label={`${resource}.${a}`}
                      checked={value.includes(`${resource}.${a}`)}
                      disabled={
                        disabled ||
                        (allowed && !allowed.includes(`${resource}.${a}`))
                      }
                      onChange={(e) =>
                        toggle(`${resource}.${a}`, e.target.checked)
                      }
                    />
                  ) : (
                    <span aria-hidden="true">—</span>
                  )}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
