import React from 'react';
import {render, screen, waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import AccountSwitcher from './AccountSwitcher';
import * as API from '../../api';
import {getCurrentAccountId} from '../../storage';

vi.mock('../../api');

const {mockUseAuth} = vi.hoisted(() => ({mockUseAuth: vi.fn()}));

vi.mock('../auth/AuthProvider', () => ({
  useAuth: mockUseAuth,
}));

const mockFetchAccounts = API.fetchAccounts as ReturnType<typeof vi.fn>;
const mockCreateWorkspace = API.createWorkspace as ReturnType<typeof vi.fn>;

const buildAccount = (id: string, name: string): any => ({
  id,
  company_name: name,
});

const authState = ({isSuperadmin = false}: {isSuperadmin?: boolean} = {}) => ({
  account: {id: 'primary-account', company_name: 'Primary'},
  currentUser: {
    id: 1,
    email: 'me@test.com',
    is_superadmin: isSuperadmin,
  },
});

// jsdom does not implement navigation, so replace `window.location` with a
// stub whose `reload` we can observe.
const reloadSpy = vi.fn();

beforeAll(() => {
  Object.defineProperty(window, 'location', {
    configurable: true,
    value: {...window.location, reload: reloadSpy},
  });
});

const openCreateWorkspaceModal = async (
  user: ReturnType<typeof userEvent.setup>
) => {
  const trigger = await screen.findByLabelText('Switch account');
  await user.click(trigger);

  const menuItem = await screen.findByText('Create new workspace');
  await user.click(menuItem);
};

describe('AccountSwitcher', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.clearAllMocks();
    mockUseAuth.mockReturnValue(authState({isSuperadmin: true}));
  });

  it('renders the switch-account control even for a single account', async () => {
    mockFetchAccounts.mockResolvedValue([
      buildAccount('primary-account', 'Primary'),
    ]);

    render(<AccountSwitcher />);

    await waitFor(() =>
      expect(screen.getByLabelText('Switch account')).toBeInTheDocument()
    );
  });

  it('renders a switch-account control when the user has multiple accounts', async () => {
    mockFetchAccounts.mockResolvedValue([
      buildAccount('primary-account', 'Primary'),
      buildAccount('second-account', 'Second'),
    ]);

    render(<AccountSwitcher />);

    await waitFor(() =>
      expect(screen.getByLabelText('Switch account')).toBeInTheDocument()
    );
  });

  it('shows the create-workspace item for superadmins', async () => {
    const user = userEvent.setup();
    mockFetchAccounts.mockResolvedValue([
      buildAccount('primary-account', 'Primary'),
    ]);

    render(<AccountSwitcher />);

    const trigger = await screen.findByLabelText('Switch account');
    await user.click(trigger);

    expect(await screen.findByText('Create new workspace')).toBeInTheDocument();
  });

  it('hides the create-workspace item from non-superadmins', async () => {
    const user = userEvent.setup();
    mockUseAuth.mockReturnValue(authState({isSuperadmin: false}));
    mockFetchAccounts.mockResolvedValue([
      buildAccount('primary-account', 'Primary'),
    ]);

    render(<AccountSwitcher />);

    const trigger = await screen.findByLabelText('Switch account');
    await user.click(trigger);

    // Wait for the popover (account list) to be visible, then assert the
    // create action is absent.
    await screen.findByRole('menu');
    expect(screen.queryByText('Create new workspace')).not.toBeInTheDocument();
  });

  it('opens the create-workspace modal from the dropdown menu', async () => {
    const user = userEvent.setup();
    mockFetchAccounts.mockResolvedValue([
      buildAccount('primary-account', 'Primary'),
    ]);

    render(<AccountSwitcher />);

    await openCreateWorkspaceModal(user);

    expect(await screen.findByLabelText('Company name')).toBeInTheDocument();
  });

  it('creates a workspace and switches to it on submit', async () => {
    const user = userEvent.setup();
    mockFetchAccounts.mockResolvedValue([
      buildAccount('primary-account', 'Primary'),
    ]);
    mockCreateWorkspace.mockResolvedValue(
      buildAccount('new-account', 'New Workspace')
    );

    render(<AccountSwitcher />);

    await openCreateWorkspaceModal(user);

    const input = await screen.findByLabelText('Company name');
    await user.type(input, 'New Workspace');
    await user.click(screen.getByRole('button', {name: 'Create'}));

    await waitFor(() =>
      expect(mockCreateWorkspace).toHaveBeenCalledWith('New Workspace')
    );
    await waitFor(() => expect(getCurrentAccountId()).toEqual('new-account'));
    expect(reloadSpy).toHaveBeenCalled();
  });
});
