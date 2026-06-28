import React from 'react';
import {render, screen} from '@testing-library/react';
import DisabledUsersTable from './DisabledUsersTable';

// Regression guard for the antd 5 Dropdown `menu` migration.
const user: any = {
  id: 1,
  email: 'disabled@example.com',
  role: 'user',
  disabled_at: '2024-01-01T00:00:00Z',
};

describe('DisabledUsersTable', () => {
  it('renders disabled users with a row-action trigger', () => {
    render(
      <DisabledUsersTable
        users={[user]}
        isAdmin
        onEnableUser={() => {}}
        onArchiveUser={() => {}}
      />
    );

    expect(screen.getByText('disabled@example.com')).toBeInTheDocument();
    expect(document.querySelector('.ant-dropdown-trigger')).toBeInTheDocument();
  });
});
