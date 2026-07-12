import React from 'react';
import type {InputRef} from 'antd';
import {Box, Flex} from '../ui';
import {
  message,
  notification,
  Button,
  Container,
  Divider,
  Input,
  Paragraph,
  Select,
  Text,
  Title,
} from '../common';
import Spinner from '../Spinner';
import AccountUsersTable from './AccountUsersTable';
import DisabledUsersTable from './DisabledUsersTable';
import * as API from '../../api';
import {Account, User} from '../../types';
import {FRONTEND_BASE_URL, isUserInvitationEmailEnabled} from '../../config';
import {sleep, hasValidStripeKey} from '../../utils';
import logger from '../../logger';

type Props = {};
type State = {
  account: Account | null;
  addMemberEmail: string;
  addMemberRole: 'user' | 'admin';
  currentUser: User | null;
  inviteUrl: string;
  inviteUserEmail: string;
  isAddingMember: boolean;
  isLoading: boolean;
  isRefreshing: boolean;
  showInviteMoreInput: boolean;
};

class TeamOverview extends React.Component<Props, State> {
  input: InputRef | null = null;

  state: State = {
    account: null,
    addMemberEmail: '',
    addMemberRole: 'user',
    currentUser: null,
    inviteUrl: '',
    inviteUserEmail: '',
    isAddingMember: false,
    isLoading: true,
    isRefreshing: false,
    showInviteMoreInput: false,
  };

  async componentDidMount() {
    await this.fetchLatestAccountInfo();
    const currentUser = await API.me();

    this.setState({currentUser, isLoading: false});
  }

  fetchLatestAccountInfo = async () => {
    const account = await API.fetchAccountInfo();
    logger.debug('Account info:', account);
    this.setState({account});
  };

  hasAdminRole = () => {
    return this.state.currentUser?.role === 'admin';
  };

  handleGenerateInviteUrl = async () => {
    try {
      const {id: token} = await API.generateUserInvitation();

      this.setState(
        {
          inviteUrl: `${FRONTEND_BASE_URL}/register/${token}`,
        },
        () => this.focusAndHighlightInput()
      );
    } catch (err) {
      const hasServerErrorMessage = !!err?.response?.body?.error?.message;
      const shouldDisplayBillingLink =
        hasServerErrorMessage && hasValidStripeKey();
      const description =
        err?.response?.body?.error?.message || err?.message || String(err);

      notification.error({
        message: hasServerErrorMessage
          ? 'Please upgrade to add more users!'
          : 'Failed to generate user invitation!',
        description,
        duration: 10, // 10 seconds
        // Only offer an upgrade CTA when billing (Stripe) is actually
        // configured; a self-hosted instance without Stripe has nowhere
        // sensible to send the user (papercups.io/pricing is the upstream
        // SaaS, not this fork).
        btn: shouldDisplayBillingLink ? (
          <a href="/billing">
            <Button type="primary" size="small">
              Upgrade subscription
            </Button>
          </a>
        ) : undefined,
      });
    }
  };

  handleSendInviteEmail = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();

