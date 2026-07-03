import {
  getCurrentAccountId,
  setCurrentAccountId,
  clearCurrentAccountId,
} from './storage';

describe('current account storage helpers', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('returns null when no account has been set', () => {
    expect(getCurrentAccountId()).toBeNull();
  });

  it('round-trips a stored account id via get/set/clear', () => {
    const accountId = 'acc_123-456-789';

    setCurrentAccountId(accountId);
    expect(getCurrentAccountId()).toEqual(accountId);

    clearCurrentAccountId();
    expect(getCurrentAccountId()).toBeNull();
  });

  it('overwrites a previously stored account id', () => {
    setCurrentAccountId('first');
    setCurrentAccountId('second');
    expect(getCurrentAccountId()).toEqual('second');
  });
});
