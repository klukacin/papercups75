import React from 'react';
import {MemoryRouter, Route, Routes} from 'react-router-dom';
import {render, screen, waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import InstanceAdminPage from './InstanceAdminPage';
import * as API from '../../api';
import {getCurrentAccountId} from '../../storage';

vi.mock('../../api');

const {mockUseAuth} = vi.hoisted(() => ({mockUseAuth: vi.fn()}));

vi.mock('../auth/AuthProvider', () => ({
  useAuth: mockUseAuth,
}));

const mockFetchAccounts = API.fetchAccounts as ReturnType<typeof vi.fn>;
const mockFetchAllUsersAdmin = API.fetchAllUsersAdmin as ReturnType<
  typeof vi.fn
>;
const mockSetUserSuperadmin = API.setUserSuperadmin as ReturnType<typeof vi.fn>;

const authState = ({isSuperadmin = true}: {isSuperadmin?: boolean} = {}) => ({
  account: {id: 'account-1', company_name: 'Acme Inc'},
  currentUser: {
    id: 1,
    email: 'root@test.com',
    is_superadmin: isSuperadmin,
  },
});

const workspaces: any[] = [
  {id: 'account-1', company_name: 'Acme Inc', users: [{id: 1}, {id: 2}]},
  {id: 'account-2', company_name: 'Beta Co'},
];

const adminUsers: any[] = [
  {
    id: 1,
    email: 'root@test.com',
    display_name: 'Root',
    is_superadmin: true,
    memberships: [
      {account_id: 'account-1', company_name: 'Acme Inc', role: 'admin'},
    ],
  },
  {
    id: 2,
    email: 'agent@test.com',
    is_superadmin: false,
    memberships: [
      {account_id: 'account-2', company_name: 'Beta Co', role: 'user'},
    ],
  },
];

// jsdom does not implement navigation, so replace `window.location` with a
// stub whose `reload` we can observe.
const reloadSpy = vi.fn();

beforeAll(() => {
  Object.defineProperty(window, 'location', {
    configurable: true,
    value: {...window.location, reload: reloadSpy},
  });
});

const renderPage = () =>
  render(
    <MemoryRouter initialEntries={['/admin']}>
      <Routes>
        <Route path="/admin" element={<InstanceAdminPage />} />
        <Route path="/" element={<div>Dashboard home</div>} />
      </Routes>
    </MemoryRouter>
  );

describe('InstanceAdminPage', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.clearAllMocks();
    mockUseAuth.mockReturnValue(authState({isSuperadmin: true}));
    mockFetchAccounts.mockResolvedValue(workspaces);
    mockFetchAllUsersAdmin.mockResolvedValue(adminUsers);
  });

  it('redirects non-superadmins to the dashboard home', async () => {
    mockUseAuth.mockReturnValue(authState({isSuperadmin: false}));

    renderPage();

    expect(await screen.findByText('Dashboard home')).toBeInTheDocument();
    expect(mockFetchAllUsersAdmin).not.toHaveBeenCalled();
    expect(mockFetchAccounts).not.toHaveBeenCalled();
  });

  it('renders all workspaces and all users for superadmins', async () => {
    renderPage();

    expect(await screen.findByText('Instance admin')).toBeInTheDocument();

    // Workspaces section: names, ids and user counts.
    expect(screen.getAllByText('Acme Inc').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Beta Co').length).toBeGreaterThan(0);
    expect(screen.getByText('account-1')).toBeInTheDocument();
    expect(screen.getByText('account-2')).toBeInTheDocument();

    // Users section: emails and superadmin toggles.
    expect(screen.getByText('root@test.com (you)')).toBeInTheDocument();
    expect(screen.getByText('agent@test.com')).toBeInTheDocument();

    const ownToggle = screen.getByRole('switch', {
      name: 'Toggle superadmin for root@test.com',
    });
    const otherToggle = screen.getByRole('switch', {
      name: 'Toggle superadmin for agent@test.com',
    });

    // You cannot toggle your own superadmin flag (server guards this too).
    expect(ownToggle).toBeDisabled();
    expect(ownToggle).toBeChecked();
    expect(otherToggle).toBeEnabled();
    expect(otherToggle).not.toBeChecked();
  });

  it('switches into a workspace from the workspaces table', async () => {
    const user = userEvent.setup();

    renderPage();

    // `account-1` is the current workspace, so only `account-2` offers Switch.
    const switchButton = await screen.findByRole('button', {name: 'Switch'});
    await user.click(switchButton);

    await waitFor(() => expect(getCurrentAccountId()).toEqual('account-2'));
    expect(reloadSpy).toHaveBeenCalled();
  });

  it('toggles the superadmin flag via setUserSuperadmin', async () => {
    const user = userEvent.setup();
    mockSetUserSuperadmin.mockResolvedValue({
      ...adminUsers[1],
      is_superadmin: true,
    });

    renderPage();

    const toggle = await screen.findByRole('switch', {
      name: 'Toggle superadmin for agent@test.com',
    });
    await user.click(toggle);

    await waitFor(() =>
      expect(mockSetUserSuperadmin).toHaveBeenCalledWith(2, true)
    );
    await waitFor(() => expect(toggle).toBeChecked());
  });

  it('shows the server error and reverts the toggle on 422', async () => {
    const user = userEvent.setup();
    mockSetUserSuperadmin.mockRejectedValue({
      response: {
        status: 422,
        body: {error: {message: 'Cannot revoke the last superadmin'}},
      },
    });

    renderPage();

    const toggle = await screen.findByRole('switch', {
      name: 'Toggle superadmin for agent@test.com',
    });
    await user.click(toggle);

    expect(
      await screen.findByText('Cannot revoke the last superadmin')
    ).toBeInTheDocument();
    await waitFor(() => expect(toggle).not.toBeChecked());
  });
});
