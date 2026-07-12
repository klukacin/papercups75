import React from 'react';
import {Navigate} from 'react-router-dom';
import {Box, Flex} from '../ui';
import {
  colors,
  message,
  Button,
  Container,
  Divider,
  Paragraph,
  Switch,
  Table,
  Tabs,
  Tag,
  Text,
  Title,
} from '../common';
import Spinner from '../Spinner';
import InstanceSettingsSection from './InstanceSettingsSection';
import * as API from '../../api';
import {Account, Alignment} from '../../types';
import {getCurrentAccountId, setCurrentAccountId} from '../../storage';
import {useAuth} from '../auth/AuthProvider';
import logger from '../../logger';

const WorkspacesTable = ({
  loading,
  workspaces,
  selectedWorkspaceId,
  onSelectWorkspace,
}: {
  loading?: boolean;
  workspaces: Array<Account>;
  selectedWorkspaceId: string | null;
  onSelectWorkspace: (id: string) => void;
}) => {
  const data = workspaces.map((workspace) => {
    return {...workspace, key: workspace.id};
  });

  const columns = [
    {
      title: 'Name',
      dataIndex: 'company_name',
      key: 'company_name',
      render: (value: string) => {
        return value || 'Untitled account';
      },
    },
    {
      title: 'ID',
      dataIndex: 'id',
      key: 'id',
      render: (value: string) => {
        return <Text code>{value}</Text>;
      },
    },
    {
      title: 'Users',
      dataIndex: 'users',
      key: 'users',
      render: (users: Account['users']) => {
        // The users association is only included in some account payloads.
        return Array.isArray(users) ? users.length : '--';
      },
    },
    {
      title: '',
      dataIndex: 'action',
      key: 'action',
      align: Alignment.Right,
      render: (value: string, record: Account) => {
        if (record.id === selectedWorkspaceId) {
          return <Tag color={colors.green}>Current</Tag>;
        }

        return (
          <Button onClick={() => onSelectWorkspace(record.id)}>Switch</Button>
        );
      },
    },
  ];

  return (
    <Table
      loading={loading}
      dataSource={data}
      columns={columns}
      pagination={false}
    />
  );
};

const AdminUsersTable = ({
  loading,
  users,
  currentUserId,
  pendingUserId,
  onToggleSuperadmin,
}: {
  loading?: boolean;
  users: Array<API.AdminUser>;
  currentUserId?: number;
  pendingUserId: number | null;
  onToggleSuperadmin: (user: API.AdminUser, isSuperadmin: boolean) => void;
}) => {
  const data = users.map((user) => {
    return {...user, key: user.id};
  });

  const columns = [
    {
      title: 'Email',
      dataIndex: 'email',
      key: 'email',
      render: (value: string, record: API.AdminUser) => {
        if (record.id === currentUserId) {
          return <Text strong>{value} (you)</Text>;
        }

        return value;
      },
    },
    {
      title: 'Name',
      dataIndex: 'display_name',
      key: 'display_name',
      render: (value?: string) => {
        return value || '--';
      },
    },
    {
      title: 'Memberships',
      dataIndex: 'memberships',
      key: 'memberships',
      render: (memberships: API.AdminUser['memberships']) => {
        if (!memberships || memberships.length === 0) {
          return '--';
        }

        return (
          <Flex sx={{flexWrap: 'wrap', gap: '4px'}}>
            {memberships.map((membership) => (
              <Tag
                key={membership.account_id}
                color={membership.role === 'admin' ? colors.green : undefined}
              >
                {membership.company_name || 'Untitled account'} &middot;{' '}
                {membership.role}
              </Tag>
            ))}
          </Flex>
        );
      },
    },
    {
      title: 'Superadmin',
      dataIndex: 'is_superadmin',
      key: 'is_superadmin',
      render: (value: boolean, record: API.AdminUser) => {
        return (
          <Switch
            aria-label={`Toggle superadmin for ${record.email}`}
            checked={!!value}
            // The server also guards against self-revoking, but disabling the
            // toggle for yourself makes that obvious in the UI.
            disabled={record.id === currentUserId}
            loading={pendingUserId === record.id}
            onChange={(checked) => onToggleSuperadmin(record, checked)}
          />
        );
      },
    },
  ];

  return (
    <Table
      loading={loading}
      dataSource={data}
      columns={columns}
      pagination={false}
    />
  );
};

