import {buildInboxesMenuItems} from './inboxesMenu';

const baseUnread: any = {
  conversations: {
    assigned: 1,
    mentioned: 2,
    unread: 3,
    unassigned: 4,
    priority: 5,
  },
  inboxes: {'inbox-1': 7},
};

const keysOf = (items: any[]): string[] =>
  (items || []).filter(Boolean).map((i: any) => i.key);

describe('buildInboxesMenuItems', () => {
  it('builds conversation + inbox submenus and admin actions for admins', () => {
    const items = buildInboxesMenuItems({
      totalNumUnread: 9,
      unread: baseUnread,
      inboxes: [{id: 'inbox-1', name: 'Support'} as any],
      isAdminUser: true,
      onAddInbox: () => {},
    });
    const keys = keysOf(items as any[]);
    expect(keys).toEqual(
      expect.arrayContaining([
        'conversations',
        'inboxes',
        'add-inbox',
        'inbox-settings',
      ])
    );

    const inboxesSub: any = (items as any[]).find(
      (i) => i && i.key === 'inboxes'
    );
    expect(keysOf(inboxesSub.children)).toEqual(['inbox-1']);
  });

  it('hides admin-only actions for non-admins', () => {
    const items = buildInboxesMenuItems({
      totalNumUnread: 0,
      unread: baseUnread,
      inboxes: [],
      isAdminUser: false,
      onAddInbox: () => {},
    });
    const keys = keysOf(items as any[]);
    expect(keys).not.toContain('add-inbox');
    expect(keys).not.toContain('inbox-settings');
    expect(keys).toContain('conversations');
  });

  it('add-inbox item triggers the provided callback', () => {
    let called = false;
    const items = buildInboxesMenuItems({
      totalNumUnread: 0,
      unread: baseUnread,
      inboxes: [],
      isAdminUser: true,
      onAddInbox: () => {
        called = true;
      },
    });
    const addInbox: any = (items as any[]).find(
      (i) => i && i.key === 'add-inbox'
    );
    addInbox.onClick();
    expect(called).toBe(true);
  });
});
