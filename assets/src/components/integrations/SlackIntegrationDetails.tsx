import React from 'react';
import {Navigate} from 'react-router-dom';
import {RouteComponentProps, withRouter} from '../../router-compat';
import qs from 'query-string';
import {parseSlackAuthState} from './support';

export const SlackIntegrationDetails = (props: RouteComponentProps<{}>) => {
  const {type: t, state, ...rest} = qs.parse(props.location.search);
  const key = t || state ? String(t || state) : '';
  const {type, inboxId} = parseSlackAuthState(key);

  if (inboxId && inboxId.length) {
    switch (type) {
      case 'reply':
        return (
          <Navigate
            to={`/inboxes/${inboxId}/integrations/slack/reply?${qs.stringify({
              state,
              ...rest,
            })}`}
            replace
          />
        );
      case 'support':
        return (
          <Navigate
            to={`/inboxes/${inboxId}/integrations/slack/support?${qs.stringify({
              state,
              ...rest,
            })}`}
            replace
          />
        );
      default:
        return <Navigate to={`/inboxes/${inboxId}/integrations`} replace />;
    }
  }

  switch (type) {
    case 'reply':
      return (
        <Navigate
          to={`/integrations/slack/reply?${qs.stringify({
            state,
            ...rest,
          })}`}
          replace
        />
      );
    case 'support':
      return (
        <Navigate
          to={`/integrations/slack/support?${qs.stringify({
            state,
            ...rest,
          })}`}
          replace
        />
      );
    default:
      return <Navigate to={`/integrations`} replace />;
  }
};

export default withRouter(SlackIntegrationDetails);
