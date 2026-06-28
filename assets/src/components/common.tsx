import React, {FunctionComponent} from 'react';
import {
  Alert,
  AutoComplete,
  Badge,
  Button,
  Checkbox,
  Divider,
  Drawer,
  Dropdown,
  Empty,
  Input,
  InputNumber,
  Layout,
  List,
  Mentions,
  Menu,
  Modal,
  notification,
  Popconfirm,
  Popover,
  Radio,
  Result,
  Select,
  Spin,
  Statistic,
  Switch,
  Table,
  Tabs,
  Tag,
  Tooltip,
  Typography,
  Upload,
} from 'antd';

import {Prism as SyntaxHighlighter} from 'react-syntax-highlighter';
import {prism as syntaxHighlightingLanguage} from 'react-syntax-highlighter/dist/esm/styles/prism';

import {
  blue,
  green,
  red,
  volcano,
  orange,
  gold,
  purple,
  magenta,
  grey,
} from '@ant-design/colors';

import {Box, BoxProps, Flex, ThemeUICSSObject} from 'theme-ui';
import DatePicker from './DatePicker';
import MarkdownRenderer from './MarkdownRenderer';

export type {UploadChangeParam, UploadFile} from 'antd/es/upload/interface';

const {Title, Text, Paragraph} = Typography;
const {Header, Content, Footer, Sider} = Layout;
const {RangePicker} = DatePicker;

export const colors = {
  white: '#fff',
  black: '#000',
  primary: blue[5],
  green: green[5],
  red: red[5],
  gold: gold[5],
  volcano: volcano[5],
  orange: orange[5],
  purple: purple[5],
  magenta: magenta[5],
  blue: blue, // expose all blues
  gray: grey, // expose all grays
  text: 'rgba(0, 0, 0, 0.65)',
  secondary: 'rgba(0, 0, 0, 0.55)', // WCAG AA: ~4.7:1 on white
  note: '#fff1b8',
  noteSecondary: 'rgba(254,237,175,.4)',
};

export const shadows = {
  primary:
    '0 0 #0000, 0 0 #0000, 0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px 0 rgba(0, 0, 0, 0.06)',
  small: '0 0 #0000, 0 0 #0000, 0 1px 2px 0 rgba(0, 0, 0, 0.05)',
  medium:
    '0 0 #0000, 0 0 #0000, 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
  large:
    '0 0 #0000, 0 0 #0000, 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
};

export const StandardSyntaxHighlighter: FunctionComponent<{
  language: string;
  style?: any;
  children: string | string[];
}> = ({language, children, style = {}}) => {
  return (
    <SyntaxHighlighter
      language={language}
      style={syntaxHighlightingLanguage}
      customStyle={style}
    >
      {children}
    </SyntaxHighlighter>
  );
};

export const Card = ({
  children,
  shadow = false,
  sx = {},
  ...props
}: {
  children: any;
  shadow?: boolean | 'small' | 'medium' | 'large';
  sx?: ThemeUICSSObject;
} & BoxProps) => {
  const shadowKey = shadow && typeof shadow === 'boolean' ? 'primary' : shadow;
  const boxShadow = shadowKey ? shadows[shadowKey] || shadows.primary : 'none';

  return (
    <Box
      sx={{
        bg: colors.white,
        border: '1px solid rgba(0, 0, 0, .06)',
        borderRadius: 4,
        boxShadow,
        ...sx,
      }}
      {...props}
    >
      {children}
    </Box>
  );
};

export const Container = ({
  children,
  sx = {},
}: {
  children: any;
  sx?: ThemeUICSSObject;
}) => {
  return (
    <Flex
      sx={{
        width: '100%',
        justifyContent: 'center',
        alignItems: 'center',
        flexDirection: 'column',
      }}
    >
      <Box p={4} sx={{flex: 1, width: '100%', maxWidth: 1080, ...sx}}>
        {children}
      </Box>
    </Flex>
  );
};

export const TextArea = Input.TextArea;

/**
 * Whitelist node types that we allow when we render markdown.
 * Reference https://github.com/rexxars/react-markdown#node-types
 */
export const allowedMarkdownElements: Array<string> = [
  'br',
  'p',
  'em',
  'strong',
  'blockquote',
  'del',
  'a',
  'ul',
  'ol',
  'li',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'code',
  'pre',
  'img',
];

export const allowedNodeTypes: Array<any> = [
  'root',
  'text',
  'break',
  'paragraph',
  'emphasis',
  'strong',
  'blockquote',
  'delete',
  'link',
  'linkReference',
  'list',
  'listItem',
  'heading',
  'inlineCode',
  'code',
  'image',
];

export {
  // Typography
  Title,
  Text,
  Paragraph,
  // Layout
  Content,
  Footer,
  Layout,
  Header,
  Sider,
  // Components
  Alert,
  AutoComplete,
  Badge,
  Button,
  Checkbox,
  DatePicker,
  Divider,
  Drawer,
  Dropdown,
  Empty,
  Input,
  InputNumber,
  List,
  MarkdownRenderer,
  Mentions,
  Menu,
  Modal,
  notification,
  Popconfirm,
  Popover,
  Radio,
  RangePicker,
  Result,
  Select,
  Switch,
  Spin,
  Statistic,
  Table,
  Tabs,
  Tag,
  Tooltip,
  Upload,
};
