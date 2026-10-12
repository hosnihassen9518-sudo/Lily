# Admin Portal

React/Vite administration interface for Lily Device Platform.

## Features

- Administrator login
- Dashboard counters
- Automatic online/offline device refresh
- Device inventory
- Add factory device with serial + device secret
- Disable / re-enable device
- Delete unneeded device
- User management
- Disable / re-enable users
- Music library
- Upload MP3 files
- Hide / publish music
- Delete MP3 and database record
- Responsive layout

## Requirements

- Node.js 20+ recommended
- Lily FastAPI backend running on port 6100

## Start on Windows

```powershell
cd admin_portal
copy .env.example .env
npm install
npm run dev
```

Open the Vite URL, normally:

```text
http://localhost:5173
```

## API address

The default API is:

```text
http://127.0.0.1:6100/api/v1
```

To use another backend address, edit `.env`:

```text
VITE_API_BASE_URL=http://192.168.1.20:6100/api/v1
```

Use the Nginx proxy for same-origin browser requests in the production portal.
The Docker production build uses the relative `/api/v1` address on its own origin.

## Default development administrator

Unless changed in `backend/.env`:

```text
admin@example.com
ChangeThisAdminPassword!
```

## Device lifecycle and session policy

See [0.8.0 provisioning, login duration, Wi-Fi changes, and account reset](../docs/device-lifecycle-and-session-policy.md).
