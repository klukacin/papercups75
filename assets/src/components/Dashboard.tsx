import React, {useEffect, useRef, useState} from 'react';
import {
  useLocation,
  useParams,
  Navigate,
  Route,
  Routes,
  Link,
} from 'react-router-dom';
import {RouteComponentProps, withRouter} from '../router-compat';
import {Helmet} from 'react-helmet';
import {Box, Flex} from 'theme-ui';
import {ChatWidget, Papercups} from '@papercups-io/chat-widget';
// import {Storytime} from '../lib/storytime'; // For testing
import {Storytime} from '@papercups-io/storytime';
import {colors, Layout, Menu, Sider} from './common';
import {SettingOutlined} from './icons';
import {buildPrimaryMenuItems, buildSecondaryMenuItems} from './dashboardMenu';
import {
  BASE_URL,
  env,
  isDev,
  isEuEdition,
  isHostedProd,
  isStorytimeEnabled,
} from '../config';
import {SOCKET_URL} from '../socket';
import analytics from '../analytics';
import {
  DASHBOARD_COLLAPSED_SIDER_WIDTH,
  formatUserExternalId,
  getBrowserVisibilityInfo,
  hasValidStripeKey,
  isWindowHidden,
} from '../utils';
import {Account, User} from '../types';
import {useAuth} from './auth/AuthProvider';
import {SocketProvider, SocketContext} from './auth/SocketProvider';
import AccountSwitcher from './account/AccountSwitcher';
import AccountOverview from './settings/AccountOverview';
import TeamOverview from './settings/TeamOverview';
import UserProfile from './settings/UserProfile';
import ChatWidgetSettings from './settings/ChatWidgetSettings';
import {
  ConversationsContext,
  ConversationsProvider,
  useConversations,
} from './conversations/ConversationsProvider';
import NotificationsProvider from './conversations/NotificationsProvider';
import IntegrationsOverview from './integrations/IntegrationsOverview';
import SlackReplyIntegrationDetails from './integrations/SlackReplyIntegrationDetails';
import SlackSyncIntegrationDetails from './integrations/SlackSyncIntegrationDetails';
import SlackIntegrationDetails from './integrations/SlackIntegrationDetails';
import GmailIntegrationDetails from './integrations/GmailIntegrationDetails';
import GoogleSheetsIntegrationDetails from './integrations/GoogleSheetsIntegrationDetails';
import GoogleIntegrationDetails from './integrations/GoogleIntegrationDetails';
import MattermostIntegrationDetails from './integrations/MattermostIntegrationDetails';
import TwilioIntegrationDetails from './integrations/TwilioIntegrationDetails';
import GithubIntegrationDetails from './integrations/GithubIntegrationDetails';
import HubspotIntegrationDetails from './integrations/HubspotIntegrationDetails';
import IntercomIntegrationDetails from './integrations/IntercomIntegrationDetails';
import BillingOverview from './billing/BillingOverview';
import CustomersPage from './customers/CustomersPage';
import CustomerDetailsPage from './customers/CustomerDetailsPage';
import CustomerDetailsPageV2 from './customers/CustomerDetailsPageV2';
import SessionsOverview from './sessions/SessionsOverview';
import InstallingStorytime from './sessions/InstallingStorytime';
import LiveSessionViewer from './sessions/LiveSessionViewer';
import ReportingDashboard from './reporting/ReportingDashboard';
import CompaniesPage from './companies/CompaniesPage';
import CreateCompanyPage from './companies/CreateCompanyPage';
import UpdateCompanyPage from './companies/UpdateCompanyPage';
import CompanyDetailsPage from './companies/CompanyDetailsPage';
import GettingStarted from './getting-started/GettingStarted';
import TagsOverview from './tags/TagsOverview';
import TagDetailsPage from './tags/TagDetailsPage';
import IssuesOverview from './issues/IssuesOverview';
import IssueDetailsPage from './issues/IssueDetailsPage';
import NotesOverview from './notes/NotesOverview';
import PersonalApiKeysPage from './developers/PersonalApiKeysPage';
import EventSubscriptionsPage from './developers/EventSubscriptionsPage';
import EmailTemplateBuilder from './developers/EmailTemplateBuilder';
import LambdaDetailsPage from './lambdas/LambdaDetailsPage';
import LambdasOverview from './lambdas/LambdasOverview';
import CannedResponsesOverview from './canned-responses/CannedResponsesOverview';
import ForwardingAddressSettings from './settings/ForwardingAddressSettings';
import InboxesDashboard from './inboxes/InboxesDashboard';

