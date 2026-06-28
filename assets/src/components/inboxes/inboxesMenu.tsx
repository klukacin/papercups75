import React from 'react';
import {Link} from 'react-router-dom';
import {Box, Flex} from 'theme-ui';
import type {MenuProps} from 'antd';
import {Badge} from '../common';
import {PlusOutlined, SettingOutlined} from '../icons';
import {Inbox} from '../../types';

type MenuItems = MenuProps['items'];

const badgeLink = (to: string, label: string, count: number) => (
  <Link to={to}>
    <Flex sx={{alignItems: 'center', justifyContent: 'space-between'}}>
      <Box mr={2}>{label}</Box>
      <Badge count={count} style={{borderColor: '#FF4D4F'}} />
    </Flex>
  </Link>
);

export type InboxesUnread = {
  conversations: {
    assigned?: number;
    mentioned?: number;
    unread?: number;
    unassigned: number;
    priority: number;
  };
  inboxes: Record<string, number>;
};

export type InboxesMenuOptions = {
  totalNumUnread: number;
  unread: InboxesUnread;
  inboxes: Array<Inbox>;
  isAdminUser: boolean;
  onAddInbox: () => void;
};

// Pure builder for the inboxes sidebar navigation using the antd 5 `items` API.
// Extracted from InboxesDashboard so it can be unit-tested without the
// component's providers.
export const buildInboxesMenuItems = ({
  totalNumUnread,
  unread,
  inboxes,
  isAdminUser,
  onAddInbox,
}: InboxesMenuOptions): MenuItems => {
  return [
    {
      key: 'conversations',
      label: 'Conversations',
      children: [
        {key: 'all', label: badgeLink('/conversations/all', 'All', totalNumUnread)},
        {
          key: 'me',
          label: badgeLink(
            '/conversations/me',
            'Assigned to me',
            unread.conversations.assigned || 0
          ),
        },
        {
          key: 'mentions',
          label: badgeLink(
            '/conversations/mentions',
            'Mentions',
            unread.conversations.mentioned || 0
          ),
        },
        {
          key: 'unread',
          label: badgeLink(
            '/conversations/unread',
            'Unread',
            unread.conversations.unread || 0
          ),
        },
        {
          key: 'unassigned',
          label: badgeLink(
            '/conversations/unassigned',
            'Unassigned',
            unread.conversations.unassigned
          ),
        },
        {
          key: 'priority',
          label: badgeLink(
            '/conversations/priority',
            'Prioritized',
            unread.conversations.priority
          ),
        },
        {
          key: 'closed',
          label: <Link to="/conversations/closed">Closed</Link>,
        },
      ],
    },
    {
      key: 'inboxes',
      label: 'Inboxes',
      children: inboxes.map((inbox) => {
        const {id, name} = inbox;

        return {
          key: id,
          label: badgeLink(
            `/inboxes/${id}/conversations`,
            name,
            unread.inboxes[id] || 0
          ),
        };
      }),
    },
    isAdminUser
      ? {
          key: 'add-inbox',
          icon: <PlusOutlined />,
          title: 'Add inbox',
          label: 'Add inbox',
          onClick: onAddInbox,
        }
      : null,
    isAdminUser
      ? {
          key: 'inbox-settings',
          icon: <SettingOutlined />,
          title: 'Inbox settings',
          label: <Link to="/inboxes">Configure inboxes</Link>,
        }
      : null,
  ];
};
