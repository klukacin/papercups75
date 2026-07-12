import React from 'react';
import {Box} from '../ui';
import {
  Button,
  Divider,
  Input,
  message,
  Modal,
  Popover,
  Text,
  Tooltip,
} from '../common';
import {CheckOutlined, TeamOutlined} from '../icons';
import * as API from '../../api';
import logger from '../../logger';
import {Account} from '../../types';
import {getCurrentAccountId, setCurrentAccountId} from '../../storage';
import {useAuth} from '../auth/AuthProvider';

// Lets a user switch which workspace (account) the dashboard is scoped to and
// create new workspaces. Selecting an account persists the id (sent as the
// `X-Account-Id` header on every authenticated request) and reloads the app so
// all data refetches under the newly selected account.
//
// Always renders (even for a single workspace) since it also hosts the
// "Create new workspace" action.
const AccountSwitcher = () => {
  const {account: primaryAccount, currentUser} = useAuth();
  // Creating workspaces is an instance-superadmin-only action (the server
  // rejects it with a 403 for everyone else), so hide the menu item otherwise.
  const isSuperadmin = !!currentUser?.is_superadmin;
  const [accounts, setAccounts] = React.useState<Array<Account>>([]);
  const [isPopoverOpen, setPopoverOpen] = React.useState(false);
  const [isCreateModalOpen, setCreateModalOpen] = React.useState(false);
  const [companyName, setCompanyName] = React.useState('');
  const [isCreating, setCreating] = React.useState(false);

  React.useEffect(() => {
    let mounted = true;

    API.fetchAccounts()
      .then((results) => {
        if (mounted) {
          setAccounts(results || []);
        }
      })
      .catch((err) => {
        logger.error('Failed to fetch accounts:', err);
      });

    return () => {
      mounted = false;
    };
  }, []);

  // Fall back to the user's primary account (from `/me`) when no account has
  // been explicitly selected yet.
  const selectedAccountId = getCurrentAccountId() || primaryAccount?.id || null;

  const handleSelectAccount = (accountId: string) => {
    if (accountId === selectedAccountId) {
      return;
    }

    setCurrentAccountId(accountId);
    // Full reload so every provider/query refetches under the new account.
    window.location.reload();
  };

  const handleCancelCreateWorkspace = () => {
    setCreateModalOpen(false);
    setCompanyName('');
  };

  const handleCreateWorkspace = async () => {
    const name = companyName.trim();

    if (!name || isCreating) {
      return;
    }

    setCreating(true);

    try {
      const created = await API.createWorkspace(name);

      setCurrentAccountId(created.id);
      // Full reload so the app boots scoped to the new workspace.
      window.location.reload();
    } catch (err) {
      const description =
        err?.response?.body?.error?.message || err?.message || String(err);

      message.error(description);
      setCreating(false);
    }
  };

  // NB: deliberately NOT an antd Dropdown/Menu. This component lives inside the
  // Dashboard <Sider>, whose context leaks into Menu (even through the popup
  // portal, since React context follows the component tree) and renders it in
  // inline-collapsed mode - menu labels collapse to their first letter. A
  // Popover with a plain button list has no Menu context to inherit.
  const popoverContent = (
    <Box sx={{minWidth: 220}} role="menu">
      {accounts.map((account) => {
        const isSelected = account.id === selectedAccountId;

        return (
          <Button
            key={account.id}
            type="text"
            block
            role="menuitem"
            style={{textAlign: 'left'}}
            onClick={() => {
              setPopoverOpen(false);
              handleSelectAccount(account.id);
            }}
          >
            {isSelected && (
              <CheckOutlined style={{marginRight: 8, color: '#1890ff'}} />
            )}
            {account.company_name || 'Untitled account'}
          </Button>
        );
      })}

      {isSuperadmin && (
        <>
          <Divider style={{margin: '8px 0'}} />

          <Button
            type="text"
            block
            role="menuitem"
            style={{textAlign: 'left'}}
            onClick={() => {
              setPopoverOpen(false);
              setCreateModalOpen(true);
            }}
          >
            Create new workspace
          </Button>
        </>
      )}
    </Box>
  );

  return (
    <>
      <Popover
        placement="rightTop"
        trigger="click"
        open={isPopoverOpen}
        onOpenChange={setPopoverOpen}
        content={popoverContent}
      >
        <Tooltip title="Switch account" placement="right">
          <Button
            type="text"
            icon={<TeamOutlined style={{color: 'rgba(255, 255, 255, 0.65)'}} />}
            aria-label="Switch account"
          />
        </Tooltip>
      </Popover>

      <Modal
        title="Create new workspace"
        open={isCreateModalOpen}
        onOk={handleCreateWorkspace}
        onCancel={handleCancelCreateWorkspace}
        footer={[
          <Button
            key="cancel"
            onClick={handleCancelCreateWorkspace}
            disabled={isCreating}
          >
            Cancel
          </Button>,
          <Button
            key="submit"
            type="primary"
            loading={isCreating}
            disabled={isCreating || !companyName.trim()}
            onClick={handleCreateWorkspace}
          >
            Create
          </Button>,
        ]}
      >
        <Box>
          <label htmlFor="company-name">
            <Text strong>Company name</Text>
          </label>

          <Input
            id="company-name"
            type="text"
            required
            size="large"
            value={companyName}
            placeholder="e.g. Acme Inc"
            disabled={isCreating}
            onChange={(e) => setCompanyName(e.target.value)}
            onPressEnter={handleCreateWorkspace}
          />
        </Box>
      </Modal>
    </>
  );
};

export default AccountSwitcher;
