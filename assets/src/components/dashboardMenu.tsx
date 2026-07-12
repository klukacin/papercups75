import React from 'react';
import {Link} from 'react-router-dom';
import type {MenuProps} from 'antd';
import {
  ApiOutlined,
  CodeOutlined,
  CrownOutlined,
  GlobalOutlined,
  LineChartOutlined,
  LogoutOutlined,
  MailOutlined,
  SettingOutlined,
  SmileOutlined,
  TeamOutlined,
  VideoCameraOutlined,
} from './icons';

type MenuItems = MenuProps['items'];

export type PrimaryMenuOptions = {
  isAdminUser: boolean;
  isSuperadmin: boolean;
  shouldHighlightInbox: boolean;
  totalNumUnread: number;
  shouldDisplayBilling: boolean;
};

// Pure builder for the dashboard's primary navigation, using the antd 5 `items`
// API. Kept separate from the Dashboard component so it can be unit-tested
// without the surrounding providers (auth, notifications, router, ...).
export const buildPrimaryMenuItems = ({
  isAdminUser,
  isSuperadmin,
  shouldHighlightInbox,
  totalNumUnread,
  shouldDisplayBilling,
}: PrimaryMenuOptions): MenuItems => {
  return [
    isAdminUser
      ? {
          key: 'getting-started',
          icon: <GlobalOutlined />,
          title: 'Getting started',
          label: <Link to="/getting-started">Getting started</Link>,
        }
      : null,
    {
      key: 'conversations',
      danger: shouldHighlightInbox,
      icon: <MailOutlined />,
      title: `Inbox (${totalNumUnread})`,
      label: <Link to="/conversations/all">Inbox ({totalNumUnread})</Link>,
    },
    isAdminUser
      ? {
          key: 'integrations',
          icon: <ApiOutlined />,
          title: 'Integrations',
          label: <Link to="/integrations">Integrations</Link>,
        }
      : null,
    {
      key: 'customers',
      icon: <TeamOutlined />,
      title: 'Customers',
      label: 'Customers',
      children: [
        {key: 'people', label: <Link to="/customers">People</Link>},
        {key: 'companies', label: <Link to="/companies">Companies</Link>},
        {key: 'tags', label: <Link to="/tags">Tags</Link>},
        {key: 'issues', label: <Link to="/issues">Issues</Link>},
        {key: 'notes', label: <Link to="/notes">Notes</Link>},
      ],
    },
    {
      key: 'reporting',
      icon: <LineChartOutlined />,
      title: 'Reporting',
      label: <Link to="/reporting">Reporting</Link>,
    },
    isAdminUser
      ? {
          key: 'developers',
          icon: <CodeOutlined />,
          title: 'Developers',
          label: 'Developers',
          children: [
            {
              key: 'personal-api-keys',
              label: <Link to="/developers/personal-api-keys">API keys</Link>,
            },
            {
              key: 'event-subscriptions',
              label: (
                <Link to="/developers/event-subscriptions">
                  Event subscriptions
                </Link>
              ),
            },
            {key: 'functions', label: <Link to="/functions">Functions</Link>},
          ],
        }
      : null,
    isAdminUser
      ? {
          key: 'sessions',
          icon: <VideoCameraOutlined />,
          title: 'Sessions',
          label: 'Sessions',
          children: [
            {
              key: 'list',
              label: <Link to="/sessions/list">Live sessions</Link>,
            },
            {
              key: 'setup',
              label: <Link to="/sessions/setup">Set up Storytime</Link>,
            },
          ],
        }
      : null,
    isAdminUser
      ? {
          key: 'settings',
          icon: <SettingOutlined />,
          title: 'Settings',
          label: 'Settings',
          children: [
            {
              key: 'account',
              label: <Link to="/settings/account">Account</Link>,
            },
            {key: 'team', label: <Link to="/settings/team">My team</Link>},
            {
              key: 'profile',
              label: <Link to="/settings/profile">My profile</Link>,
            },
            {key: 'inboxes', label: <Link to="/inboxes">Inboxes</Link>},
            {
              key: 'saved-replies',
              label: <Link to="/settings/saved-replies">Saved replies</Link>,
            },
            shouldDisplayBilling
              ? {
                  key: 'billing',
                  label: <Link to="/settings/billing">Billing</Link>,
                }
              : null,
          ],
        }
      : {
          key: 'settings',
          icon: <SettingOutlined />,
          title: 'Settings',
          label: 'Settings',
          children: [
            {
              key: 'profile',
              label: <Link to="/settings/profile">My profile</Link>,
            },
            {
              key: 'saved-replies',
              label: <Link to="/settings/saved-replies">Saved replies</Link>,
            },
          ],
        },
    // Instance-level administration (all workspaces/users) is only available
    // to superadmins; see the `/admin` route in Dashboard.tsx.
    isSuperadmin
      ? {
          key: 'admin',
          icon: <CrownOutlined />,
          title: 'Instance admin',
          label: <Link to="/admin">Instance admin</Link>,
        }
      : null,
  ];
};

export type SecondaryMenuOptions = {
  showChat: boolean;
  onChatClick: () => void;
  onLogout: () => void;
};

// Pure builder for the lower "chat / log out" menu.
export const buildSecondaryMenuItems = ({
  showChat,
  onChatClick,
  onLogout,
}: SecondaryMenuOptions): MenuItems => {
  return [
    showChat
      ? {
          key: 'chat',
          icon: <SmileOutlined />,
          title: 'Chat with us!',
          label: 'Chat with us!',
          onClick: onChatClick,
        }
      : null,
    {
      key: 'logout',
      icon: <LogoutOutlined />,
      title: 'Log out',
      label: 'Log out',
      onClick: onLogout,
    },
  ];
};