const {REACT_APP_ADMIN_ACCOUNT_ID = 'eb504736-0f20-4978-98ff-1a82ae60b266'} =
  env;

const TITLE_FLASH_INTERVAL = 2000;

const shouldDisplayChat = (pathname: string) => {
  return isHostedProd && pathname !== '/settings/chat-widget';
};

const getSectionKey = (pathname: string) => {
  if (pathname.startsWith('/companies')) {
    return ['customers', 'companies'];
  } else if (pathname.startsWith('/customers')) {
    return ['customers', 'people'];
  } else if (pathname.startsWith('/tags')) {
    return ['customers', 'tags'];
  } else if (pathname.startsWith('/notes')) {
    return ['customers', 'notes'];
  } else if (pathname.startsWith('/functions')) {
    return ['developers', 'functions'];
  } else if (pathname.startsWith('/inboxes')) {
    return ['conversations', ...pathname.split('/').slice(2)];
  } else {
    return pathname.split('/').slice(1); // Slice off initial slash
  }
};

const useWindowVisibility = (d?: Document) => {
  const doc = d || document || window.document;
  const [isWindowVisible, setWindowVisible] = useState(!isWindowHidden(doc));

  useEffect(() => {
    const {event} = getBrowserVisibilityInfo(doc);
    const handler = () => setWindowVisible(!isWindowHidden(doc));

    if (!event) {
      return;
    }

    doc.addEventListener(event, handler, false);

    return () => doc.removeEventListener(event, handler);
  }, [doc]);

  return isWindowVisible;
};

const ChatWithUs = ({
  currentUser,
  account,
}: {
  currentUser: User;
  account?: Account | null;
}) => {
  if (isEuEdition) {
    return (
      <ChatWidget
        token={REACT_APP_ADMIN_ACCOUNT_ID}
        accountId={REACT_APP_ADMIN_ACCOUNT_ID}
        title="Need help with anything?"
        subtitle="Ask us in the chat window below 😊"
        greeting="Hi there! Send us a message and we'll get back to you as soon as we can."
        primaryColor="#1890ff"
        hideToggleButton
        baseUrl="https://app.papercups-eu.io"
        customer={{
          external_id: formatUserExternalId(currentUser),
          email: currentUser.email,
          metadata: {
            company_name: account?.company_name,
            subscription_plan: account?.subscription_plan,
            edition: 'EU',
          },
        }}
      />
    );
  }

  return (
    <ChatWidget
      token={REACT_APP_ADMIN_ACCOUNT_ID}
      accountId={REACT_APP_ADMIN_ACCOUNT_ID}
      title="Need help with anything?"
      subtitle="Ask us in the chat window below 😊"
      greeting="Hi there! Send us a message and we'll get back to you as soon as we can."
      primaryColor="#1890ff"
      hideToggleButton
      customer={{
        external_id: formatUserExternalId(currentUser),
        email: currentUser.email,
        metadata: {
          company_name: account?.company_name,
          subscription_plan: account?.subscription_plan,
          edition: 'US',
        },
      }}
    />
  );
};

// TODO: not sure if this is the best way to handle this, but the goal
// of this component is to flash the number of unread messages in the
// tab (i.e. HTML title) so users can see when new messages arrive
const DashboardHtmlHead = ({totalNumUnread}: {totalNumUnread: number}) => {
  const doc = document || window.document;
  const [htmlTitle, setHtmlTitle] = useState('Papercups');
  const isWindowVisible = useWindowVisibility(doc);
  const timer = useRef<any>(undefined);

  const hasDefaultTitle = (title: string) => title.startsWith('Papercups');

  const toggleNotificationMessage = () => {
    if (totalNumUnread > 0 && hasDefaultTitle(htmlTitle) && !isWindowVisible) {
      setHtmlTitle(
        `(${totalNumUnread}) New message${totalNumUnread === 1 ? '' : 's'}!`
      );
    } else {
      setHtmlTitle('Papercups');
    }
  };

  useEffect(() => {
    const shouldToggle =
      totalNumUnread > 0 && (!isWindowVisible || !hasDefaultTitle(htmlTitle));

    if (shouldToggle) {
      timer.current = setTimeout(
        toggleNotificationMessage,
        TITLE_FLASH_INTERVAL
      );
    } else {
      clearTimeout(timer.current);
    }

    return () => clearTimeout(timer.current);
  });

  return (
    <Helmet defer={false}>
      <title>{totalNumUnread ? htmlTitle : 'Papercups'}</title>
    </Helmet>
  );
};

