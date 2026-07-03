// React 18 removed implicit `children` from component prop types. A few of our
// older third-party libraries declare class/function components whose prop
// interfaces never listed `children` explicitly, so usages with children fail
// to type-check under @types/react@18. Re-add `children` to those interfaces.
import 'react';

declare module 'react-helmet' {
  interface HelmetProps {
    children?: React.ReactNode;
  }
}

declare module 'react-router-dom' {
  interface BrowserRouterProps {
    children?: React.ReactNode;
  }
}

declare module 'react-router' {
  interface SwitchProps {
    children?: React.ReactNode;
  }

  interface MemoryRouterProps {
    children?: React.ReactNode;
  }
}
