import React from 'react';
import {Link} from 'react-router-dom';
import {RouteComponentProps, withRouter} from '../../router-compat';
import {Box, Flex} from '../ui';
import dayjs from 'dayjs';

import {
  colors,
  Alert,
  Button,
  Container,
  Divider,
  Input,
  Paragraph,
  Popconfirm,
  Select,
  Text,
  Title,
  notification,
} from '../common';
import {
  ArrowLeftOutlined,
  CheckCircleOutlined,
  CloseCircleOutlined,
} from '../icons';
import * as API from '../../api';
import {
  EmailAccount,
  EmailAccountParams,
  EmailAccountTlsMode,
  EmailAccountVerification,
  Inbox,
} from '../../types';
import logger from '../../logger';

const TLS_MODE_OPTIONS: Array<{value: EmailAccountTlsMode; label: string}> = [
  {value: 'ssl', label: 'SSL'},
  {value: 'starttls', label: 'STARTTLS'},
  {value: 'none', label: 'None'},
];

type FormValues = {
  from_address: string;
  imap_host: string;
  imap_port: string;
  imap_tls: EmailAccountTlsMode;
  imap_username: string;
  imap_password: string;
  imap_folder: string;
  smtp_host: string;
  smtp_port: string;
  smtp_tls: EmailAccountTlsMode;
  smtp_username: string;
  smtp_password: string;
};

const DEFAULT_FORM_VALUES: FormValues = {
  from_address: '',
  imap_host: '',
  imap_port: '993',
  imap_tls: 'ssl',
  imap_username: '',
  imap_password: '',
  imap_folder: 'INBOX',
  smtp_host: '',
  smtp_port: '465',
  smtp_tls: 'ssl',
  smtp_username: '',
  smtp_password: '',
};

// NB: the server never returns passwords, so the password fields always start
// out blank (see the `(unchanged)` placeholder when a password is stored).
const getFormValues = (account: EmailAccount): FormValues => {
  return {
    from_address: account.from_address ?? '',
    imap_host: account.imap_host ?? '',
    imap_port: account.imap_port != null ? String(account.imap_port) : '',
    imap_tls: account.imap_tls ?? 'ssl',
    imap_username: account.imap_username ?? '',
    imap_password: '',
    imap_folder: account.imap_folder ?? 'INBOX',
    smtp_host: account.smtp_host ?? '',
    smtp_port: account.smtp_port != null ? String(account.smtp_port) : '',
    smtp_tls: account.smtp_tls ?? 'ssl',
    smtp_username: account.smtp_username ?? '',
    smtp_password: '',
  };
};

const parsePort = (value: string): number | undefined => {
  const port = parseInt(value, 10);

  return Number.isNaN(port) ? undefined : port;
};

const VerificationResult = ({
  protocol,
  ok,
  error,
  exists,
}: {
  protocol: 'IMAP' | 'SMTP';
  ok: boolean;
  error?: string | null;
  exists?: number | null;
}) => {
  if (ok) {
    return (
      <Text>
        <CheckCircleOutlined style={{color: colors.green}} /> {protocol} ok
        {exists != null ? ` (${exists} messages)` : ''}
      </Text>
    );
  }

  return (
    <Text type="danger">
      <CloseCircleOutlined /> {protocol} error:{' '}
      {error || 'Connection failed. Please check the details above.'}
    </Text>
  );
};

type Props = RouteComponentProps<{inbox_id: string}>;
type State = {
  loading: boolean;
  saving: boolean;
  verifying: boolean;
  inbox: Inbox | null;
  emailAccount: EmailAccount | null;
  values: FormValues;
  // Whether the form still matches the saved account (i.e. no edits since the
  // last load/save) -- if so, "Test connection" verifies the stored account.
  pristine: boolean;
  verification: EmailAccountVerification | null;
  error: string | null;
};

class InboxEmailAccountPage extends React.Component<Props, State> {
  state: State = {
    loading: true,
    saving: false,
    verifying: false,
    inbox: null,
    emailAccount: null,
    values: DEFAULT_FORM_VALUES,
    pristine: true,
    verification: null,
    error: null,
  };

