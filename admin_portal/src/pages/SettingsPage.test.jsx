// @vitest-environment jsdom
import React from "react";
import {it, expect, vi, afterEach} from "vitest";
import {render, screen, cleanup} from "@testing-library/react";
import {MemoryRouter} from "react-router-dom";
import SettingsPage from "./SettingsPage";
vi.mock("../context/AuthContext",()=>({useAuth:()=>({can:p=>p!=="settings.read" && p!=="audit.read"})}));
afterEach(cleanup);
it("groups permitted administration sections inside Settings",()=>{
 render(<MemoryRouter initialEntries={["/settings"]}><SettingsPage/></MemoryRouter>);
 expect(screen.getByRole("link",{name:"Administrators"}).getAttribute("href")).toBe("/settings/administrators");
 expect(screen.getByRole("link",{name:"Sessions"})).toBeTruthy();
 expect(screen.queryByRole("link",{name:"Audit"})).toBeNull();
 expect(screen.queryByText("Mobile login duration")).toBeNull();
});
