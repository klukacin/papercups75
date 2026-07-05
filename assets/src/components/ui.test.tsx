import React from 'react';
import {render, screen} from '@testing-library/react';

import {Box, Flex, Image, sxToStyle} from './ui';

describe('sxToStyle', () => {
  it('maps the bg shorthand to backgroundColor', () => {
    expect(sxToStyle({bg: 'red'})).toEqual({backgroundColor: 'red'});
  });

  it('maps margin/padding shorthands to their CSS longhands', () => {
    expect(sxToStyle({m: 1})).toEqual({margin: 4});
    expect(sxToStyle({mt: 1, mb: 2, ml: 3, mr: 4})).toEqual({
      marginTop: 4,
      marginBottom: 8,
      marginLeft: 16,
      marginRight: 32,
    });
    expect(sxToStyle({p: 1, pt: 1, pb: 2, pl: 3, pr: 4})).toEqual({
      padding: 4,
      paddingTop: 4,
      paddingBottom: 8,
      paddingLeft: 16,
      paddingRight: 32,
    });
  });

  it('expands mx/my and px/py to both axes', () => {
    expect(sxToStyle({mx: 2})).toEqual({marginLeft: 8, marginRight: 8});
    expect(sxToStyle({my: 3})).toEqual({marginTop: 16, marginBottom: 16});
    expect(sxToStyle({px: 4})).toEqual({paddingLeft: 32, paddingRight: 32});
    expect(sxToStyle({py: 5})).toEqual({paddingTop: 64, paddingBottom: 64});
  });

  it('maps integers through the theme-ui default space scale', () => {
    // [0, 4, 8, 16, 32, 64, 128, 256, 512]
    expect(sxToStyle({mb: 0})).toEqual({marginBottom: 0});
    expect(sxToStyle({mb: 8})).toEqual({marginBottom: 512});
  });

  it('maps negative integers to negative scale values', () => {
    expect(sxToStyle({mx: -1})).toEqual({marginLeft: -4, marginRight: -4});
    expect(sxToStyle({mb: -3})).toEqual({marginBottom: -16});
  });

  it('passes numbers outside the scale range through raw', () => {
    expect(sxToStyle({mb: 12})).toEqual({marginBottom: 12});
    expect(sxToStyle({mr: 360})).toEqual({marginRight: 360});
    expect(sxToStyle({mt: -16})).toEqual({marginTop: -16});
  });

  it('passes non-integer numbers through raw', () => {
    expect(sxToStyle({mt: 2.5})).toEqual({marginTop: 2.5});
  });

  it('scales positional and gap keys through the space scale', () => {
    expect(sxToStyle({top: 0, bottom: 20})).toEqual({top: 0, bottom: 20});
    expect(sxToStyle({gap: 2})).toEqual({gap: 8});
    expect(sxToStyle({left: 3})).toEqual({left: 16});
  });

  it('does NOT scale-map non-space numeric keys', () => {
    expect(
      sxToStyle({
        flex: 1,
        opacity: 0.8,
        zIndex: 2,
        fontWeight: 4,
        lineHeight: 1.4,
        fontSize: 12,
        height: 320,
        borderRadius: 4,
      })
    ).toEqual({
      flex: 1,
      opacity: 0.8,
      zIndex: 2,
      fontWeight: 4,
      lineHeight: 1.4,
      fontSize: 12,
      height: 320,
      borderRadius: 4,
    });
  });

  it('passes strings through untouched', () => {
    expect(
      sxToStyle({
        width: '100%',
        maxWidth: 'calc(100% - 20px)',
        mb: '1em',
        px: '12px',
      })
    ).toEqual({
      width: '100%',
      maxWidth: 'calc(100% - 20px)',
      marginBottom: '1em',
      paddingLeft: '12px',
      paddingRight: '12px',
    });
  });

  it('ignores undefined/null values and handles missing sx', () => {
    expect(sxToStyle()).toEqual({});
    expect(sxToStyle({mb: undefined as any, color: null as any})).toEqual({});
  });
});

describe('Box', () => {
  it('renders a div with its children', () => {
    render(<Box data-testid="box">hello</Box>);
    const el = screen.getByTestId('box');
    expect(el.tagName).toBe('DIV');
    expect(el).toHaveTextContent('hello');
  });

  it('passes className and other DOM props through', () => {
    const onClick = vi.fn();
    render(
      <Box data-testid="box" className="my-class" onClick={onClick}>
        x
      </Box>
    );
    const el = screen.getByTestId('box');
    expect(el).toHaveClass('my-class');
    el.click();
    expect(onClick).toHaveBeenCalled();
  });

  it('translates direct spacing props into inline styles', () => {
    render(<Box data-testid="box" mb={3} mx={-1} p={4} />);
    const el = screen.getByTestId('box');
    expect(el.style.marginBottom).toBe('16px');
    expect(el.style.marginLeft).toBe('-4px');
    expect(el.style.marginRight).toBe('-4px');
    expect(el.style.padding).toBe('32px');
  });

  it('translates a direct backgroundColor prop into an inline style', () => {
    render(<Box data-testid="box" backgroundColor="#fff" />);
    const el = screen.getByTestId('box');
    expect(el.style.backgroundColor).toBe('rgb(255, 255, 255)');
    expect(el).not.toHaveAttribute('backgroundColor');
  });

  it('translates sx into inline styles', () => {
    render(<Box data-testid="box" sx={{bg: 'blue', width: '100%', mb: 2}} />);
    const el = screen.getByTestId('box');
    expect(el.style.backgroundColor).toBe('blue');
    expect(el.style.width).toBe('100%');
    expect(el.style.marginBottom).toBe('8px');
  });

  it('lets sx override direct props', () => {
    render(<Box data-testid="box" mb={2} sx={{mb: 3}} />);
    expect(screen.getByTestId('box').style.marginBottom).toBe('16px');
  });

  it('lets a user-passed style prop win over sx and direct props', () => {
    render(
      <Box data-testid="box" mb={2} sx={{mb: 3}} style={{marginBottom: 99}} />
    );
    expect(screen.getByTestId('box').style.marginBottom).toBe('99px');
  });

  it('forwards refs to the underlying div', () => {
    const ref = React.createRef<HTMLDivElement>();
    render(<Box ref={ref} data-testid="box" />);
    expect(ref.current).toBe(screen.getByTestId('box'));
  });
});

describe('Flex', () => {
  it('renders with display: flex', () => {
    render(<Flex data-testid="flex" />);
    expect(screen.getByTestId('flex').style.display).toBe('flex');
  });

  it('merges sx and spacing props on top of display: flex', () => {
    render(<Flex data-testid="flex" mx={-3} sx={{flexDirection: 'column'}} />);
    const el = screen.getByTestId('flex');
    expect(el.style.display).toBe('flex');
    expect(el.style.flexDirection).toBe('column');
    expect(el.style.marginLeft).toBe('-16px');
    expect(el.style.marginRight).toBe('-16px');
  });

  it('forwards refs', () => {
    const ref = React.createRef<HTMLDivElement>();
    render(<Flex ref={ref} data-testid="flex" />);
    expect(ref.current).toBe(screen.getByTestId('flex'));
  });
});

describe('Image', () => {
  it('renders an img with src/alt and translated props', () => {
    render(<Image src="/foo.png" alt="foo" mb={2} sx={{width: '100%'}} />);
    const el = screen.getByAltText('foo') as HTMLImageElement;
    expect(el.tagName).toBe('IMG');
    expect(el.src).toContain('/foo.png');
    expect(el.style.marginBottom).toBe('8px');
    expect(el.style.width).toBe('100%');
  });
});
