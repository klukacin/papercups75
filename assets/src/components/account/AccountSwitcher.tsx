import React from 'react';
import {Button, Dropdown, Tooltip} from '../common';
import {CheckOutlined, TeamOutlined} from '../icons';
import * as API from '../../api';
import logger from '../../logger';
import {Account} from '../../types';
import {getCurrentAccountId, setCurrentAccountId} from '../../storage';
import {useAuth} from '../auth/AuthProvider';

// Lets a user who belongs to more than one account switch which account the
// dashboard is scoped to. Selecting an account persists the id (sent as the
// `X-Account-Id` header on every authenticated request) and reloads the app so
// all data refetches under the newly selected account.
//
// Renders nothing when the user only belongs to a single account, keeping the
// common single-account experience uncluttered.
const AccountSwitcher = () => {
  const {account: primaryAccount} = useAuth();
  const [accounts, setAccounts] = React.useState<Array<Account>>([]);

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

  if (accounts.length <= 1) {
    return null;
  }

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

  const items = accounts.map((account) => {
    const isSelected = account.id === selectedAccountId;

    return {
      key: account.id,
      label: (
        <span>
          {isSelected && (
            <CheckOutlined style={{marginRight: 8, color: '#1890ff'}} />
          )}
          {account.company_name || 'Untitled account'}
        </span>
      ),
    };
  });

  return (
    <Dropdown
      placement="topRight"
      menu={{
        items,
        selectedKeys: selectedAccountId ? [selectedAccountId] : [],
        onClick: ({key}) => handleSelectAccount(key),
      }}
    >
      <Tooltip title="Switch account" placement="right">
        <Button
          type="text"
          icon={<TeamOutlined style={{color: 'rgba(255, 255, 255, 0.65)'}} />}
          aria-label="Switch account"
        />
      </Tooltip>
    </Dropdown>
  );
};

export default AccountSwitcher;
