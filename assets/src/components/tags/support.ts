import {colors} from '../common';

export const TAG_COLORS = [
  {name: 'default', hex: '#fafafa'},
  {name: 'magenta', hex: colors.magenta},
  {name: 'red', hex: colors.red},
  {name: 'volcano', hex: colors.volcano},
  {name: 'purple', hex: colors.purple},
  // NB: `colors.blue` is the full antd palette (an array); under theme-ui,
  // array values were treated as responsive and desktop viewports (>= 64em)
  // rendered `colors.blue[3]`, so we pin that value explicitly.
  {name: 'blue', hex: colors.blue[3]},
];

export const defaultTagColor = (index: number) => {
  const options = TAG_COLORS.slice(1).map((color) => color.name);

  return options[index % options.length];
};
