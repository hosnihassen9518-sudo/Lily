// @vitest-environment jsdom
import React from 'react';
import {it,expect,vi,beforeEach,afterEach} from 'vitest';
import {render,screen,fireEvent,waitFor,cleanup} from '@testing-library/react';
import DeviceTypesPage from './DeviceTypesPage';
import {api} from '../services/api';
vi.mock('../context/AuthContext',()=>({useAuth:()=>({can:()=>true})}));
vi.mock('../services/api',()=>({api:{deviceTypes:vi.fn(),deviceModels:vi.fn(),deviceFeatures:vi.fn(),createDeviceModel:vi.fn(),updateDeviceModel:vi.fn(),deleteDeviceModel:vi.fn()}}));
beforeEach(()=>{
 api.deviceTypes.mockResolvedValue([{id:1,key:'light',name:'Light',capabilities:[]}]);
 api.deviceModels.mockResolvedValue([{key:'lamp',name:'Lamp',device_type_id:1,hardware_version:'1',firmware_target:'esp32_test_light',capabilities:['power','light','brightness']}]);
 api.deviceFeatures.mockResolvedValue(['power','light','brightness','rgb','audio','volume'].map(key=>({key,name:key,description:key+' feature'})));
});
afterEach(()=>{cleanup();vi.resetAllMocks();});
it('edits explicit capabilities and keeps model key immutable',async()=>{
 render(<DeviceTypesPage/>);fireEvent.click(await screen.findByRole('button',{name:'Edit Lamp'}));
 expect(screen.getByLabelText('Model key').disabled).toBe(true);
 fireEvent.click(screen.getByRole('checkbox',{name:'brightness'}));
 fireEvent.click(screen.getByRole('button',{name:'Save model'}));
 await waitFor(()=>expect(api.updateDeviceModel).toHaveBeenCalledWith('lamp',expect.objectContaining({capabilities:['power','light']})));
});
it('adds feature prerequisites and shows create failures without losing the form',async()=>{
 api.createDeviceModel.mockRejectedValue(new Error('Model key already exists'));
 render(<DeviceTypesPage/>);await screen.findByRole('button',{name:'Edit Lamp'});
 fireEvent.change(screen.getByLabelText('Model key'),{target:{value:'new'}});
 fireEvent.change(screen.getByLabelText('Model name'),{target:{value:'New lamp'}});
 fireEvent.change(screen.getByLabelText('Device type'),{target:{value:'1'}});
 fireEvent.click(screen.getByRole('checkbox',{name:'volume'}));
 expect(screen.getByRole('checkbox',{name:'audio'}).checked).toBe(true);
 fireEvent.click(screen.getByRole('button',{name:'Create model'}));
 await screen.findByText('Model key already exists');expect(screen.getByLabelText('Model name').value).toBe('New lamp');
});
it('shows pending schedule delivery after a model is saved',async()=>{
 api.updateDeviceModel.mockResolvedValue({schedule_sync_pending:[11]});
 render(<DeviceTypesPage/>);fireEvent.click(await screen.findByRole('button',{name:'Edit Lamp'}));
 fireEvent.click(screen.getByRole('button',{name:'Save model'}));
 await screen.findByText('Model saved. Schedule updates are waiting for the server or devices to reconnect.');
});
it('requires deletion confirmation and preserves models when in use',async()=>{
 api.deleteDeviceModel.mockRejectedValue(new Error('Model is in use'));
 render(<DeviceTypesPage/>);fireEvent.click(await screen.findByRole('button',{name:'Delete Lamp'}));
 expect(api.deleteDeviceModel).not.toHaveBeenCalled();
 fireEvent.click(screen.getByRole('button',{name:'Confirm delete'}));
 await screen.findByText('Model is in use');expect(screen.getByRole('button',{name:'Edit Lamp'})).toBeTruthy();
});
it('selecting color includes light and power and removing power removes dependents',async()=>{
 render(<DeviceTypesPage/>);await screen.findByRole('button',{name:'Edit Lamp'});
 fireEvent.click(screen.getByRole('checkbox',{name:'rgb'}));
 expect(screen.getByRole('checkbox',{name:'light'}).checked).toBe(true);
 expect(screen.getByRole('checkbox',{name:'power'}).checked).toBe(true);
 fireEvent.click(screen.getByRole('checkbox',{name:'power'}));
 expect(screen.getByRole('checkbox',{name:'light'}).checked).toBe(false);
 expect(screen.getByRole('checkbox',{name:'rgb'}).checked).toBe(false);
});