// Instance-wide administration for superadmins: lists every workspace on the
// instance (with a quick "switch into it" action) and every user (with the
// ability to grant/revoke the superadmin flag), plus a Settings tab for
// instance-wide runtime configuration. Non-superadmins are redirected away;
// the server enforces the same restrictions on every endpoint used here.
const InstanceAdminPage = () => {
  const {account: primaryAccount, currentUser} = useAuth();
  const isSuperadmin = !!currentUser?.is_superadmin;

  const [workspaces, setWorkspaces] = React.useState<Array<Account>>([]);
  const [users, setUsers] = React.useState<Array<API.AdminUser>>([]);
  const [isLoading, setLoading] = React.useState(true);
  const [pendingUserId, setPendingUserId] = React.useState<number | null>(null);

  React.useEffect(() => {
    if (!isSuperadmin) {
      return;
    }

    let mounted = true;

    Promise.all([API.fetchAccounts(), API.fetchAllUsersAdmin()])
      .then(([accounts, allUsers]) => {
        if (mounted) {
          setWorkspaces(accounts || []);
          setUsers(allUsers || []);
        }
      })
      .catch((err) => {
        logger.error('Failed to load instance admin data:', err);
      })
      .then(() => {
        if (mounted) {
          setLoading(false);
        }
      });

    return () => {
      mounted = false;
    };
  }, [isSuperadmin]);

  if (!isSuperadmin) {
    return <Navigate to="/" replace />;
  }

  // Same fallback as the AccountSwitcher: when no workspace has been
  // explicitly selected yet, the app is scoped to the primary account.
  const selectedWorkspaceId =
    getCurrentAccountId() || primaryAccount?.id || null;

  const handleSelectWorkspace = (workspaceId: string) => {
    setCurrentAccountId(workspaceId);
    // Full reload so every provider/query refetches under the new workspace.
    window.location.reload();
  };

  const handleToggleSuperadmin = async (
    user: API.AdminUser,
    isUserSuperadmin: boolean
  ) => {
    const setUserFlag = (id: number, flag: boolean) =>
      setUsers((prev) =>
        prev.map((u) => (u.id === id ? {...u, is_superadmin: flag} : u))
      );

    // Flip the toggle optimistically; revert below if the server rejects it
    // (e.g. 422 when revoking the last superadmin).
    setUserFlag(user.id, isUserSuperadmin);
    setPendingUserId(user.id);

    try {
      await API.setUserSuperadmin(user.id, isUserSuperadmin);
    } catch (err) {
      setUserFlag(user.id, !isUserSuperadmin);

      const description =
        err?.response?.body?.error?.message || err?.message || String(err);

      message.error(description);
    } finally {
      setPendingUserId(null);
    }
  };

  if (isLoading) {
    return (
      <Flex
        sx={{
          flex: 1,
          justifyContent: 'center',
          alignItems: 'center',
          height: '100%',
        }}
      >
        <Spinner size={40} />
      </Flex>
    );
  }

  return (
    <Container sx={{maxWidth: 960}}>
      <Box mb={4}>
        <Title level={3}>Instance admin</Title>
      </Box>

      <Tabs
        defaultActiveKey="users"
        items={[
          {
            key: 'users',
            label: 'Users & workspaces',
            children: (
              <>
                <Box mb={4}>
                  <Title level={4}>Workspaces</Title>

                  <Paragraph>
                    <Text>
                      All workspaces on this instance. Switching reloads the
                      dashboard scoped to the selected workspace.
                    </Text>
                  </Paragraph>

                  <WorkspacesTable
                    workspaces={workspaces}
                    selectedWorkspaceId={selectedWorkspaceId}
                    onSelectWorkspace={handleSelectWorkspace}
                  />
                </Box>

                <Divider />

                <Box mb={4}>
                  <Title level={4}>Users</Title>

                  <Paragraph>
                    <Text>
                      All users on this instance, across every workspace.
                      Superadmins can manage all workspaces and users.
                    </Text>
                  </Paragraph>

                  <AdminUsersTable
                    users={users}
                    currentUserId={currentUser?.id}
                    pendingUserId={pendingUserId}
                    onToggleSuperadmin={handleToggleSuperadmin}
                  />
                </Box>
              </>
            ),
          },
          {
            key: 'settings',
            label: 'Settings',
            // NB: antd renders inactive tab panes lazily, so the settings
            // fetch only fires once this tab is first activated.
            children: <InstanceSettingsSection />,
          },
        ]}
      />
    </Container>
  );
};

export default InstanceAdminPage;
