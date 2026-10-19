// @vitest-environment jsdom
import React from 'react';
import {it,expect,vi,beforeEach,afterEach} from 'vitest';
import {render,screen,fireEvent,waitFor,cleanup} from '@testing-library/react';
import RolesPage from './RolesPage';import {api} from '../services/api';
vi.mock('../context/AuthContext',()=>({useAuth:()=>({can:()=>true})}));
vi.mock('../services/api',()=>({api:{access:vi.fn()}}));
beforeEach(()=>{api.access.mockImplementation(async(path,method)=>{if(method==='POST')throw new Error('Role key exists');if(path==='/access/permissions')return {resources:{devices:['read','control']}};return [{key:'read_only',name:'Read-only',predefined:true,permissions:['devices.read']},{key:'custom_role',name:'Custom',predefined:false,permissions:['devices.read']}];});});
afterEach(()=>{cleanup();vi.resetAllMocks();});
it('shows predefined role permissions as locked',async()=>{render(<RolesPage/>);fireEvent.click(await screen.findByRole('button',{name:'View Read-only'}));expect(screen.getByRole('checkbox',{name:'devices.read'}).disabled).toBe(true);expect(screen.queryByRole('button',{name:'Save role'})).toBeNull();});
it('creating a colliding key never silently edits the existing role',async()=>{render(<RolesPage/>);await screen.findByRole('button',{name:'Edit Custom'});fireEvent.click(screen.getByRole('button',{name:'Create role'}));fireEvent.change(screen.getByLabelText('Role key'),{target:{value:'custom_role'}});fireEvent.change(screen.getByLabelText('Name'),{target:{value:'New name'}});fireEvent.click(screen.getByRole('button',{name:'Save role'}));await waitFor(()=>expect(api.access).toHaveBeenCalledWith('/access/roles','POST',expect.objectContaining({key:'custom_role'})));});
