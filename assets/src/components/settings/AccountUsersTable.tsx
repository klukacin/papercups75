import React from 'react';
import {Flex} from '../ui';
import dayjs from 'dayjs';
import {
  colors,
  Button,
  Dropdown,
  Popconfirm,
  Select,
  Table,
  Tag,
  Text,
} from '../common';
import {SettingOutlined, SmileTwoTone} from '../icons';
import {User, Alignment} from '../../types';

const AccountUsersTable = ({
  loading,
  users,
  currentUser,
  isAdmin,
  onDisableUser,
  onUpdateRole,
  onRemoveMember,
}: {
  loading?: boolean;
  users: Array<User>;
  currentUser: User;
  isAdmin?: boolean;
  onDisableUser: (user: User) => void;
  onUpdateRole: (user: User, role: 'user' | 'admin') => void;
  onRemoveMember: (user: User) => void;
}) => {
  // TODO: how should we sort the users?
  const data = users
    .map((u) => {
      return {...u, key: u.id};
    })
    .sort((a, b) => {
      return +new Date(a.created_at) - +new Date(b.created_at);
    });

  const columns = [
    {
      title: 'Email',
      dataIndex: 'email',
      key: 'email',
      render: (value: string, record: User) => {
        if (currentUser && record.id === currentUser.id) {
          return (
            <Flex sx={{alignItems: 'center'}}>
              <Text strong>{value}</Text>
              <SmileTwoTone
                style={{fontSize: 16, marginLeft: 4}}
                twoToneColor={colors.primary}
              />
            </Flex>
          );
        }

        return value;
      },
    },
    {
      title: 'Name',
      dataIndex: 'name',
      key: 'name',
      render: (value: string, record: User) => {
        const {full_name: fullName, display_name: displayName} = record;

        return fullName || displayName || '--';
      },
    },
    {
      title: 'Member since',
      dataIndex: 'created_at',
      key: 'created_at',
      render: (value: string) => {
        const formatted = dayjs(value).format('MMMM DD, YYYY');

        return formatted;
      },
    },
    {
      title: 'Role',
      dataIndex: 'role',
      key: 'role',
      render: (value: string, record: User) => {
        // Admins can change other members' roles in this workspace; their own
        // role (and everyone's, for non-admins) renders as a read-only tag.
        // (The server also blocks demoting the last admin with a 422.)
        if (isAdmin && currentUser && record.id !== currentUser.id) {
          return (
            <Select
              aria-label={`Change role for ${record.email}`}
              style={{width: 120}}
              value={record.role}
              // Two options need no virtual scrolling; non-virtual lists also
              // expose real `role="option"` items (better a11y + testability).
              virtual={false}
              onChange={(role: 'user' | 'admin') => onUpdateRole(record, role)}
              options={[
                {value: 'user', label: 'Member'},
                {value: 'admin', label: 'Admin'},
              ]}
            />
          );
        }

        switch (value) {
          case 'admin':
            return <Tag color={colors.green}>Admin</Tag>;
          case 'user':
            return <Tag>Member</Tag>;
          default:
            return '--';
        }
      },
    },
    {
      title: '',
      dataIndex: 'action',
      key: 'action',
      align: Alignment.Right,
      render: (value: string, record: User) => {
        if (!isAdmin) {
          return null;
        }

        // Current user cannot disable/demote/remove themselves
        if (currentUser && record.id === currentUser.id) {
          return null;
        }

        const handleMenuClick = (data: any) => {
          switch (data.key) {
            case 'disable':
              return onDisableUser(record);
            default:
              return null;
          }
        };

        return (
          <Flex sx={{justifyContent: 'flex-end', gap: '8px'}}>
            <Popconfirm
              title="Remove from workspace?"
              description={`${record.email} will lose access to this workspace.`}
              onConfirm={() => onRemoveMember(record)}
            >
              <Button danger>Remove</Button>
            </Popconfirm>

            <Dropdown
              menu={{
                onClick: handleMenuClick,
                items: [{key: 'disable', label: 'Disable user'}],
              }}
            >
              <Button icon={<SettingOutlined />} />
            </Dropdown>
          </Flex>
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

export default AccountUsersTable;
