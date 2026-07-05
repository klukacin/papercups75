/**
 * Zero-dependency replacement for the `theme-ui` Box/Flex/Image primitives.
 *
 * The app never mounted a theme-ui ThemeProvider, so every component ran on
 * theme-ui's built-in default scales. This shim reproduces exactly that
 * behavior by translating the `sx` prop and direct spacing props into plain
 * inline styles:
 *
 * - Space scale (margins/paddings/gap/top/right/bottom/left): integer values
 *   with |n| < 9 map through theme-ui's default space scale
 *   [0, 4, 8, 16, 32, 64, 128, 256, 512] (negative n yields the negative
 *   scale value); anything else passes through raw, matching theme-ui's
 *   fallback for out-of-range scale indices.
 * - Numeric fontSize is passed through raw. theme-ui's default fontSizes
 *   scale [12, 14, 16, 20, 24, 32, 48, 64, 72] only applies to indices 0-8,
 *   and the codebase only ever uses numeric fontSize values >= 12, which
 *   theme-ui already passed through raw. (Verified by grep before removal.)
 * - All other keys (flex, opacity, zIndex, width, ...) pass through
 *   untouched; React's style prop handles px-vs-unitless the same way
 *   theme-ui did.
 * - Responsive array values are NOT supported (inline styles cannot express
 *   media queries); the few call sites that used them were rewritten with
 *   CSS classes + media queries (see App.css).
 *
 * Merge order matches theme-ui: direct props first, then `sx` overrides,
 * then a user-passed `style` prop wins last.
 */
import React from 'react';

const SPACE_SCALE = [0, 4, 8, 16, 32, 64, 128, 256, 512];

type SxValue = string | number | undefined | null;

export type SxObject = {[key: string]: SxValue};

// Alias kept so existing `import {ThemeUICSSObject} from '../ui'` sites and
// type annotations continue to compile unchanged.
export type ThemeUICSSObject = SxObject;

type SpaceValue = number | string;

interface SpaceProps {
  // theme-ui's Box also accepted styled-system color props directly;
  // `backgroundColor` is the only one the codebase uses.
  backgroundColor?: string;
  m?: SpaceValue;
  mt?: SpaceValue;
  mr?: SpaceValue;
  mb?: SpaceValue;
  ml?: SpaceValue;
  mx?: SpaceValue;
  my?: SpaceValue;
  p?: SpaceValue;
  pt?: SpaceValue;
  pr?: SpaceValue;
  pb?: SpaceValue;
  pl?: SpaceValue;
  px?: SpaceValue;
  py?: SpaceValue;
}

// Shorthand -> CSS longhand(s). Used both for direct props and inside `sx`.
const SHORTHANDS: {[key: string]: Array<string>} = {
  m: ['margin'],
  mt: ['marginTop'],
  mr: ['marginRight'],
  mb: ['marginBottom'],
  ml: ['marginLeft'],
  mx: ['marginLeft', 'marginRight'],
  my: ['marginTop', 'marginBottom'],
  p: ['padding'],
  pt: ['paddingTop'],
  pr: ['paddingRight'],
  pb: ['paddingBottom'],
  pl: ['paddingLeft'],
  px: ['paddingLeft', 'paddingRight'],
  py: ['paddingTop', 'paddingBottom'],
  bg: ['backgroundColor'],
};

// Direct props (on Box/Flex/Image) that get translated into inline styles.
const DIRECT_STYLE_PROP_KEYS = Object.keys(SHORTHANDS)
  .filter((key) => key !== 'bg')
  .concat(['backgroundColor']);

// CSS keys whose numeric values go through the space scale (matching the
// `scales` map in @theme-ui/css).
const SPACE_SCALE_KEYS = new Set([
  'margin',
  'marginTop',
  'marginRight',
  'marginBottom',
  'marginLeft',
  'padding',
  'paddingTop',
  'paddingRight',
  'paddingBottom',
  'paddingLeft',
  'gap',
  'gridGap',
  'gridRowGap',
  'gridColumnGap',
  'rowGap',
  'columnGap',
  'top',
  'right',
  'bottom',
  'left',
  'inset',
]);

const scaleSpace = (value: SxValue): SxValue => {
  if (
    typeof value === 'number' &&
    Number.isInteger(value) &&
    Math.abs(value) < SPACE_SCALE.length
  ) {
    return value < 0 ? -SPACE_SCALE[-value] : SPACE_SCALE[value];
  }

  return value;
};

export const sxToStyle = (sx: SxObject = {}): React.CSSProperties => {
  const style: {[key: string]: string | number} = {};

  for (const key of Object.keys(sx)) {
    const value = sx[key];

    if (value === undefined || value === null) {
      continue;
    }

    const cssKeys = SHORTHANDS[key] || [key];

    for (const cssKey of cssKeys) {
      style[cssKey] = SPACE_SCALE_KEYS.has(cssKey)
        ? (scaleSpace(value) as string | number)
        : value;
    }
  }

  return style as React.CSSProperties;
};

// Computes the final inline style: direct spacing props first, then `sx`
// overrides, then a user-passed `style` prop last. Returns the remaining
// (DOM-safe) props with the spacing props stripped out.
const useTranslatedProps = <
  T extends SpaceProps & {sx?: SxObject; style?: React.CSSProperties}
>(
  props: T
) => {
  const {sx, style, ...rest} = props;
  const direct: SxObject = {};

  for (const key of DIRECT_STYLE_PROP_KEYS) {
    if (key in rest) {
      direct[key] = (rest as {[key: string]: SxValue})[key];
      delete (rest as {[key: string]: SxValue})[key];
    }
  }

  return {
    rest,
    style: {...sxToStyle(direct), ...sxToStyle(sx), ...style},
  };
};

export interface BoxProps
  extends React.HTMLAttributes<HTMLDivElement>,
    SpaceProps {
  sx?: SxObject;
}

export const Box = React.forwardRef<HTMLDivElement, BoxProps>(function Box(
  props,
  ref
) {
  const {rest, style} = useTranslatedProps(props);

  return <div ref={ref} {...rest} style={style} />;
});

export const Flex = React.forwardRef<HTMLDivElement, BoxProps>(function Flex(
  {sx, ...props},
  ref
) {
  return <Box ref={ref} sx={{display: 'flex', ...sx}} {...props} />;
});

export interface ImageProps
  extends React.ImgHTMLAttributes<HTMLImageElement>,
    SpaceProps {
  sx?: SxObject;
}

export const Image = React.forwardRef<HTMLImageElement, ImageProps>(
  function Image(props, ref) {
    const {rest, style} = useTranslatedProps(props);

    // eslint-disable-next-line jsx-a11y/alt-text
    return <img ref={ref} {...rest} style={style} />;
  }
);
