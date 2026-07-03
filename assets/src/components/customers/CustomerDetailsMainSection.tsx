import React from 'react';
import {History} from 'history';
import qs from 'query-string';

import {Card, Tabs} from '../common';
import CustomerDetailsConversations from './CustomerDetailsConversations';
import CustomerDetailsNotes from './CustomerDetailsNotes';
import CustomerDetailsIssues from './CustomerDetailsIssues';

enum TabKey {
  Conversations = 'Conversations',
  Notes = 'Notes',
  Issues = 'Issues',
}

const getDefaultTab = (query: string): TabKey => {
  const {tab = 'conversations'} = qs.parse(query);

  switch (tab) {
    case 'notes':
      return TabKey.Notes;
    case 'issues':
      return TabKey.Issues;
    case 'conversations':
    default:
      return TabKey.Conversations;
  }
};

type Props = {customerId: string; history: History};

const CustomerDetailsMainSection = ({customerId, history}: Props) => {
  const defaultActiveKey = getDefaultTab(history.location.search);

  return (
    <Card>
      <Tabs
        defaultActiveKey={defaultActiveKey}
        tabBarStyle={{paddingLeft: '16px', marginBottom: '0'}}
        items={[
          {
            key: TabKey.Conversations,
            label: TabKey.Conversations,
            children: (
              <CustomerDetailsConversations
                customerId={customerId}
                history={history}
              />
            ),
          },
          {
            key: TabKey.Notes,
            label: TabKey.Notes,
            children: <CustomerDetailsNotes customerId={customerId} />,
          },
          {
            key: TabKey.Issues,
            label: TabKey.Issues,
            children: <CustomerDetailsIssues customerId={customerId} />,
          },
        ]}
      />
    </Card>
  );
};

export default CustomerDetailsMainSection;
