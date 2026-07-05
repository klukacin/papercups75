import React from 'react';
import {Navigate} from 'react-router-dom';
import {RouteComponentProps, withRouter} from '../../router-compat';
import qs from 'query-string';

export const GoogleIntegrationDetails = (props: RouteComponentProps<{}>) => {
  const {type, state, scope, ...rest} = qs.parse(props.location.search);

  switch (scope) {
    case 'https://www.googleapis.com/auth/gmail.modify':
      return (
        <Navigate
          to={`/integrations/google/gmail?${qs.stringify({
            state,
            scope,
            type,
            ...rest,
          })}`}
          replace
        />
      );
    case 'https://www.googleapis.com/auth/spreadsheets':
      return (
        <Navigate
          to={`/integrations/google/sheets?${qs.stringify({
            state,
            scope,
            type,
            ...rest,
          })}`}
          replace
        />
      );
    default:
      return <Navigate to={`/integrations`} replace />;
  }
};

export default withRouter(GoogleIntegrationDetails);