    try {
      const {inviteUserEmail} = this.state;
      await API.sendUserInvitationEmail(inviteUserEmail);
      notification.success({
        message: `Invitation was successfully sent to ${inviteUserEmail}!`,
        duration: 10, // 10 seconds
      });

      this.setState({inviteUserEmail: ''});
    } catch (err) {
      // TODO: consolidate error logic with handleGenerateInviteUrl
      const hasServerErrorMessage = !!err?.response?.body?.error?.message;
      const shouldDisplayBillingLink =
        hasServerErrorMessage && hasValidStripeKey();
      const description =
        err?.response?.body?.error?.message || err?.message || String(err);

      notification.error({
        message: hasServerErrorMessage
          ? 'Please upgrade to add more users!'
          : 'Failed to generate user invitation!',
        description,
        duration: 10, // 10 seconds
        // Only offer an upgrade CTA when billing (Stripe) is actually
        // configured; a self-hosted instance without Stripe has nowhere
        // sensible to send the user (papercups.io/pricing is the upstream
        // SaaS, not this fork).
        btn: shouldDisplayBillingLink ? (
          <a href="/billing">
            <Button type="primary" size="small">
              Upgrade subscription
            </Button>
          </a>
        ) : undefined,
      });
    }
  };

  focusAndHighlightInput = () => {
    if (!this.input) {
      return;
    }

    this.input.focus();
    this.input.select();

    if (document.queryCommandSupported('copy')) {
      document.execCommand('copy');
      notification.open({
        message: 'Copied to clipboard!',
        description:
          'You can now paste your unique invitation URL to a teammate.',
      });
    }
  };

  handleChangeInviteUserEmail = (e: React.ChangeEvent<HTMLInputElement>) => {
    this.setState({inviteUserEmail: e.target.value});
  };

  handleChangeAddMemberEmail = (e: React.ChangeEvent<HTMLInputElement>) => {
    this.setState({addMemberEmail: e.target.value});
  };

  handleChangeAddMemberRole = (role: 'user' | 'admin') => {
    this.setState({addMemberRole: role});
  };

  handleAddExistingMember = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();

    const {addMemberEmail, addMemberRole} = this.state;

    this.setState({isAddingMember: true});

    try {
      const member = await API.addAccountMember(addMemberEmail, addMemberRole);

      message.success(`Successfully added ${member.email} to your workspace!`);
      this.setState({addMemberEmail: '', addMemberRole: 'user'});
      // Refresh the team list so the newly added member shows up.
      await this.fetchLatestAccountInfo();
    } catch (err) {
      const status = err?.response?.status ?? err?.status;
      const description =
        status === 404
          ? 'No user found with that email'
          : err?.response?.body?.error?.message || err?.message || String(err);

      message.error(description);
    } finally {
      this.setState({isAddingMember: false});
    }
  };

  handleDisableUser = async ({id: userId}: User) => {
    this.setState({isRefreshing: true});

    return API.disableAccountUser(userId)
      .then((user) => {
        notification.success({
          message: 'Successfully disabled user!',
          description: `If this was a mistake, you can renable ${user.email} below.`,
        });
      })
      .then(() => sleep(400)) // Add slight delay so not too jarring
      .then(() => this.fetchLatestAccountInfo())
      .catch((err) => {
        const description =
          err?.response?.body?.error?.message ||
          err?.message ||
          'Something went wrong. Please contact us or try again in a few minutes.';
        notification.error({
          message: 'Failed to disable user!',
          description,
        });
      })
      .then(() => this.setState({isRefreshing: false}));
  };

  handleUpdateRole = async ({id: userId}: User, role: 'user' | 'admin') => {
    this.setState({isRefreshing: true});

    return API.updateAccountMemberRole(userId, role)
      .then((member) => {
        notification.success({
          message: 'Successfully changed role!',
          description: `${member.email} is now ${
            role === 'user' ? 'a team member' : 'an admin'
          }.`,
        });
      })
      .then(() => sleep(400)) // Add slight delay so not too jarring
      .then(() => this.fetchLatestAccountInfo())
      .catch((err) => {
        // e.g. 422 when demoting the last admin of the workspace
        const description =
          err?.response?.body?.error?.message ||
          err?.message ||
          'Something went wrong. Please contact us or try again in a few minutes.';
        notification.error({
          message: 'Failed to update role!',
          description,
        });
      })
      .then(() => this.setState({isRefreshing: false}));
  };

  handleRemoveMember = async ({id: userId, email}: User) => {
    this.setState({isRefreshing: true});

    return API.removeAccountMember(userId)
      .then(() => {
        notification.success({
          message: 'Successfully removed member!',
          description: `${email} no longer has access to this workspace.`,
        });
      })
      .then(() => sleep(400)) // Add slight delay so not too jarring
      .then(() => this.fetchLatestAccountInfo())
      .catch((err) => {
        // e.g. 422 for a member's primary workspace or the last admin
        const description =
          err?.response?.body?.error?.message ||
          err?.message ||
          'Something went wrong. Please contact us or try again in a few minutes.';
        notification.error({
          message: 'Failed to remove member!',
          description,
        });
      })
      .then(() => this.setState({isRefreshing: false}));
  };

  handleEnableUser = async ({id: userId}: User) => {
    this.setState({isRefreshing: true});

    return API.enableAccountUser(userId)
      .then((user) => {
        notification.success({
          message: 'Successfully re-enabled user!',
          description: `If this was a mistake, you can disable ${user.email} above.`,
        });
      })
      .then(() => sleep(400)) // Add slight delay so not too jarring
      .then(() => this.fetchLatestAccountInfo())
      .catch((err) => {
        const description =
          err?.response?.body?.error?.message ||
          err?.message ||
          'Something went wrong. Please contact us or try again in a few minutes.';
        notification.error({
          message: 'Failed to enable user!',
          description,
        });
      })
      .then(() => this.setState({isRefreshing: false}));
  };

  handleArchiveUser = async ({id: userId}: User) => {
    this.setState({isRefreshing: true});

    return API.archiveAccountUser(userId)
      .then((user) => {
        notification.success({
          message: 'Successfully archived user!',
          description: `If this was a mistake, please notify us and we will reverse the action.`,
        });
      })
      .then(() => sleep(400)) // Add slight delay so not too jarring
      .then(() => this.fetchLatestAccountInfo())
      .catch((err) => {
        const description =
          err?.response?.body?.error?.message ||
          err?.message ||
          'Something went wrong. Please contact us or try again in a few minutes.';
        notification.error({
          message: 'Failed to archive user!',
          description,
        });
      })
      .then(() => this.setState({isRefreshing: false}));
  };

  handleClickOnInviteMoreLink = () => {
    this.setState({showInviteMoreInput: true});
  };

  render() {
    const {
      account,
      addMemberEmail,
      addMemberRole,
      currentUser,
      inviteUrl,
      inviteUserEmail,
      isAddingMember,
      isLoading,
      isRefreshing,
      showInviteMoreInput,
    } = this.state;

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
    } else if (!account || !currentUser) {
      return null;
    }

    const {users = []} = account;
    const isAdmin = this.hasAdminRole();

    return (
      <Container sx={{maxWidth: 960}}>
        <Box mb={4}>
          <Title level={3}>My Team</Title>
        </Box>

        {isAdmin && (
          <>
            <Box mb={4}>
              <Title level={4}>Invite new teammate</Title>

              <Paragraph>
                <Text>
                  Generate a unique invitation URL below and send it to your
                  teammate.
                </Text>
              </Paragraph>

              <Flex sx={{maxWidth: 640}}>
                <Box mr={1}>
                  <Button type="primary" onClick={this.handleGenerateInviteUrl}>
                    Generate invite URL
                  </Button>
                </Box>
                <Box sx={{flex: 1}}>
                  <Input
                    ref={(el) => {
                      this.input = el;
                    }}
                    type="text"
                    placeholder="Click the button to generate an invite URL"
                    disabled={!inviteUrl}
                    value={inviteUrl}
                  ></Input>
                </Box>
              </Flex>
            </Box>

            <Box mb={4}>
              <Title level={4}>Add existing member</Title>

              <Paragraph>
                <Text>
                  Add a user who already has an account to this workspace by
                  email.
                </Text>
              </Paragraph>

              <form
                aria-label="Add existing member"
                onSubmit={this.handleAddExistingMember}
              >
                <Flex sx={{maxWidth: 640}}>
                  <Box mr={1} sx={{flex: 1}}>
                    <Input
                      aria-label="Member email"
                      onChange={this.handleChangeAddMemberEmail}
                      placeholder="Email address"
                      required
                      type="email"
                      value={addMemberEmail}
                    />
                  </Box>
                  <Box mr={1}>
                    <Select
                      aria-label="Member role"
                      style={{width: 120}}
                      value={addMemberRole}
                      onChange={this.handleChangeAddMemberRole}
                      options={[
                        {value: 'user', label: 'User'},
                        {value: 'admin', label: 'Admin'},
                      ]}
                    />
                  </Box>
                  <Button
                    type="primary"
                    htmlType="submit"
                    loading={isAddingMember}
                  >
                    Add
                  </Button>
                </Flex>
              </form>
            </Box>
            <Divider />
          </>
        )}

        <Box mb={4}>
          <Title level={4}>Team</Title>

          <AccountUsersTable
            loading={isRefreshing}
            users={users.filter((u: User) => !u.disabled_at)}
            currentUser={currentUser}
            isAdmin={isAdmin}
            onDisableUser={this.handleDisableUser}
            onUpdateRole={this.handleUpdateRole}
            onRemoveMember={this.handleRemoveMember}
          />

          {isAdmin && isUserInvitationEmailEnabled && (
            <Box mt={2}>
              {showInviteMoreInput ? (
                <form onSubmit={this.handleSendInviteEmail}>
                  <Flex sx={{maxWidth: 480}}>
                    <Box mr={1} sx={{flex: 1}}>
                      <Input
                        onChange={this.handleChangeInviteUserEmail}
                        placeholder="Email address"
                        required
                        type="email"
                        value={inviteUserEmail}
                      />
                    </Box>
                    <Button type="primary" htmlType="submit">
                      Send invite
                    </Button>
                  </Flex>
                </form>
              ) : (
                <Button
                  type="primary"
                  onClick={this.handleClickOnInviteMoreLink}
                >
                  Invite teammate
                </Button>
              )}
            </Box>
          )}
        </Box>

        {isAdmin && (
          <Box mb={4}>
            <Title level={4}>Disabled users</Title>
            <DisabledUsersTable
              loading={isRefreshing}
              users={users.filter((u: User) => !!u.disabled_at)}
              isAdmin={isAdmin}
              onEnableUser={this.handleEnableUser}
              onArchiveUser={this.handleArchiveUser}
            />
          </Box>
        )}
      </Container>
    );
  }
}

export default TeamOverview;
