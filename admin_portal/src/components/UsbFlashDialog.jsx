import React, { useEffect, useRef, useState } from "react";
import { api } from "../services/api";
import { closeBoard, connectBoard, factoryImageMatches, validatePackage, verifyBoot, verifyResume, writeFirmware } from "../services/usbFlash";
import Modal from "./Modal";

export default function UsbFlashDialog({ allowFactory, allowReset, factoryOnly = false, onClose, onComplete }) {
  const session = useRef(null);
  const mounted = useRef(true);
  const running = useRef(false);
  const [board, setBoard] = useState(null);
  const [device, setDevice] = useState(null);
  const [recovery, setRecovery] = useState(null);
  const [models, setModels] = useState([]);
  const [modelKey, setModelKey] = useState("");
  const [loadingModels, setLoadingModels] = useState(factoryOnly);
  const [modelLoadError, setModelLoadError] = useState("");
  const [catalogAttempt, setCatalogAttempt] = useState(0);
  const [mode, setMode] = useState("keep");
  const [resetTarget, setResetTarget] = useState(null);
  const [resetReady, setResetReady] = useState(false);
  const [resetConfirmed, setResetConfirmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState("");
  const [error, setError] = useState("");
  const [completion, setCompletion] = useState(null);
  const [finished, setFinished] = useState(false);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      if (!running.current) void disconnect().catch(() => {});
    };
  }, []);

  useEffect(() => {
    if (!factoryOnly) return;
    let current = true;
    api.usbFlashModels()
      .then(available => { if (current) setModels(available); })
      .catch(err => { if (current) setModelLoadError(err.message || "Could not load Lily models."); })
      .finally(() => { if (current) setLoadingModels(false); });
    return () => { current = false; };
  }, [factoryOnly, catalogAttempt]);

  const canPush = board && allowFactory && !!modelKey && board.kind !== "existing"
    && (!device?.model_key || device.model_key === modelKey);

  async function disconnect() {
    const current = session.current;
    session.current = null;
    await closeBoard(current);
  }

  async function perform(action) {
    if (running.current) return;
    running.current = true;
    setBusy(true);
    setError("");
    try {
      await action();
    } catch (err) {
      setError(err.name === "NotFoundError" ? "No USB port selected." : err.message || "USB operation failed.");
    } finally {
      if (!mounted.current) await disconnect().catch(() => {});
      running.current = false;
      setBusy(false);
      setProgress("");
    }
  }

  function disconnectDetectedBoard() {
    return perform(async () => {
      await disconnect();
      setBoard(null);
      setDevice(null);
      setRecovery(null);
    });
  }

  function connect() {
    if (factoryOnly && !models.some(model => model.key === modelKey)) return;
    return perform(async () => {
      const next = await connectBoard(setProgress);
      session.current = next;
      try {
        let detected = next.board;
        const pending = detected.partition_sha256 ? await api.usbFlashRecovery(detected.mac) : null;
        if (pending) {
          if (pending.partition_sha256 !== detected.partition_sha256 ||
              (detected.serial_number && pending.serial_number !== detected.serial_number)) {
            throw new Error("The board does not match the saved USB update.");
          }
          detected = { ...detected, kind: "existing", serial_number: pending.serial_number };
        }
        if (resetTarget && (detected.mac !== resetTarget.mac || detected.serial_number !== resetTarget.serial_number)) {
          throw new Error("Reconnect the same Lily board to continue the reset update.");
        }
        const known = pending ?? (detected.kind === "existing" ? await api.usbFlashDevice(detected.serial_number, detected.mac) : null);
        const available = allowFactory && !factoryOnly ? await api.usbFlashModels() : null;
        setDevice(known);
        setRecovery(pending);
        if (available) setModels(available);
        if (!factoryOnly) setModelKey(known?.model_key ?? "");
        setBoard(known?.factory_pending ? { ...detected, kind: "unknown" } : detected);
      } catch (err) {
        await disconnect().catch(() => {});
        throw err;
      }
    });
  }

  async function checkReset(target) {
    setProgress("Waiting for Lily to finish its factory reset…");
    const result = await api.usbFlashReset(target);
    if (result.status === "completed") setResetReady(true);
    else if (result.status !== "pending") throw new Error("Lily did not confirm the reset.");
  }

  function requestReset() {
    return perform(async () => {
      const target = { mac: board.mac, serial_number: board.serial_number };
      await disconnect();
      setBoard(null);
      setResetTarget(target);
      await checkReset(target);
    });
  }

  async function finish(payload) {
    setProgress("Saving the verified flash result…");
    const result = await api.usbFlashComplete(payload);
    if (result.status !== "completed") throw new Error("The inventory update was not confirmed. Save the verified result again.");
    setFinished(true);
    onComplete?.(payload.serial_number);
  }

  function flash() {
    return perform(async () => {
      const current = session.current;
      if (factoryOnly && !canPush) return;
      if (!current || !modelKey || (board.kind !== "existing" && !allowFactory)) throw new Error("Connect an authorized board and choose its model.");
      const existing = board.kind === "existing";
      const selectedMode = recovery?.mode ?? (resetReady ? "reset" : existing ? "keep" : "blank");
      const { chip, mac, flash_size, serial_number, partition_sha256 } = board;
      const payload = { mode: selectedMode, chip, mac, flash_size, model_key: modelKey };
      if (selectedMode !== "blank") Object.assign(payload, { serial_number, partition_sha256 });
      if (board.kind === "unknown" || recovery) payload.resume = true;
      let writing = false;
      let written = false;
      let verifying = false;
      try {
        setProgress("Preparing firmware for this board…");
        const pkg = await api.usbFlashPackage(payload);
        if (typeof pkg.completion_token !== "string" || !pkg.completion_token) throw new Error("The firmware package has no completion token.");
        if (!mounted.current) return;
        const files = await validatePackage(pkg, board, selectedMode, modelKey);
        let alreadyWritten = false;
        if (payload.resume && selectedMode === "blank") {
          setProgress("Checking the previous factory write…");
          try {
            await verifyResume(current.loader, flash_size, files);
          } catch (err) {
            // An earlier successful boot may have initialized NVS or the file
            // system. In that case verify the installed image without writing.
            if (!device?.factory_pending || board.serial_number !== pkg.serial_number ||
                !await factoryImageMatches(current.loader, files)) throw err;
            alreadyWritten = true;
            setProgress("Checking the previously written firmware at reboot…");
            verifying = true;
            await verifyBoot(current, pkg.serial_number);
          }
        }
        if (!mounted.current) return;
        if (!alreadyWritten) {
          writing = true;
          await writeFirmware(current, files, setProgress);
          written = true;
          setProgress("Flash verified. Checking Lily’s boot identity…");
          await verifyBoot(current, pkg.serial_number);
        }
        const result = { mode: selectedMode, serial_number: pkg.serial_number, mac, completion_token: pkg.completion_token };
        setCompletion(result);
        await finish(result);
      } catch (err) {
        if (writing && !written) throw new Error("Flash did not finish. Reconnect the same board and retry its prepared firmware.");
        throw err;
      } finally {
        if (writing || verifying) {
          await disconnect().catch(() => {});
          setBoard(null);
        }
      }
    });
  }

  async function dismiss() {
    if (running.current) return;
    await perform(async () => {
      await disconnect();
      onClose();
    });
  }

  return (
    <Modal title={factoryOnly ? "Add device" : "Flash Lily over USB"} onClose={dismiss}>
      <div className="form-grid" aria-busy={busy}>
        {factoryOnly && !completion && (
          <>
            <label>
              Lily model
              <select value={modelKey} onChange={event => setModelKey(event.target.value)}
                disabled={busy || !!board || loadingModels}>
                <option value="">{loadingModels ? "Loading models…" : "Select model"}</option>
                {models.map(model => <option key={model.key} value={model.key}>{model.name}</option>)}
              </select>
            </label>
            {!loadingModels && !modelLoadError && !models.length && <p>No Lily models are available for USB setup.</p>}
            {modelLoadError && (
              <div className="alert error" role="alert">
                <p>{modelLoadError}</p>
                <button type="button" className="secondary-button" onClick={() => {
                  setModelLoadError("");
                  setLoadingModels(true);
                  setCatalogAttempt(attempt => attempt + 1);
                }}>Retry loading models</button>
              </div>
            )}
          </>
        )}
        {!board && !resetTarget && !completion && <p>Connect Lily to this computer with a USB data cable, then select its port.</p>}
        {board && (factoryOnly ? (
          <dl className="usb-device-details" aria-label="Detected device">
            <dt>Chip</dt><dd>{board.chip}</dd>
            <dt>Flash</dt><dd>{board.flash_size / (1024 * 1024)} MiB</dd>
            <dt>Board MAC</dt><dd className="mono">{board.mac}</dd>
            <dt>Serial number</dt><dd>{board.serial_number || "Unassigned"}</dd>
          </dl>
        ) : <p>{board.chip} · 16 MB flash · {board.mac}</p>)}
        {board?.kind === "blank" && <p>{factoryOnly
          ? "Blank board verified. Push configuration to install the selected model’s firmware and assign its factory serial."
          : "Blank board verified. Choose the Lily model to create its factory identity."}</p>}
        {factoryOnly && board?.kind === "existing" && <p>This board is already in inventory. Use Flash over USB for firmware updates.</p>}
        {factoryOnly && board && board.kind !== "existing" && device?.model_key && device.model_key !== modelKey
          && <p>This board has pending setup for {device.name}. Disconnect and select that model to resume.</p>}
        {board?.kind === "unknown" && <p>This board contains unrecognized flash data. It can only continue a previously prepared factory flash for this board.</p>}
        {board && board.kind !== "existing" && !allowFactory && <p>Your role cannot create factory devices.</p>}
        {!factoryOnly && board && board.kind !== "existing" && allowFactory && (
          <label>
            Lily model
            <select value={modelKey} onChange={(event) => setModelKey(event.target.value)} disabled={busy || device?.factory_pending}>
              <option value="">Select model</option>
              {models.map((model) => <option key={model.key} value={model.key}>{model.name}</option>)}
            </select>
          </label>
        )}
        {!factoryOnly && board?.kind === "existing" && (
          <>
            <p>{device.name} · {board.serial_number}</p>
            {recovery && <p>A pending firmware update was found for this board. Resume it to finish the update.</p>}
            {!recovery && !resetReady && (
              <label>
                Existing device
                <select value={mode} disabled={busy} onChange={(event) => { setMode(event.target.value); setResetConfirmed(false); }}>
                  <option value="keep">Keep identity and settings</option>
                  {allowReset && device.owned && <option value="reset">Reset settings and keep identity</option>}
                </select>
              </label>
            )}
            {!recovery && mode === "reset" && !resetReady && (
              <>
                <p>Reset removes ownership, Wi-Fi settings, schedules, and downloaded audio. Lily must connect to the server to confirm completion before flashing.</p>
                <label><span><input type="checkbox" checked={resetConfirmed} disabled={busy} onChange={(event) => setResetConfirmed(event.target.checked)} /> I confirm the reset for {board.serial_number}</span></label>
              </>
            )}
          </>
        )}
        {!board && resetTarget && !completion && <p>{resetReady ? "Reset confirmed. Reconnect the same Lily board to install the update." : "Keep Lily powered and connected to Wi-Fi. Check again when it has had time to confirm the reset."}</p>}
        {progress && <div role="status">{progress}</div>}
        {error && <div className="alert error" role="alert">{error}</div>}
        {finished && <div className="alert success" role="status">Flash and reboot verified for {completion.serial_number}.{factoryOnly && <p>The device is in inventory and ready to pair in the Lily app.</p>}</div>}
        {!finished && completion && <p>Flash and reboot verified. Save the result to finish the inventory update.</p>}
        <div className="modal-actions">
          <button type="button" className="secondary-button" onClick={dismiss} disabled={busy}>{finished ? "Done" : "Close"}</button>
          {!board && !completion && (!resetTarget || resetReady) && <button type="button" className="primary-button" onClick={connect} disabled={busy || (factoryOnly && !modelKey)}>{factoryOnly ? "Connect COM port" : "Connect USB"}</button>}
          {!board && !completion && resetTarget && !resetReady && <button type="button" className="primary-button" onClick={() => perform(() => checkReset(resetTarget))} disabled={busy}>Check reset</button>}
          {board?.kind === "existing" && !recovery && mode === "reset" && !resetReady && <button type="button" className="primary-button" onClick={requestReset} disabled={busy || !resetConfirmed}>Reset device</button>}
          {factoryOnly && board && <button type="button" className="secondary-button" disabled={busy} onClick={disconnectDetectedBoard}>Disconnect</button>}
          {factoryOnly && canPush && <button type="button" className="primary-button" onClick={flash} disabled={busy}>
            {board.kind === "unknown" ? "Resume configuration push" : "Push configuration"}
          </button>}
          {!factoryOnly && board && (recovery || board.kind !== "existing" || mode === "keep" || resetReady) && <button type="button" className="primary-button" onClick={flash} disabled={busy || !modelKey}>{recovery ? "Resume firmware update" : board.kind === "unknown" ? "Resume factory flash" : "Flash firmware"}</button>}
          {completion && !finished && <button type="button" className="primary-button" onClick={() => perform(() => finish(completion))} disabled={busy}>Save result</button>}
        </div>
      </div>
    </Modal>
  );
}
