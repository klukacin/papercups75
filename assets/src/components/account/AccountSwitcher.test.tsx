import React from 'react';
import {render, screen, waitFor} from '@testing-library/react';
import AccountSwitcher from './AccountSwitcher';
import * as API from '../../api';

vi.mock('../../api');

vi.mock('../auth/AuthProvider', () => ({
  useAuth: () => ({account: {id: 'primary-account', company_name: 'Primary'}}),
}));

const mockFetchAccounts = API.fetchAccounts as ReturnType<typeof vi.fn>;

const buildAccount = (id: string, name: string): any => ({
  id,
  company_name: name,
});

describe('AccountSwitcher', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.clearAllMocks();
  });

  it('renders nothing when the user belongs to a single account', async () => {
    mockFetchAccounts.mockResolvedValue([
      buildAccount('primary-account', 'Primary'),
    ]);

    const {container} = render(<AccountSwitcher />);

    await waitFor(() => expect(mockFetchAccounts).toHaveBeenCalled());
    expect(container).toBeEmptyDOMElement();
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
});
