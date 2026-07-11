import React from 'react';
import {render, screen, waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import TeamOverview from './TeamOverview';
import * as API from '../../api';

vi.mock('../../api');

const mockMe = API.me as ReturnType<typeof vi.fn>;
const mockFetchAccountInfo = API.fetchAccountInfo as ReturnType<typeof vi.fn>;
const mockAddAccountMember = API.addAccountMember as ReturnType<typeof vi.fn>;

const account: any = {id: 'account-1', company_name: 'Test Co', users: []};
const adminUser: any = {id: 1, email: 'admin@test.com', role: 'admin'};
const regularUser: any = {id: 2, email: 'agent@test.com', role: 'user'};

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
});
