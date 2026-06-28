import React from 'react';
import {
  useLocation,
  Switch,
  Redirect,
  Route,
  RouteComponentProps,
} from 'react-router-dom';
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
        <Switch>
          <Route
            path="/conversations/:bucket/:conversation_id"
            component={ConversationsDashboard}
          />
          <Route
            path="/conversations/:bucket"
            component={ConversationsDashboard}
          />
          <Route
            path="/inboxes/:inbox_id/conversations/:conversation_id"
            component={InboxConversations}
          />
          <Route
            path="/inboxes/:inbox_id/conversations"
            component={InboxConversations}
          />
          <Route
            path="/inboxes/:inbox_id/conversations"
            component={InboxesDashboard}
          />
          <Route
            path="/inboxes/:inbox_id/chat-widget"
            component={ChatWidgetSettings}
          />
          <Route
            path="/inboxes/:inbox_id/integrations/slack/reply"
            component={SlackReplyIntegrationDetails}
          />
          <Route
            path="/inboxes/:inbox_id/integrations/slack/support"
            component={SlackSyncIntegrationDetails}
          />
          <Route
            path="/inboxes/:inbox_id/integrations/slack"
            component={SlackIntegrationDetails}
          />
          <Route
            path="/inboxes/:inbox_id/integrations/google/gmail"
            component={GmailIntegrationDetails}
          />
          <Route
            path="/inboxes/:inbox_id/integrations/google"
            component={GoogleIntegrationDetails}
          />
          <Route
            path="/inboxes/:inbox_id/integrations/mattermost"
            component={MattermostIntegrationDetails}
          />
          <Route
            path="/inboxes/:inbox_id/integrations/twilio"
            component={TwilioIntegrationDetails}
          />
          <Route
            path="/inboxes/:inbox_id/email-forwarding"
            component={InboxEmailForwardingPage}
          />
          <Route path="/inboxes/:inbox_id" component={InboxDetailsPage} />
          <Route path="/inboxes" component={InboxesOverview} />
          <Route path="*" render={() => <Redirect to="/conversations/all" />} />
        </Switch>
      </Layout>
    </Layout>
  );
};

export default InboxesDashboard;
