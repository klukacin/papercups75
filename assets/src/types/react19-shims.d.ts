// React 19 removed the global `JSX` namespace (it now lives at `React.JSX`).
// Some of our code and dependencies (e.g. react-markdown 8) still reference the
// bare `JSX.Element` / `JSX.IntrinsicElements` types, so re-expose the global
// namespace as an alias of `React.JSX` to keep type-checking green.
import type * as React from 'react';

declare global {
  namespace JSX {
    type Element = React.JSX.Element;
    type ElementType = React.JSX.ElementType;
    type ElementClass = React.JSX.ElementClass;
    type LibraryManagedAttributes<C, P> = React.JSX.LibraryManagedAttributes<
      C,
      P
    >;
    // eslint-disable-next-line @typescript-eslint/no-empty-interface
    interface ElementAttributesProperty
      extends React.JSX.ElementAttributesProperty {}
    // eslint-disable-next-line @typescript-eslint/no-empty-interface
    interface ElementChildrenAttribute
      extends React.JSX.ElementChildrenAttribute {}
    // eslint-disable-next-line @typescript-eslint/no-empty-interface
    interface IntrinsicAttributes extends React.JSX.IntrinsicAttributes {}
    // eslint-disable-next-line @typescript-eslint/no-empty-interface
    interface IntrinsicClassAttributes<T>
      extends React.JSX.IntrinsicClassAttributes<T> {}
    // eslint-disable-next-line @typescript-eslint/no-empty-interface
    interface IntrinsicElements extends React.JSX.IntrinsicElements {}
  }
}
