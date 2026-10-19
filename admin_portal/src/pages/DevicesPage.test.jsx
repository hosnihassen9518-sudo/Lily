// @vitest-environment jsdom
import React from 'react';
import { describe,it,expect,vi,afterEach } from 'vitest';
import { render,screen,fireEvent,waitFor,cleanup } from '@testing-library/react';
import DevicesPage from './DevicesPage';
import {api} from '../services/api';
vi.mock('../context/AuthContext',()=>({useAuth:()=>({can:()=>true})}));
vi.mock('../services/api',()=>({api:{devices:vi.fn(async()=>[]),deviceTypes:vi.fn(async()=>[{id:1,name:'Light'}]),deviceModels:vi.fn(async()=>[{key:'test',name:'Test light',device_type_id:1}]),generateDevice:vi.fn()}}));
afterEach(()=>{cleanup();vi.clearAllMocks();});
describe('one-time factory credentials',()=>{
 it('keeps creation open while pending and preserves the result when reopened',async()=>{
  let resolve;api.generateDevice.mockImplementation(()=>new Promise(r=>{resolve=r;}));
  const {container}=render(<DevicesPage/>);
  fireEvent.click(screen.getByText('Add device'));
  await screen.findByText('Light');
  const selects=container.querySelectorAll('select');
  fireEvent.change(selects[0],{target:{value:'1'}});
  await screen.findByText('Test light');
  fireEvent.change(selects[1],{target:{value:'test'}});
  fireEvent.submit(container.querySelector('form'));
  await waitFor(()=>expect(api.generateDevice).toHaveBeenCalledTimes(1));
  fireEvent.mouseDown(container.querySelector('.modal-backdrop'));
  expect(screen.queryByText('Creating…')).not.toBeNull();
  resolve({serial_number:'TEST-ONE-TIME',filename:'device_config.h',config_header:'secret'});
  await screen.findByText('TEST-ONE-TIME');
  fireEvent.mouseDown(container.querySelector('.modal-backdrop'));
  fireEvent.click(screen.getByText('Add device'));
  expect(screen.queryByText('TEST-ONE-TIME')).not.toBeNull();
 });
});

it('shows saved credentials and lets administrators choose CSV fields',async()=>{
 api.devices.mockResolvedValue([{id:7,serial_number:'SAVED-DEVICE',model:'Lily Test Light',status:'INVENTORY'}]);
 api.deviceCredentials=vi.fn(async()=>({serial_number:'SAVED-DEVICE',device_secret:'saved-factory-secret'}));
 api.exportDevices=vi.fn(async()=>({text:async()=>'serial_number\nSAVED-DEVICE\n'}));
 URL.createObjectURL=vi.fn(()=> 'blob:test');URL.revokeObjectURL=vi.fn();
 render(<DevicesPage/>);
 await screen.findByText('SAVED-DEVICE');
 fireEvent.click(screen.getByTitle('Show credentials'));
 await screen.findByDisplayValue('saved-factory-secret');
 fireEvent.click(screen.getByText('Export CSV'));
 expect(screen.getByText('Choose fields')).not.toBeNull();
});

it('refreshes available models when factory creation is reopened',async()=>{
 api.devices.mockResolvedValue([]);
 api.deviceModels.mockResolvedValue([{key:'test',name:'Test light',device_type_id:1}]);
 const {container}=render(<DevicesPage/>);
 await waitFor(()=>expect(api.deviceModels).toHaveBeenCalled());
 api.deviceModels.mockResolvedValue([{key:'new',name:'New model',device_type_id:1}]);
 fireEvent.click(screen.getByText('Add device'));
 fireEvent.change(container.querySelector('select'),{target:{value:'1'}});
 await screen.findByText('New model');
 expect(screen.queryByText('Test light')).toBeNull();
});
