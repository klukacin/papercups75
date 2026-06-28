import React from 'react';
import {MemoryRouter} from 'react-router-dom';
import {render, screen} from '@testing-library/react';
import {IssuesTable} from './IssuesTable';

// Regression guard for the antd 5 Dropdown `menu` migration: the table renders
// and the row action trigger is present.
const issue: any = {
  id: 'issue-1',
  title: 'Investigate the flaky webhook',
  state: 'in_progress',
  github_issue_url: 'https://github.com/example/repo/issues/1',
  updated_at: '2024-01-01T00:00:00Z',
  inserted_at: '2024-01-01T00:00:00Z',
};

describe('IssuesTable', () => {
  it('renders issue rows and a row-action trigger', () => {
    render(
      <MemoryRouter>
        <IssuesTable issues={[issue]} onUpdate={() => {}} />
      </MemoryRouter>
    );

    expect(screen.getByText('Investigate the flaky webhook')).toBeInTheDocument();
    expect(screen.getByText('in progress')).toBeInTheDocument();
    // The actions Dropdown renders a button trigger in the last column.
    expect(document.querySelector('.ant-dropdown-trigger')).toBeInTheDocument();
  });
});
