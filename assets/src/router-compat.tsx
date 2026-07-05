import React from 'react';
import {
  Location,
  NavigateOptions,
  To,
  useLocation,
  useNavigate,
  useParams,
} from 'react-router-dom';

/**
 * Compatibility layer for the react-router v5 -> v6 migration.
 *
 * Most of the components in this codebase are class components that were
 * written against the v5 `RouteComponentProps` API (`history`, `location`,
 * and `match` injected as props by `<Route component={...} />`). React Router
 * v6 removed both `RouteComponentProps` and the prop injection, so this
 * module provides:
 *
 *  - a v5-shaped `History` object (backed by `useNavigate`)
 *  - a v5-shaped `Match` object (backed by `useParams`/`useLocation`)
 *  - a `RouteComponentProps` type alias matching the v5 shape
 *  - a `withRouter` HOC that injects the above into class/function components
 */

export interface History {
  push: (to: To, state?: any) => void;
  replace: (to: To, state?: any) => void;
  go: (delta: number) => void;
  goBack: () => void;
  goForward: () => void;
  location: Location;
}

export interface Match<Params extends {[K in keyof Params]?: string} = {}> {
  params: Params;
  path: string;
  url: string;
  isExact: boolean;
}

export interface RouteComponentProps<
  Params extends {[K in keyof Params]?: string} = {}
> {
  history: History;
  location: Location;
  match: Match<Params>;
}

export const useCompatHistory = (): History => {
  const navigate = useNavigate();
  const location = useLocation();

  return React.useMemo(
    () => ({
      push: (to: To, state?: any) => {
        const options: NavigateOptions = state !== undefined ? {state} : {};

        navigate(to, options);
      },
      replace: (to: To, state?: any) => {
        const options: NavigateOptions =
          state !== undefined ? {replace: true, state} : {replace: true};

        navigate(to, options);
      },
      go: (delta: number) => navigate(delta),
      goBack: () => navigate(-1),
      goForward: () => navigate(1),
      location,
    }),
    [navigate, location]
  );
};

export function withRouter<P extends RouteComponentProps<any>>(
  Component: React.ComponentType<P>
): React.ComponentType<Omit<P, keyof RouteComponentProps<any>>> {
  const Wrapper = (props: Omit<P, keyof RouteComponentProps<any>>) => {
    const location = useLocation();
    const params = useParams();
    const history = useCompatHistory();

    const match = React.useMemo(
      () => ({
        params,
        // NB: v5 `match.path`/`match.url` have no exact v6 equivalent; nothing
        // in this codebase reads them, so we approximate with the pathname.
        path: location.pathname,
        url: location.pathname,
        isExact: true,
      }),
      [params, location.pathname]
    );

    return (
      <Component
        {...(props as P)}
        history={history}
        location={location}
        match={match}
      />
    );
  };

  Wrapper.displayName = `withRouter(${
    Component.displayName || Component.name || 'Component'
  })`;

  return Wrapper;
}
