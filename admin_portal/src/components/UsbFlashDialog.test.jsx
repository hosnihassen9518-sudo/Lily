// @vitest-environment jsdom
import React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import UsbFlashDialog from "./UsbFlashDialog";
import { api } from "../services/api";
import * as usb from "../services/usbFlash";

vi.mock("../services/api", () => ({ api: {
  usbFlashModels: vi.fn(), usbFlashDevice: vi.fn(), usbFlashRecovery: vi.fn(), usbFlashPackage: vi.fn(),
  usbFlashReset: vi.fn(), usbFlashComplete: vi.fn(),
} }));
vi.mock("../services/usbFlash", () => ({
  closeBoard: vi.fn(), connectBoard: vi.fn(), factoryImageMatches: vi.fn(), validatePackage: vi.fn(),
  verifyBoot: vi.fn(), verifyResume: vi.fn(), writeFirmware: vi.fn(),
}));

const serial_number = "LILY-A1B2C3D4E5F60708";
const hardware = { chip: "ESP32-S3", mac: "11:22:33:44:55:66", flash_size: 16777216 };
const existing = { ...hardware, kind: "existing", serial_number, partition_sha256: "layout" };
const model = { key: "lily_v2", name: "Lily Light + Speaker" };
const connect = () => fireEvent.click(screen.getByRole("button", { name: "Connect USB" }));

beforeEach(() => {
  vi.resetAllMocks();
  api.usbFlashModels.mockResolvedValue([model]);
  api.usbFlashRecovery.mockResolvedValue(null);
  api.usbFlashDevice.mockResolvedValue({ model_key: model.key, name: model.name, owned: true });
  api.usbFlashPackage.mockResolvedValue({ serial_number, completion_token: "staged-package-token" });
  api.usbFlashComplete.mockResolvedValue({ status: "completed" });
  usb.validatePackage.mockResolvedValue([]);
});
afterEach(cleanup);

