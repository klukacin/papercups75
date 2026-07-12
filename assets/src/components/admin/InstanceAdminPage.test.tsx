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
const mockFetchInstanceSettings = API.fetchInstanceSettings as ReturnType<
  typeof vi.fn
>;
const mockUpdateInstanceSettings = API.updateInstanceSettings as ReturnType<
  typeof vi.fn
>;

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

const instanceSettings: API.InstanceSettings = {
  editable: [
    {
      key: 'REGISTRATION_DISABLED',
      type: 'boolean',
      value: 'false',
      source: 'env',
    },
    {
      key: 'DASHBOARD_URL',
      type: 'string',
      value: 'https://app.example.com',
      source: 'override',
    },
    {
      key: 'SUPPORT_EMAIL',
      type: 'string',
      value: null,
      source: null,
    },
  ],
  env_only: [
    {key: 'DATABASE_URL', is_set: true, preview: 'ecto://po********'},
    {key: 'MAILGUN_API_KEY', is_set: false, preview: null},
  ],
};

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

// The settings pane is rendered lazily by antd Tabs, so the settings fetch
// only fires (and its content only mounts) once the tab has been clicked.
const openSettingsTab = async (user: ReturnType<typeof userEvent.setup>) => {
  const tab = await screen.findByRole('tab', {name: 'Settings'});

  await user.click(tab);
};

describe('InstanceAdminPage', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.clearAllMocks();
    mockUseAuth.mockReturnValue(authState({isSuperadmin: true}));
    mockFetchAccounts.mockResolvedValue(workspaces);
    mockFetchAllUsersAdmin.mockResolvedValue(adminUsers);
    mockFetchInstanceSettings.mockResolvedValue(instanceSettings);
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

  it('renders editable settings with controls and source tags in the settings tab', async () => {
    const user = userEvent.setup();

    renderPage();
    await openSettingsTab(user);

    // Boolean settings render as a switch; string settings as a text input.
    const toggle = await screen.findByRole('switch', {
      name: 'Toggle REGISTRATION_DISABLED',
    });
    expect(toggle).not.toBeChecked();

    const input = screen.getByRole('textbox', {
      name: 'Value for DASHBOARD_URL',
    });
    expect(input).toHaveValue('https://app.example.com');

    // Each row shows a humanized label plus the raw key.
    expect(screen.getByText('Registration disabled')).toBeInTheDocument();
    expect(screen.getByText('REGISTRATION_DISABLED')).toBeInTheDocument();

    // Source tags: DB override (blue), from env (default), unset (gray).
    expect(screen.getByText('DB override')).toBeInTheDocument();
    expect(screen.getByText('from env')).toBeInTheDocument();
    expect(screen.getByText('unset')).toBeInTheDocument();

    // Only settings backed by a DB override can be reset to env.
    expect(
      screen.getByRole('button', {name: 'Reset DASHBOARD_URL to env'})
    ).toBeEnabled();
    expect(
      screen.getByRole('button', {name: 'Reset REGISTRATION_DISABLED to env'})
    ).toBeDisabled();

    // Env-only settings are listed read-only with a set/not set status.
    expect(screen.getByText('DATABASE_URL')).toBeInTheDocument();
    expect(screen.getByText('ecto://po********')).toBeInTheDocument();
    expect(screen.getByText('MAILGUN_API_KEY')).toBeInTheDocument();
    expect(screen.getByText('set')).toBeInTheDocument();
    expect(screen.getByText('not set')).toBeInTheDocument();
  });

  it('saves only the changed settings', async () => {
    const user = userEvent.setup();
    mockUpdateInstanceSettings.mockResolvedValue({
      editable: [
        {
          key: 'REGISTRATION_DISABLED',
          type: 'boolean',
          value: 'true',
          source: 'override',
        },
        {
          key: 'DASHBOARD_URL',
          type: 'string',
          value: 'https://app.example.com',
          source: 'override',
        },
        {
          key: 'SUPPORT_EMAIL',
          type: 'string',
          value: 'help@acme.co',
          source: 'override',
        },
      ],
      env_only: instanceSettings.env_only,
    });

    renderPage();
    await openSettingsTab(user);

    const toggle = await screen.findByRole('switch', {
      name: 'Toggle REGISTRATION_DISABLED',
    });
    await user.click(toggle);
    await user.type(
      screen.getByRole('textbox', {name: 'Value for SUPPORT_EMAIL'}),
      'help@acme.co'
    );
    await user.click(screen.getByRole('button', {name: 'Save'}));

    // Only the two edited keys are sent; DASHBOARD_URL is untouched.
    await waitFor(() =>
      expect(mockUpdateInstanceSettings).toHaveBeenCalledWith({
        REGISTRATION_DISABLED: true,
        SUPPORT_EMAIL: 'help@acme.co',
      })
    );
    expect(mockUpdateInstanceSettings).toHaveBeenCalledTimes(1);

    expect(
      await screen.findByText('Instance settings updated')
    ).toBeInTheDocument();

    // The section re-renders from the server response.
    await waitFor(() =>
      expect(screen.getAllByText('DB override')).toHaveLength(3)
    );
    expect(toggle).toBeChecked();
  });

  it('resets a setting to its env value by sending null', async () => {
    const user = userEvent.setup();
    mockUpdateInstanceSettings.mockResolvedValue({
      editable: [
        instanceSettings.editable[0],
        {
          key: 'DASHBOARD_URL',
          type: 'string',
          value: 'https://env.example.com',
          source: 'env',
        },
        instanceSettings.editable[2],
      ],
      env_only: instanceSettings.env_only,
    });

    renderPage();
    await openSettingsTab(user);

    const resetButton = await screen.findByRole('button', {
      name: 'Reset DASHBOARD_URL to env',
    });
    await user.click(resetButton);

    await waitFor(() =>
      expect(mockUpdateInstanceSettings).toHaveBeenCalledWith({
        DASHBOARD_URL: null,
      })
    );

    // The row re-renders from the response: the override is gone and the
    // input now reflects the env-provided value.
    await waitFor(() =>
      expect(
        screen.getByRole('textbox', {name: 'Value for DASHBOARD_URL'})
      ).toHaveValue('https://env.example.com')
    );
    expect(screen.queryByText('DB override')).not.toBeInTheDocument();
  });

  it('shows the server error message when saving settings fails', async () => {
    const user = userEvent.setup();
    mockUpdateInstanceSettings.mockRejectedValue({
      response: {
        status: 422,
        body: {error: {message: 'Unknown setting: REGISTRATION_DISABLED'}},
      },
    });

    renderPage();
    await openSettingsTab(user);

    const toggle = await screen.findByRole('switch', {
      name: 'Toggle REGISTRATION_DISABLED',
    });
    await user.click(toggle);
    await user.click(screen.getByRole('button', {name: 'Save'}));

    expect(
      await screen.findByText('Unknown setting: REGISTRATION_DISABLED')
    ).toBeInTheDocument();
    // Local edits are preserved so they can be corrected and retried.
    expect(toggle).toBeChecked();
  });
});
