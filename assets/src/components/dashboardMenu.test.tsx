import {
  buildPrimaryMenuItems,
  buildSecondaryMenuItems,
} from './dashboardMenu';

const keysOf = (items: any[]): string[] =>
  (items || []).filter(Boolean).map((i: any) => i.key);

describe('dashboard menu builders', () => {
  it('includes admin-only sections for admins', () => {
    const items = buildPrimaryMenuItems({
      isAdminUser: true,
      shouldHighlightInbox: false,
      totalNumUnread: 3,
      shouldDisplayBilling: true,
    });
    const keys = keysOf(items as any[]);

    expect(keys).toEqual(
      expect.arrayContaining([
        'getting-started',
        'conversations',
        'integrations',
        'customers',
        'reporting',
        'developers',
        'sessions',
        'settings',
      ])
    );

    const settings: any = (items as any[]).find((i) => i && i.key === 'settings');
    expect(keysOf(settings.children)).toContain('billing');
  });

  it('hides admin-only sections for non-admins', () => {
    const items = buildPrimaryMenuItems({
      isAdminUser: false,
      shouldHighlightInbox: false,
      totalNumUnread: 0,
      shouldDisplayBilling: false,
    });
    const keys = keysOf(items as any[]);

    expect(keys).not.toContain('getting-started');
    expect(keys).not.toContain('integrations');
    expect(keys).not.toContain('developers');
    expect(keys).toContain('conversations');

    const settings: any = (items as any[]).find((i) => i && i.key === 'settings');
    // Non-admin settings submenu is limited to profile + saved replies.
    expect(keysOf(settings.children)).toEqual(['profile', 'saved-replies']);
  });

  it('omits billing when shouldDisplayBilling is false (admin)', () => {
    const items = buildPrimaryMenuItems({
      isAdminUser: true,
      shouldHighlightInbox: false,
      totalNumUnread: 0,
      shouldDisplayBilling: false,
    });
    const settings: any = (items as any[]).find((i) => i && i.key === 'settings');
    expect(keysOf(settings.children)).not.toContain('billing');
  });

  it('secondary menu shows chat only when enabled', () => {
    const withChat = buildSecondaryMenuItems({
      showChat: true,
      onChatClick: () => {},
      onLogout: () => {},
    });
    const withoutChat = buildSecondaryMenuItems({
      showChat: false,
      onChatClick: () => {},
      onLogout: () => {},
    });

    expect(keysOf(withChat as any[])).toEqual(['chat', 'logout']);
    expect(keysOf(withoutChat as any[])).toEqual(['logout']);
  });
});