describe("admin USB flashing", () => {
  it("requires a model and verifies factory boot before completing inventory", async () => {
    usb.connectBoard.mockResolvedValue({ board: { ...hardware, kind: "blank" } });
    render(<UsbFlashDialog allowFactory allowReset onClose={vi.fn()} />);
    connect();
    const select = await screen.findByLabelText("Lily model");
    expect(screen.getByRole("button", { name: "Flash firmware" }).disabled).toBe(true);
    fireEvent.change(select, { target: { value: model.key } });
    fireEvent.click(screen.getByRole("button", { name: "Flash firmware" }));
    await screen.findByText(`Flash and reboot verified for ${serial_number}.`);
    expect(api.usbFlashPackage).toHaveBeenCalledWith({ ...hardware, model_key: model.key, mode: "blank" });
    expect(usb.verifyBoot).toHaveBeenCalledWith(expect.anything(), serial_number);
    expect(api.usbFlashComplete).toHaveBeenCalledWith({ mac: hardware.mac, serial_number, mode: "blank", completion_token: "staged-package-token" });
    expect(usb.verifyBoot.mock.invocationCallOrder[0]).toBeLessThan(api.usbFlashComplete.mock.invocationCallOrder[0]);
  });

  it("defaults to keeping identity and settings", async () => {
    usb.connectBoard.mockResolvedValue({ board: existing });
    render(<UsbFlashDialog onClose={vi.fn()} />);
    connect();
    expect((await screen.findByLabelText("Existing device")).value).toBe("keep");
    fireEvent.click(screen.getByRole("button", { name: "Flash firmware" }));
    await screen.findByText(`Flash and reboot verified for ${serial_number}.`);
    expect(api.usbFlashPackage).toHaveBeenCalledWith({ ...hardware, model_key: model.key, mode: "keep", serial_number, partition_sha256: "layout" });
    expect(api.usbFlashReset).not.toHaveBeenCalled();
  });

  it("requires reset confirmation, releases serial and waits for reset completion", async () => {
    usb.connectBoard.mockResolvedValue({ board: existing });
    api.usbFlashReset.mockResolvedValueOnce({ status: "pending" }).mockResolvedValueOnce({ status: "completed" });
    render(<UsbFlashDialog allowFactory allowReset onClose={vi.fn()} />);
    connect();
    fireEvent.change(await screen.findByLabelText("Existing device"), { target: { value: "reset" } });
    const reset = screen.getByRole("button", { name: "Reset device" });
    expect(reset.disabled).toBe(true);
    fireEvent.click(screen.getByRole("checkbox"));
    fireEvent.click(reset);
    const check = await screen.findByRole("button", { name: "Check reset" });
    await waitFor(() => expect(check.disabled).toBe(false));
    expect(usb.closeBoard.mock.invocationCallOrder[0]).toBeLessThan(api.usbFlashReset.mock.invocationCallOrder[0]);
    expect(api.usbFlashPackage).not.toHaveBeenCalled();
    fireEvent.click(check);
    await screen.findByRole("button", { name: "Connect USB" });
    connect();
    fireEvent.click(await screen.findByRole("button", { name: "Flash firmware" }));
    await screen.findByText(`Flash and reboot verified for ${serial_number}.`);
    expect(api.usbFlashPackage).toHaveBeenCalledWith(expect.objectContaining({ mode: "reset", serial_number }));
  });

  it("verifies a pending factory recovery before writing and does not complete a failed boot", async () => {
    usb.connectBoard.mockResolvedValue({ board: existing });
    api.usbFlashDevice.mockResolvedValue({ model_key: model.key, name: model.name, factory_pending: true });
    usb.verifyBoot.mockRejectedValue(new Error("Boot identity missing"));
    render(<UsbFlashDialog allowFactory onClose={vi.fn()} />);
    connect();
    fireEvent.click(await screen.findByRole("button", { name: "Resume factory flash" }));
    await screen.findByText("Boot identity missing");
    expect(api.usbFlashPackage).toHaveBeenCalledWith({ ...hardware, model_key: model.key, mode: "blank", resume: true });
    expect(usb.verifyResume.mock.invocationCallOrder[0]).toBeLessThan(usb.writeFirmware.mock.invocationCallOrder[0]);
    expect(api.usbFlashComplete).not.toHaveBeenCalled();
  });

  it("confirms a previously booted matching factory image without overwriting initialized data", async () => {
    usb.connectBoard.mockResolvedValue({ board: existing });
    api.usbFlashDevice.mockResolvedValue({ model_key: model.key, name: model.name, factory_pending: true });
    usb.verifyResume.mockRejectedValue(new Error("NVS has been initialized"));
    usb.factoryImageMatches.mockResolvedValue(true);
    render(<UsbFlashDialog allowFactory onClose={vi.fn()} />);
    connect();
    fireEvent.click(await screen.findByRole("button", { name: "Resume factory flash" }));
    await screen.findByText(`Flash and reboot verified for ${serial_number}.`);
    expect(usb.verifyBoot).toHaveBeenCalled();
    expect(usb.writeFirmware).not.toHaveBeenCalled();
  });

  it("resumes an existing app-only update after the interrupted app loses its serial", async () => {
    usb.connectBoard.mockResolvedValue({ board: { ...hardware, kind: "unknown", partition_sha256: "layout", appSize: 0x300000 } });
    api.usbFlashRecovery.mockResolvedValue({ serial_number, model_key: model.key, name: model.name, mode: "keep", partition_sha256: "layout" });
    render(<UsbFlashDialog onClose={vi.fn()} />);
    connect();
    fireEvent.click(await screen.findByRole("button", { name: "Resume firmware update" }));
    await screen.findByText(`Flash and reboot verified for ${serial_number}.`);
    expect(api.usbFlashPackage).toHaveBeenCalledWith({ ...hardware, mode: "keep", model_key: model.key, serial_number, partition_sha256: "layout", resume: true });
    expect(usb.verifyResume).not.toHaveBeenCalled();
  });
});
