import React from 'react';
import {MemoryRouter, Route, Routes} from 'react-router-dom';
import {render, screen, waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import InboxEmailAccountPage from './InboxEmailAccountPage';
import * as API from '../../api';

vi.mock('../../api');

const mockFetchInbox = API.fetchInbox as ReturnType<typeof vi.fn>;
const mockFetchEmailAccounts = API.fetchEmailAccounts as ReturnType<
  typeof vi.fn
>;
const mockCreateEmailAccount = API.createEmailAccount as ReturnType<
  typeof vi.fn
>;
const mockUpdateEmailAccount = API.updateEmailAccount as ReturnType<
  typeof vi.fn
>;
const mockVerifyEmailAccount = API.verifyEmailAccount as ReturnType<
  typeof vi.fn
>;

const inbox: any = {id: 'inbox-1', name: 'Primary Inbox'};

const existingAccount: any = {
  id: 'email-account-1',
  inbox_id: 'inbox-1',
  account_id: 'account-1',
  from_address: 'support@company.co',
  imap_host: 'imap.company.co',
  imap_port: 993,
  imap_tls: 'ssl',
  imap_username: 'support@company.co',
  imap_folder: 'INBOX',
  has_imap_password: true,
  smtp_host: 'smtp.company.co',
  smtp_port: 465,
  smtp_tls: 'ssl',
  smtp_username: '',
  has_smtp_password: false,
  status: 'active',
  last_error: null,
  last_synced_at: null,
};

const renderPage = () =>
  render(
    <MemoryRouter initialEntries={['/inboxes/inbox-1/email-account']}>
      <Routes>
        <Route
          path="/inboxes/:inbox_id/email-account"
          element={<InboxEmailAccountPage />}
        />
      </Routes>
    </MemoryRouter>
  );

describe('InboxEmailAccountPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockFetchInbox.mockResolvedValue(inbox);
    mockFetchEmailAccounts.mockResolvedValue([]);
  });

  it('renders the email account form', async () => {
    renderPage();

    // Waits for the mount fetches to resolve (inbox name in back button).
    await screen.findByText('Back to Primary Inbox');

    expect(screen.getByLabelText('From address')).toBeInTheDocument();
    expect(screen.getByLabelText('IMAP host')).toBeInTheDocument();
    expect(screen.getByLabelText('IMAP port')).toHaveValue('993');
    expect(screen.getByLabelText('IMAP username')).toBeInTheDocument();
    expect(screen.getByLabelText('IMAP password')).toBeInTheDocument();
    expect(screen.getByLabelText('IMAP folder')).toHaveValue('INBOX');
    expect(screen.getByLabelText('SMTP host')).toBeInTheDocument();
    expect(screen.getByLabelText('SMTP password')).toBeInTheDocument();
    expect(screen.getByRole('button', {name: 'Save'})).toBeInTheDocument();
    expect(
      screen.getByRole('button', {name: 'Test connection'})
    ).toBeInTheDocument();
    // No account saved yet, so there is nothing to remove.
    expect(
      screen.queryByRole('button', {name: 'Remove'})
    ).not.toBeInTheDocument();
    // Behavior callouts.
    expect(
      screen.getByText(/marked as read in the mailbox once imported/i)
    ).toBeInTheDocument();
    expect(
      screen.getByText(/Office365 basic-auth IMAP is not supported/i)
    ).toBeInTheDocument();
    expect(
      screen.getByText(/blank to reuse the IMAP credentials/i)
    ).toBeInTheDocument();
  });

  it('creates a new email account with the typed values on save', async () => {
    const user = userEvent.setup();
    mockCreateEmailAccount.mockResolvedValue(existingAccount);

    renderPage();
    await screen.findByText('Back to Primary Inbox');

    await user.type(
      screen.getByLabelText('From address'),
      'support@company.co'
    );
    await user.type(screen.getByLabelText('IMAP host'), 'imap.company.co');
    await user.type(
      screen.getByLabelText('IMAP username'),
      'support@company.co'
    );
    await user.type(screen.getByLabelText('IMAP password'), 'imap-secret');
    await user.type(screen.getByLabelText('SMTP host'), 'smtp.company.co');
    await user.click(screen.getByRole('button', {name: 'Save'}));

    // Blank SMTP credentials are omitted (they fall back to IMAP's).
    await waitFor(() =>
      expect(mockCreateEmailAccount).toHaveBeenCalledWith({
        inbox_id: 'inbox-1',
        from_address: 'support@company.co',
        imap_host: 'imap.company.co',
        imap_port: 993,
        imap_tls: 'ssl',
        imap_username: 'support@company.co',
        imap_password: 'imap-secret',
        imap_folder: 'INBOX',
        smtp_host: 'smtp.company.co',
        smtp_port: 465,
        smtp_tls: 'ssl',
        smtp_username: '',
      })
    );
  });

  it('tests the connection with the form values and shows per-protocol results', async () => {
    const user = userEvent.setup();
    mockVerifyEmailAccount.mockResolvedValue({
      imap: {ok: true, error: null, exists: 42},
      smtp: {ok: false, error: 'Connection refused (port 465)'},
    });

    renderPage();
    await screen.findByText('Back to Primary Inbox');

    await user.type(screen.getByLabelText('IMAP host'), 'imap.company.co');
    await user.click(screen.getByRole('button', {name: 'Test connection'}));

    expect(await screen.findByText(/IMAP ok \(42 messages\)/)).toBeVisible();
    expect(
      screen.getByText(/SMTP error: Connection refused \(port 465\)/)
    ).toBeVisible();
    // No saved account, so the current (flat) form values are verified.
    expect(mockVerifyEmailAccount).toHaveBeenCalledWith(
      expect.objectContaining({imap_host: 'imap.company.co', imap_port: 993})
    );
  });

  it('verifies a saved, untouched account by id', async () => {
    const user = userEvent.setup();
    mockFetchEmailAccounts.mockResolvedValue([existingAccount]);
    mockVerifyEmailAccount.mockResolvedValue({
      imap: {ok: true, error: null, exists: 1},
      smtp: {ok: true, error: null},
    });

    renderPage();
    await screen.findByText('Back to Primary Inbox');

    await user.click(screen.getByRole('button', {name: 'Test connection'}));

    await waitFor(() =>
      expect(mockVerifyEmailAccount).toHaveBeenCalledWith({
        id: 'email-account-1',
      })
    );
    expect(await screen.findByText(/SMTP ok/)).toBeVisible();
  });

  it('does not send blank passwords when updating an existing account', async () => {
    const user = userEvent.setup();
    mockFetchEmailAccounts.mockResolvedValue([existingAccount]);
    mockUpdateEmailAccount.mockResolvedValue(existingAccount);

    renderPage();
    await screen.findByText('Back to Primary Inbox');

    // The form is populated from the saved account, and the stored password
    // (never returned by the API) shows as "(unchanged)".
    expect(screen.getByLabelText('IMAP host')).toHaveValue('imap.company.co');
    expect(screen.getByLabelText('IMAP password')).toHaveAttribute(
      'placeholder',
      '(unchanged)'
    );
    expect(screen.getByLabelText('SMTP password')).not.toHaveAttribute(
      'placeholder'
    );

    const imapHost = screen.getByLabelText('IMAP host');
    await user.clear(imapHost);
    await user.type(imapHost, 'imap2.company.co');
    await user.click(screen.getByRole('button', {name: 'Save'}));

    await waitFor(() => expect(mockUpdateEmailAccount).toHaveBeenCalled());

    const [id, params] = mockUpdateEmailAccount.mock.calls[0];
    expect(id).toEqual('email-account-1');
    expect(params.imap_host).toEqual('imap2.company.co');
    expect(params).not.toHaveProperty('imap_password');
    expect(params).not.toHaveProperty('smtp_password');
    expect(mockCreateEmailAccount).not.toHaveBeenCalled();
  });

  it('shows an error banner when the account sync is failing', async () => {
    mockFetchEmailAccounts.mockResolvedValue([
      {
        ...existingAccount,
        status: 'error',
        last_error: 'IMAP authentication failed',
      },
    ]);

    renderPage();

    expect(
      await screen.findByText('There is a problem with this email account')
    ).toBeVisible();
    expect(screen.getByText('IMAP authentication failed')).toBeVisible();
    // A saved account can be removed.
    expect(screen.getByRole('button', {name: 'Remove'})).toBeInTheDocument();
  });
});