// Preserves the v5 `<Redirect from="/account*" to="/settings*" />` behavior
// by carrying over whatever came after the `/account` prefix.
const RedirectToSettings = () => {
  const params = useParams();
  const splat = params['*'] || '';

  return <Navigate to={splat ? `/settings/${splat}` : '/settings'} replace />;
};

const Dashboard = (props: RouteComponentProps) => {
  const auth = useAuth();
  const {pathname} = useLocation();
  const {unread} = useConversations();

  const {currentUser, account} = auth;
  const isAdminUser = currentUser?.role === 'admin';

  const [section, key] = getSectionKey(pathname);
  const totalNumUnread = unread.conversations.open || 0;
  const shouldDisplayBilling = hasValidStripeKey();
  const shouldHighlightInbox =
    totalNumUnread > 0 && section !== 'conversations';

  const logout = () => auth.logout().then(() => props.history.push('/login'));

  useEffect(() => {
    if (currentUser && currentUser.id) {
      const {email} = currentUser;
      const id = formatUserExternalId(currentUser);

      analytics.identify(id, email);
    }

    if (isStorytimeEnabled && currentUser) {
      const {email} = currentUser;
      // TODO: figure out a better way to initialize this?
      const storytime = Storytime.init({
        accountId: REACT_APP_ADMIN_ACCOUNT_ID,
        baseUrl: BASE_URL,
        debug: isDev,
        customer: {
          email,
          external_id: formatUserExternalId(currentUser),
        },
      });

      return () => storytime.finish();
    }
  }, [currentUser]);

  return (
    <Layout>
      <DashboardHtmlHead totalNumUnread={totalNumUnread} />

      <Sider
        width={DASHBOARD_COLLAPSED_SIDER_WIDTH}
        collapsed={true}
        style={{
          overflow: 'auto',
          height: '100vh',
          position: 'fixed',
          left: 0,
          color: colors.white,
        }}
      >
        <Flex sx={{flexDirection: 'column', height: '100%'}}>
          <Box py={3} sx={{flex: 1}}>
            <Menu
              selectedKeys={[section, key]}
              mode="inline"
              theme="dark"
              items={buildPrimaryMenuItems({
                isAdminUser,
                shouldHighlightInbox,
                totalNumUnread,
                shouldDisplayBilling,
              })}
            />
          </Box>

          <Flex sx={{justifyContent: 'center'}}>
            <AccountSwitcher />
          </Flex>

          <Box py={3}>
            <Menu
              mode="inline"
              theme="dark"
              selectable={false}
              items={buildSecondaryMenuItems({
                showChat: shouldDisplayChat(pathname),
                onChatClick: Papercups.toggle,
                onLogout: logout,
              })}
            />
          </Box>
        </Flex>
      </Sider>

      <Layout
        style={{
          marginLeft: DASHBOARD_COLLAPSED_SIDER_WIDTH,
          background: colors.white,
        }}
      >
        <Routes>
          <Route path="/getting-started" element={<GettingStarted />} />

          {/* Temporary redirect routes to point from /accounts/* to /settings/* */}
          <Route
            path="/account/overview"
            element={<Navigate to="/settings/overview" replace />}
          />
          <Route
            path="/account/team"
            element={<Navigate to="/settings/team" replace />}
          />
          <Route
            path="/account/profile"
            element={<Navigate to="/settings/profile" replace />}
          />
          <Route
            path="/account/getting-started"
            element={<Navigate to="/settings/chat-widget" replace />}
          />
          <Route path="/account/*" element={<RedirectToSettings />} />
          <Route
            path="/account"
            element={<Navigate to="/settings" replace />}
          />
          <Route
            path="/billing"
            element={<Navigate to="/settings/billing" replace />}
          />
          <Route
            path="/saved-replies"
            element={<Navigate to="/settings/saved-replies" replace />}
          />

          <Route path="/settings/account" element={<AccountOverview />} />
          <Route path="/settings/team" element={<TeamOverview />} />
          <Route path="/settings/profile" element={<UserProfile />} />
          <Route
            path="/settings/saved-replies"
            element={<CannedResponsesOverview />}
          />
          <Route
            path="/settings/email-forwarding"
            element={<ForwardingAddressSettings />}
          />
          <Route
            path="/settings/chat-widget"
            element={<ChatWidgetSettings />}
          />
          {shouldDisplayBilling && (
            <Route path="/settings/billing" element={<BillingOverview />} />
          )}
          <Route path="/settings/*" element={<AccountOverview />} />
          <Route path="/v1/customers/:id" element={<CustomerDetailsPage />} />
          <Route path="/customers/:id" element={<CustomerDetailsPageV2 />} />
          <Route path="/customers" element={<CustomersPage />} />
          <Route path="/companies/new" element={<CreateCompanyPage />} />
          <Route path="/companies/:id/edit" element={<UpdateCompanyPage />} />
          <Route path="/companies/:id" element={<CompanyDetailsPage />} />
          <Route path="/companies" element={<CompaniesPage />} />
          <Route
            path="/integrations/slack/reply"
            element={<SlackReplyIntegrationDetails />}
          />
          <Route
            path="/integrations/slack/support"
            element={<SlackSyncIntegrationDetails />}
          />
          <Route
            path="/integrations/slack"
            element={<SlackIntegrationDetails />}
          />
          <Route
            path="/integrations/google/gmail"
            element={<GmailIntegrationDetails />}
          />
          <Route
            path="/integrations/google/sheets"
            element={<GoogleSheetsIntegrationDetails />}
          />
          <Route
            path="/integrations/google"
            element={<GoogleIntegrationDetails />}
          />
          <Route
            path="/integrations/mattermost"
            element={<MattermostIntegrationDetails />}
          />
          <Route
            path="/integrations/twilio"
            element={<TwilioIntegrationDetails />}
          />
          <Route
            path="/integrations/github"
            element={<GithubIntegrationDetails />}
          />
          <Route
            path="/integrations/hubspot"
            element={<HubspotIntegrationDetails />}
          />
          <Route
            path="/integrations/intercom"
            element={<IntercomIntegrationDetails />}
          />
          <Route
            path="/integrations/:type"
            element={<IntegrationsOverview />}
          />
          <Route path="/integrations" element={<IntegrationsOverview />} />
          <Route path="/integrations/*" element={<IntegrationsOverview />} />
          <Route
            path="/developers/personal-api-keys"
            element={<PersonalApiKeysPage />}
          />
          <Route
            path="/developers/event-subscriptions"
            element={<EventSubscriptionsPage />}
          />
          <Route
            path="/developers/_templates"
            element={<EmailTemplateBuilder />}
          />
          <Route path="/functions/:id" element={<LambdaDetailsPage />} />
          <Route path="/functions" element={<LambdasOverview />} />
          <Route path="/reporting" element={<ReportingDashboard />} />
          <Route
            path="/sessions/live/:session"
            element={<LiveSessionViewer />}
          />
          <Route path="/sessions/list" element={<SessionsOverview />} />
          <Route path="/sessions/setup" element={<InstallingStorytime />} />
          <Route path="/sessions/*" element={<SessionsOverview />} />
          <Route path="/tags/:id" element={<TagDetailsPage />} />
          <Route path="/tags" element={<TagsOverview />} />
          <Route path="/issues/:id" element={<IssueDetailsPage />} />
          <Route path="/issues" element={<IssuesOverview />} />
          <Route path="/notes" element={<NotesOverview />} />
          <Route path="/conversations/*" element={<InboxesDashboard />} />
          <Route path="/inboxes/*" element={<InboxesDashboard />} />
          <Route
            path="*"
            element={<Navigate to="/conversations/all" replace />}
          />
        </Routes>
      </Layout>

      {currentUser && shouldDisplayChat(pathname) && (
        <ChatWithUs currentUser={currentUser} account={account} />
      )}
    </Layout>
  );
};

const DashboardWrapper = (props: RouteComponentProps) => {
  const {refresh} = useAuth();

  return (
    <SocketProvider url={SOCKET_URL} refresh={refresh}>
      <SocketContext.Consumer>
        {({socket}) => {
          return (
            <ConversationsProvider>
              <ConversationsContext.Consumer>
                {({onNewMessage, onNewConversation, onConversationUpdated}) => {
                  return (
                    <NotificationsProvider
                      socket={socket}
                      onNewMessage={onNewMessage}
                      onNewConversation={onNewConversation}
                      onConversationUpdated={onConversationUpdated}
                    >
                      <Dashboard {...props} />
                    </NotificationsProvider>
                  );
                }}
              </ConversationsContext.Consumer>
            </ConversationsProvider>
          );
        }}
      </SocketContext.Consumer>
    </SocketProvider>
  );
};

export default withRouter(DashboardWrapper);
