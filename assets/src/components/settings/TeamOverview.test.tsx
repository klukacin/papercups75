import React from 'react';
import {render, screen, waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import TeamOverview from './TeamOverview';
import * as API from '../../api';

vi.mock('../../api');

const mockMe = API.me as ReturnType<typeof vi.fn>;
const mockFetchAccountInfo = API.fetchAccountInfo as ReturnType<typeof vi.fn>;
const mockAddAccountMember = API.addAccountMember as ReturnType<typeof vi.fn>;
const mockUpdateAccountMemberRole = API.updateAccountMemberRole as ReturnType<
  typeof vi.fn
>;
const mockRemoveAccountMember = API.removeAccountMember as ReturnType<
  typeof vi.fn
>;

const account: any = {id: 'account-1', company_name: 'Test Co', users: []};
const adminUser: any = {
  id: 1,
  email: 'admin@test.com',
  role: 'admin',
  created_at: '2024-01-01T00:00:00Z',
};
const regularUser: any = {
  id: 2,
  email: 'agent@test.com',
  role: 'user',
  created_at: '2024-01-02T00:00:00Z',
};
const accountWithMembers: any = {
  ...account,
  users: [adminUser, regularUser],
};

describe('TeamOverview', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('lets an admin add an existing member by email', async () => {
    const user = userEvent.setup();
    mockFetchAccountInfo.mockResolvedValue(account);
    mockMe.mockResolvedValue(adminUser);
    mockAddAccountMember.mockResolvedValue({
      account_id: 'account-1',
      user_id: 3,
      role: 'user',
      email: 'new@test.com',
    });

    render(<TeamOverview />);

    const emailInput = await screen.findByLabelText('Member email');
    await user.type(emailInput, 'new@test.com');
    await user.click(screen.getByRole('button', {name: 'Add'}));

    await waitFor(() =>
      expect(mockAddAccountMember).toHaveBeenCalledWith(
        'new@test.com',
        'user' // default role
      )
    );
    // The team list is refreshed after a member is added (initial load + 1).
    await waitFor(() => expect(mockFetchAccountInfo).toHaveBeenCalledTimes(2));
  });

  it('hides the add-existing-member form from non-admins', async () => {
    mockFetchAccountInfo.mockResolvedValue(account);
    mockMe.mockResolvedValue(regularUser);

    render(<TeamOverview />);

    await screen.findByText('My Team');
    expect(screen.queryByLabelText('Member email')).not.toBeInTheDocument();
    expect(screen.queryByText('Add existing member')).not.toBeInTheDocument();
  });

  it('lets an admin change a member role in the workspace', async () => {
    const user = userEvent.setup();
    mockFetchAccountInfo.mockResolvedValue(accountWithMembers);
    mockMe.mockResolvedValue(adminUser);
    mockUpdateAccountMemberRole.mockResolvedValue({
      account_id: 'account-1',
      user_id: 2,
      role: 'admin',
      email: 'agent@test.com',
    });

    render(<TeamOverview />);

    // The admin's own row has no role selector (only other members').
    const roleSelect = await screen.findByLabelText(
      'Change role for agent@test.com'
    );
    expect(
      screen.queryByLabelText('Change role for admin@test.com')
    ).not.toBeInTheDocument();

    await user.click(roleSelect);
    await user.click(await screen.findByRole('option', {name: 'Admin'}));

    await waitFor(() =>
      expect(mockUpdateAccountMemberRole).toHaveBeenCalledWith(2, 'admin')
    );
    // The team list is refreshed after the role change (initial load + 1).
    await waitFor(() => expect(mockFetchAccountInfo).toHaveBeenCalledTimes(2));
  });

  it('lets an admin remove a member from the workspace', async () => {
    const user = userEvent.setup();
    mockFetchAccountInfo.mockResolvedValue(accountWithMembers);
    mockMe.mockResolvedValue(adminUser);
    mockRemoveAccountMember.mockResolvedValue({});

    render(<TeamOverview />);

    // Only the other member's row offers a remove action, so this is unique.
    const removeButton = await screen.findByRole('button', {name: 'Remove'});
    await user.click(removeButton);

    // Confirm the antd Popconfirm.
    await screen.findByText('Remove from workspace?');
    await user.click(screen.getByRole('button', {name: 'OK'}));

    await waitFor(() =>
      expect(mockRemoveAccountMember).toHaveBeenCalledWith(2)
    );
    // The team list is refreshed after the member is removed (initial + 1).
    await waitFor(() => expect(mockFetchAccountInfo).toHaveBeenCalledTimes(2));
  });
});