  async componentDidMount() {
    const {inbox_id: inboxId} = this.props.match.params;

    try {
      const [inbox, accounts] = await Promise.all([
        API.fetchInbox(inboxId),
        API.fetchEmailAccounts(),
      ]);
      const emailAccount =
        accounts.find((account) => account.inbox_id === inboxId) || null;

      this.setState({
        loading: false,
        inbox,
        emailAccount,
        values: emailAccount
          ? getFormValues(emailAccount)
          : DEFAULT_FORM_VALUES,
      });
    } catch (err) {
      logger.error('Error loading email account!', err);

      this.setState({loading: false});
    }
  }

  handleUpdateField = (field: keyof FormValues, value: string) => {
    this.setState({
      values: {...this.state.values, [field]: value},
      pristine: false,
    });
  };

  handleChangeField =
    (field: keyof FormValues) => (e: React.ChangeEvent<HTMLInputElement>) => {
      this.handleUpdateField(field, e.target.value);
    };

  getSerializedParams = (): EmailAccountParams => {
    const {values} = this.state;
    const params: EmailAccountParams = {
      from_address: values.from_address,
      imap_host: values.imap_host,
      imap_port: parsePort(values.imap_port),
      imap_tls: values.imap_tls,
      imap_username: values.imap_username,
      imap_folder: values.imap_folder,
      smtp_host: values.smtp_host,
      smtp_port: parsePort(values.smtp_port),
      smtp_tls: values.smtp_tls,
      smtp_username: values.smtp_username,
    };

    // Passwords are write-only: a blank field means "keep the stored
    // password" on updates, so blank passwords are never sent to the server.
    if (values.imap_password) {
      params.imap_password = values.imap_password;
    }

    if (values.smtp_password) {
      params.smtp_password = values.smtp_password;
    }

    return params;
  };

  handleSave = async () => {
    const {inbox_id: inboxId} = this.props.match.params;
    const {emailAccount} = this.state;

    this.setState({saving: true, error: null});

    try {
      const params = this.getSerializedParams();
      const result = emailAccount
        ? await API.updateEmailAccount(emailAccount.id, params)
        : await API.createEmailAccount({...params, inbox_id: inboxId});

      this.setState({
        emailAccount: result,
        values: getFormValues(result),
        pristine: true,
      });

      notification.success({
        title: `Email account ${emailAccount ? 'updated' : 'created'}!`,
        duration: 2,
      });
    } catch (err) {
      logger.error('Error saving email account!', err);

      this.setState({
        error:
          'Failed to save email account. Please check the details above and try again.',
      });
    } finally {
      this.setState({saving: false});
    }
  };

  handleTestConnection = async () => {
    const {emailAccount, pristine} = this.state;

    this.setState({verifying: true, verification: null, error: null});

    try {
      // If the account is saved and the form is untouched, verify the stored
      // credentials (which include the passwords the server never returns);
      // otherwise verify whatever is currently in the form.
      const params =
        emailAccount && pristine
          ? {id: emailAccount.id}
          : this.getSerializedParams();
      const verification = await API.verifyEmailAccount(params);

      this.setState({verification});
    } catch (err) {
      logger.error('Error verifying email account!', err);

      this.setState({
        error: 'Failed to test connection. Please try again in a few minutes.',
      });
    } finally {
      this.setState({verifying: false});
    }
  };

  handleDelete = async () => {
    const {emailAccount} = this.state;

    if (!emailAccount) {
      return;
    }

    this.setState({saving: true, error: null});

    try {
      await API.deleteEmailAccount(emailAccount.id);

      this.setState({
        emailAccount: null,
        values: DEFAULT_FORM_VALUES,
        pristine: true,
        verification: null,
      });
    } catch (err) {
      logger.error('Error removing email account!', err);

      this.setState({error: 'Failed to remove email account.'});
    } finally {
      this.setState({saving: false});
    }
  };

