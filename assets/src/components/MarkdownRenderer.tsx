import React from 'react';
import ReactMarkdown from 'react-markdown';
import breaks from 'remark-breaks';
import {allowedMarkdownElements} from './common';

const components = {
  img: ({node, ...props}: any) => (
    <img
      alt={props.alt || ''}
      {...props}
      style={{maxWidth: '100%', maxHeight: 400}}
    />
  ),
};

type Props = {
  className?: string;
  source: string;
};

const MarkdownRenderer = ({className, source}: Props) => {
  return (
    <ReactMarkdown
      className={`Text--markdown ${className}`}
      allowedElements={allowedMarkdownElements}
      unwrapDisallowed
      components={components}
      remarkPlugins={[breaks]}
    >
      {source}
    </ReactMarkdown>
  );
};

export default MarkdownRenderer;
