// @vitest-environment jsdom
import React from 'react';import {it,expect,vi,afterEach} from 'vitest';import {render,screen,cleanup} from '@testing-library/react';import DeviceTypesPage from './DeviceTypesPage';import {api} from '../services/api';
vi.mock('../context/AuthContext',()=>({useAuth:()=>({can:p=>p==='models.read'})}));
vi.mock('../services/api',()=>({api:{deviceTypes:vi.fn().mockRejectedValue(new Error('No type access')),deviceModels:vi.fn().mockResolvedValue([{key:'lamp',name:'Authorized lamp',device_type_id:7,hardware_version:'1',firmware_target:'esp32_test_light',capabilities:[]}]),deviceFeatures:vi.fn().mockResolvedValue([])}}));
afterEach(cleanup);
it('loads authorized model data without requiring device-type read permission',async()=>{render(<DeviceTypesPage/>);expect(await screen.findByText('Authorized lamp')).toBeTruthy();expect(api.deviceTypes).not.toHaveBeenCalled();expect(screen.queryByRole("button",{name:"Create model"})).toBeNull();});
