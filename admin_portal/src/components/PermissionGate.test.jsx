// @vitest-environment jsdom
import React from 'react';
import {it,expect,vi,afterEach} from 'vitest';
import {render,screen,cleanup} from '@testing-library/react';
import PermissionGate from './PermissionGate';
vi.mock('../context/AuthContext',()=>({useAuth:()=>({can:p=>p==='models.read'})}));
afterEach(cleanup);
it('keeps reads visible and disables writes without their permission',()=>{
 render(<><PermissionGate permission="models.read"><p>Models</p></PermissionGate><PermissionGate permission="models.change" action><button>Save</button></PermissionGate></>);
 expect(screen.getByText('Models')).toBeTruthy();
 expect(screen.getByRole('button',{name:'Save'}).closest('fieldset').disabled).toBe(true);
});
