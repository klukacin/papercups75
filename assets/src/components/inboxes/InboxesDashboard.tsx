import React from 'react';
import {useLocation, Navigate, Route, Routes} from 'react-router-dom';
import {RouteComponentProps, withRouter} from '../../router-compat';
import {Box, Flex} from 'theme-ui';

import {colors, Layout, Menu, Sider} from '../common';
import {INBOXES_DASHBOARD_SIDER_WIDTH} from '../../utils';
import * as API from '../../api';
import {Inbox} from '../../types';
import {useAuth} from '../auth/AuthProvider';
import {useConversations} from '../conversations/ConversationsProvider';
import ConversationsDashboard from '../conversations/ConversationsDashboard';
import ChatWidgetSettings from '../settings/ChatWidgetSettings';
import SlackReplyIntegrationDetails from '../integrations/SlackReplyIntegrationDetails';
import SlackSyncIntegrationDetails from '../integrations/SlackSyncIntegrationDetails';
import SlackIntegrationDetails from '../integrations/SlackIntegrationDetails';
import GmailIntegrationDetails from '../integrations/GmailIntegrationDetails';
import GoogleIntegrationDetails from '../integrations/GoogleIntegrationDetails';
import MattermostIntegrationDetails from '../integrations/MattermostIntegrationDetails';
import TwilioIntegrationDetails from '../integrations/TwilioIntegrationDetails';
import InboxEmailForwardingPage from './InboxEmailForwardingPage';
import InboxDetailsPage from './InboxDetailsPage';
import InboxesOverview from './InboxesOverview';
import InboxConversations from './InboxConversations';
import NewInboxModal from './NewInboxModal';
import {buildInboxesMenuItems} from './inboxesMenu';

const getSectionKey = (pathname: string) => {
  const isInboxSettings =
    pathname === '/inboxes' ||
    (pathname.startsWith('/inboxes') &&
      pathname.indexOf('conversations') === -1);

  if (isInboxSettings) {
    return ['inbox-settings'];
  } else {
    return pathname.split('/').slice(1); // Slice off initial slash
  }
};

const InboxesDashboard = (props: RouteComponentProps) => {
  const {pathname} = useLocation();
  const {currentUser} = useAuth();
  const {unread} = useConversations();
  const [inboxes, setCustomInboxes] = React.useState<Array<Inbox>>([]);

  const [section, key] = getSectionKey(pathname);
  const totalNumUnread = unread.conversations.open || 0;
  const isAdminUser = currentUser?.role === 'admin';
  const [isAddInboxModalOpen, setAddInboxModalOpen] = React.useState(false);

  React.useEffect(() => {
    API.fetchInboxes().then((inboxes) => setCustomInboxes(inboxes));
  }, []);

  const handleInboxCreated = async (inbox: Inbox) => {
    setCustomInboxes([...inboxes, inbox]);

    props.history.push(`/inboxes/${inbox.id}`);
  };

  return (
    <Layout style={{background: colors.white}}>
      <Sider
        className="Dashboard-Sider"
        width={INBOXES_DASHBOARD_SIDER_WIDTH}
        style={{
          overflow: 'auto',
          height: '100vh',
          position: 'fixed',
          color: colors.white,
        }}
      >
        <Flex sx={{flexDirection: 'column', height: '100%'}}>
          <Box py={3} sx={{flex: 1}}>
            {/* TODO: eventually we should design our own sidebar menu so we have more control over the UX */}
            <Menu
              selectedKeys={[section, key]}
              defaultOpenKeys={['conversations', 'channels', 'inboxes']}
              mode="inline"
              theme="dark"
              items={buildInboxesMenuItems({
                totalNumUnread,
                unread,
                inboxes,
                isAdminUser,
                onAddInbox: () => setAddInboxModalOpen(true),
              })}
            />
            <NewInboxModal
              visible={isAddInboxModalOpen}
              onCancel={() => setAddInboxModalOpen(false)}
              onSuccess={(inbox) => {
                setAddInboxModalOpen(false);
                handleInboxCreated(inbox);
              }}
            />
          </Box>
        </Flex>
      </Sider>

      <Layout
        style={{
          background: colors.white,
          marginLeft: INBOXES_DASHBOARD_SIDER_WIDTH,
        }}
      >
        {/* NB: this component is mounted at both `/conversations/*` and
            `/inboxes/*` (see Dashboard.tsx), so the descendant routes below
            are relative to whichever prefix matched. */}
        {pathname.startsWith('/inboxes') ? (
          <Routes>
            <Route
              path=":inbox_id/conversations/:conversation_id"
              element={<InboxConversations />}
            />
            <Route
              path=":inbox_id/conversations"
              element={<InboxConversations />}
            />
            <Route
              path=":inbox_id/chat-widget"
              element={<ChatWidgetSettings />}
            />
            <Route
              path=":inbox_id/integrations/slack/reply"
              element={<SlackReplyIntegrationDetails />}
            />
            <Route
              path=":inbox_id/integrations/slack/support"
              element={<SlackSyncIntegrationDetails />}
            />
            <Route
              path=":inbox_id/integrations/slack"
              element={<SlackIntegrationDetails />}
            />
            <Route
              path=":inbox_id/integrations/google/gmail"
              element={<GmailIntegrationDetails />}
            />
            <Route
              path=":inbox_id/integrations/google"
              element={<GoogleIntegrationDetails />}
            />
            <Route
              path=":inbox_id/integrations/mattermost"
              element={<MattermostIntegrationDetails />}
            />
            <Route
              path=":inbox_id/integrations/twilio"
              element={<TwilioIntegrationDetails />}
            />
            <Route
              path=":inbox_id/email-forwarding"
              element={<InboxEmailForwardingPage />}
            />
            <Route path=":inbox_id/*" element={<InboxDetailsPage />} />
            <Route index element={<InboxesOverview />} />
            <Route
              path="*"
              element={<Navigate to="/conversations/all" replace />}
            />
          </Routes>
        ) : (
          <Routes>
            <Route
              path=":bucket/:conversation_id"
              element={<ConversationsDashboard />}
            />
            <Route path=":bucket" element={<ConversationsDashboard />} />
            <Route
              path="*"
              element={<Navigate to="/conversations/all" replace />}
            />
          </Routes>
        )}
      </Layout>
    </Layout>
  );
};

export default withRouter(InboxesDashboard);