  render() {
    const {inbox_id: inboxId} = this.props.match.params;
    const {
      saving,
      verifying,
      inbox,
      emailAccount,
      values,
      verification,
      error,
    } = this.state;

    return (
      <Container sx={{maxWidth: 800}}>
        <Box mb={4}>
          <Link to={`/inboxes/${inboxId}`}>
            <Button icon={<ArrowLeftOutlined />}>
              Back to {inbox?.name || 'inbox'}
            </Button>
          </Link>
        </Box>

        <Title level={3}>Email account (IMAP/SMTP)</Title>

        <Box mb={4}>
          <Paragraph>
            Connect an email account to{' '}
            {inbox ? `the ${inbox.name}` : 'Papercups'}: incoming mail is synced
            over IMAP, and replies are sent over SMTP.
          </Paragraph>
          <Paragraph>
            <Text type="secondary">
              Incoming mail is marked as read in the mailbox once imported.
              Office365 basic-auth IMAP is not supported.
            </Text>
          </Paragraph>
        </Box>

        {emailAccount && emailAccount.status === 'error' && (
          <Box mb={4}>
            <Alert
              title="There is a problem with this email account"
              description={
                emailAccount.last_error ||
                'Syncing failed with an unknown error.'
              }
              type="error"
              showIcon
            />
          </Box>
        )}

        {emailAccount && emailAccount.last_synced_at && (
          <Box mb={3}>
            <Text type="secondary">
              Last synced{' '}
              {dayjs(emailAccount.last_synced_at).format('MMM D, YYYY h:mm a')}
            </Text>
          </Box>
        )}

        <Box mb={3}>
          <label htmlFor="from_address">
            <Text strong>From address</Text>
          </label>
          <Input
            id="from_address"
            type="email"
            value={values.from_address}
            placeholder="support@company.co"
            onChange={this.handleChangeField('from_address')}
          />
        </Box>

        <Divider />

        <Box mb={3}>
          <Title level={5}>IMAP (incoming mail)</Title>
        </Box>

        <Flex mb={3} mx={-1}>
          <Box mx={1} sx={{flex: 2}}>
            <label htmlFor="imap_host">
              <Text strong>IMAP host</Text>
            </label>
            <Input
              id="imap_host"
              type="text"
              value={values.imap_host}
              placeholder="imap.company.co"
              onChange={this.handleChangeField('imap_host')}
            />
          </Box>
          <Box mx={1} sx={{flex: 1}}>
            <label htmlFor="imap_port">
              <Text strong>IMAP port</Text>
            </label>
            <Input
              id="imap_port"
              type="text"
              inputMode="numeric"
              value={values.imap_port}
              placeholder="993"
              onChange={this.handleChangeField('imap_port')}
            />
          </Box>
          <Box mx={1} sx={{flex: 1}}>
            <label htmlFor="imap_tls">
              <Text strong>IMAP encryption</Text>
            </label>
            <Select
              id="imap_tls"
              style={{width: '100%'}}
              value={values.imap_tls}
              options={TLS_MODE_OPTIONS}
              onChange={(value: EmailAccountTlsMode) =>
                this.handleUpdateField('imap_tls', value)
              }
            />
          </Box>
        </Flex>

        <Flex mb={3} mx={-1}>
          <Box mx={1} sx={{flex: 1}}>
            <label htmlFor="imap_username">
              <Text strong>IMAP username</Text>
            </label>
            <Input
              id="imap_username"
              type="text"
              value={values.imap_username}
              placeholder="support@company.co"
              onChange={this.handleChangeField('imap_username')}
            />
          </Box>
          <Box mx={1} sx={{flex: 1}}>
            <label htmlFor="imap_password">
              <Text strong>IMAP password</Text>
            </label>
            <Input.Password
              id="imap_password"
              value={values.imap_password}
              placeholder={
                emailAccount?.has_imap_password ? '(unchanged)' : undefined
              }
              onChange={this.handleChangeField('imap_password')}
            />
          </Box>
        </Flex>

        <Box mb={3}>
          <label htmlFor="imap_folder">
            <Text strong>IMAP folder</Text>
          </label>
          <Input
            id="imap_folder"
            type="text"
            value={values.imap_folder}
            placeholder="INBOX"
            onChange={this.handleChangeField('imap_folder')}
          />
        </Box>

        <Divider />

        <Box mb={3}>
          <Title level={5}>SMTP (outgoing mail)</Title>
        </Box>

        <Flex mb={3} mx={-1}>
          <Box mx={1} sx={{flex: 2}}>
            <label htmlFor="smtp_host">
              <Text strong>SMTP host</Text>
            </label>
            <Input
              id="smtp_host"
              type="text"
              value={values.smtp_host}
              placeholder="smtp.company.co"
              onChange={this.handleChangeField('smtp_host')}
            />
          </Box>
          <Box mx={1} sx={{flex: 1}}>
            <label htmlFor="smtp_port">
              <Text strong>SMTP port</Text>
            </label>
            <Input
              id="smtp_port"
              type="text"
              inputMode="numeric"
              value={values.smtp_port}
              placeholder="465"
              onChange={this.handleChangeField('smtp_port')}
            />
          </Box>
          <Box mx={1} sx={{flex: 1}}>
            <label htmlFor="smtp_tls">
              <Text strong>SMTP encryption</Text>
            </label>
            <Select
              id="smtp_tls"
              style={{width: '100%'}}
              value={values.smtp_tls}
              options={TLS_MODE_OPTIONS}
              onChange={(value: EmailAccountTlsMode) =>
                this.handleUpdateField('smtp_tls', value)
              }
            />
          </Box>
        </Flex>

        <Flex mb={2} mx={-1}>
          <Box mx={1} sx={{flex: 1}}>
            <label htmlFor="smtp_username">
              <Text strong>SMTP username</Text>
            </label>
            <Input
              id="smtp_username"
              type="text"
              value={values.smtp_username}
              placeholder="support@company.co"
              onChange={this.handleChangeField('smtp_username')}
            />
          </Box>
          <Box mx={1} sx={{flex: 1}}>
            <label htmlFor="smtp_password">
              <Text strong>SMTP password</Text>
            </label>
            <Input.Password
              id="smtp_password"
              value={values.smtp_password}
              placeholder={
                emailAccount?.has_smtp_password ? '(unchanged)' : undefined
              }
              onChange={this.handleChangeField('smtp_password')}
            />
          </Box>
        </Flex>

        <Box mb={3}>
          <Text type="secondary">
            Leave the SMTP username and password blank to reuse the IMAP
            credentials.
          </Text>
        </Box>

        {verification && (
          <Box mb={3}>
            <Box mb={1}>
              <VerificationResult
                protocol="IMAP"
                ok={!!verification.imap?.ok}
                error={verification.imap?.error}
                exists={verification.imap?.exists}
              />
            </Box>
            <Box>
              <VerificationResult
                protocol="SMTP"
                ok={!!verification.smtp?.ok}
                error={verification.smtp?.error}
              />
            </Box>
          </Box>
        )}

        <Flex mt={4} mb={2} mx={-1}>
          <Box mx={1}>
            <Button type="primary" loading={saving} onClick={this.handleSave}>
              Save
            </Button>
          </Box>
          <Box mx={1}>
            <Button loading={verifying} onClick={this.handleTestConnection}>
              Test connection
            </Button>
          </Box>
          {emailAccount && (
            <Box mx={1}>
              <Popconfirm
                title="Are you sure you want to remove this email account?"
                okText="Yes"
                cancelText="No"
                placement="topLeft"
                onConfirm={this.handleDelete}
              >
                <Button danger>Remove</Button>
              </Popconfirm>
            </Box>
          )}
        </Flex>

        {error && (
          <Box mt={2}>
            <Text type="danger">{error}</Text>
          </Box>
        )}
      </Container>
    );
  }
}

export default withRouter(InboxEmailAccountPage);
