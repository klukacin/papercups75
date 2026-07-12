import React from 'react';
import {Box, Flex} from '../ui';
import {
  colors,
  message,
  Button,
  Divider,
  Input,
  Paragraph,
  Switch,
  Table,
  Tag,
  Text,
  Title,
} from '../common';
import Spinner from '../Spinner';
import * as API from '../../api';
import {Alignment} from '../../types';
import logger from '../../logger';

// e.g. "REGISTRATION_DISABLED" -> "Registration disabled"
export const humanizeSettingKey = (key: string): string => {
  const [first = '', ...rest] = key.toLowerCase().split('_').filter(Boolean);

  if (!first) {
    return key;
  }

  return [first.charAt(0).toUpperCase() + first.slice(1), ...rest].join(' ');
};

// Boolean settings are serialized as strings on the wire ("true"/"false").
const parseBooleanSetting = (value: string | null): boolean =>
  value === 'true' || value === '1';

const SettingSourceTag = ({source}: {source: API.InstanceSettingSource}) => {
  switch (source) {
    case 'override':
      return <Tag color={colors.primary}>DB override</Tag>;
    case 'env':
      return <Tag>from env</Tag>;
    default:
      return <Tag color={colors.gray[2]}>unset</Tag>;
  }
};

// Instance-wide runtime configuration for superadmins: editable settings are
// stored as database overrides (falling back to the server environment when no
// override exists), while env-only settings can merely be inspected here.
const InstanceSettingsSection = () => {
  const [settings, setSettings] = React.useState<API.InstanceSettings | null>(
    null
  );
  const [isLoading, setLoading] = React.useState(true);
  const [isSaving, setSaving] = React.useState(false);
  const [resettingKey, setResettingKey] = React.useState<string | null>(null);
  // Local, unsaved edits keyed by setting key. Only keys whose edited value
  // actually differs from the server value are sent on Save.
  const [edits, setEdits] = React.useState<Record<string, string | boolean>>(
    {}
  );

  React.useEffect(() => {
    let mounted = true;

    API.fetchInstanceSettings()
      .then((result) => {
        if (mounted) {
          setSettings(result);
        }
      })
      .catch((err) => {
        logger.error('Failed to load instance settings:', err);
      })
      .then(() => {
        if (mounted) {
          setLoading(false);
        }
      });

    return () => {
      mounted = false;
    };
  }, []);

  const getServerValue = (
    setting: API.EditableInstanceSetting
  ): string | boolean =>
    setting.type === 'boolean'
      ? parseBooleanSetting(setting.value)
      : setting.value ?? '';

  const getDisplayedValue = (
    setting: API.EditableInstanceSetting
  ): string | boolean =>
    setting.key in edits ? edits[setting.key] : getServerValue(setting);

  const getChangedSettings = (): Record<string, string | boolean | null> => {
    return (settings?.editable ?? []).reduce((acc, setting) => {
      if (
        setting.key in edits &&
        edits[setting.key] !== getServerValue(setting)
      ) {
        acc[setting.key] = edits[setting.key];
      }

      return acc;
    }, {} as Record<string, string | boolean | null>);
  };

  const handleEdit = (key: string, value: string | boolean) => {
    setEdits((prev) => ({...prev, [key]: value}));
  };

  const handleSave = async () => {
    const changes = getChangedSettings();

    if (Object.keys(changes).length === 0) {
      return;
    }

    setSaving(true);

    try {
      const updated = await API.updateInstanceSettings(changes);

      setSettings(updated);
      setEdits({});
      message.success('Instance settings updated');
    } catch (err) {
      const description =
        err?.response?.body?.error?.message || err?.message || String(err);

      message.error(description);
    } finally {
      setSaving(false);
    }
  };

  // Sending `null` clears the database override so the setting falls back to
  // the server environment value.
  const handleResetToEnv = async (key: string) => {
    setResettingKey(key);

    try {
      const updated = await API.updateInstanceSettings({[key]: null});

      setSettings(updated);
      setEdits((prev) => {
        const {[key]: _discarded, ...rest} = prev;

        return rest;
      });
      message.success(`Cleared override for ${key}`);
    } catch (err) {
      const description =
        err?.response?.body?.error?.message || err?.message || String(err);

      message.error(description);
    } finally {
      setResettingKey(null);
    }
  };

  if (isLoading) {
    return (
      <Flex
        sx={{
          flex: 1,
          justifyContent: 'center',
          alignItems: 'center',
          height: '100%',
        }}
        py={5}
      >
        <Spinner size={40} />
      </Flex>
    );
  }

  if (!settings) {
    return (
      <Paragraph>
        <Text type="danger">
          Failed to load instance settings. Please try again later.
        </Text>
      </Paragraph>
    );
  }

  const hasChanges = Object.keys(getChangedSettings()).length > 0;

  const editableColumns = [
    {
      title: 'Setting',
      dataIndex: 'key',
      key: 'setting',
      render: (key: string) => {
        return (
          <Box>
            <Box>
              <Text strong>{humanizeSettingKey(key)}</Text>
            </Box>
            <Text code>{key}</Text>
          </Box>
        );
      },
    },
    {
      title: 'Value',
      dataIndex: 'value',
      key: 'value',
      render: (value: string | null, record: API.EditableInstanceSetting) => {
        const displayed = getDisplayedValue(record);

        if (record.type === 'boolean') {
          return (
            <Switch
              aria-label={`Toggle ${record.key}`}
              checked={displayed === true}
              onChange={(checked) => handleEdit(record.key, checked)}
            />
          );
        }

        return (
          <Input
            aria-label={`Value for ${record.key}`}
            value={typeof displayed === 'string' ? displayed : ''}
            placeholder="Not set"
            onChange={(e) => handleEdit(record.key, e.target.value)}
          />
        );
      },
    },
    {
      title: 'Source',
      dataIndex: 'source',
      key: 'source',
      render: (source: API.InstanceSettingSource) => {
        return <SettingSourceTag source={source} />;
      },
    },
    {
      title: '',
      dataIndex: 'reset',
      key: 'reset',
      align: Alignment.Right,
      render: (value: undefined, record: API.EditableInstanceSetting) => {
        return (
          <Button
            aria-label={`Reset ${record.key} to env`}
            disabled={record.source !== 'override' || isSaving}
            loading={resettingKey === record.key}
            onClick={() => handleResetToEnv(record.key)}
          >
            Reset to env
          </Button>
        );
      },
    },
  ];

  const envOnlyColumns = [
    {
      title: 'Key',
      dataIndex: 'key',
      key: 'key',
      render: (key: string) => {
        return <Text code>{key}</Text>;
      },
    },
    {
      title: 'Status',
      dataIndex: 'is_set',
      key: 'is_set',
      render: (isSet: boolean) => {
        return isSet ? (
          <Tag color={colors.green}>set</Tag>
        ) : (
          <Tag color={colors.gray[2]}>not set</Tag>
        );
      },
    },
    {
      title: 'Preview',
      dataIndex: 'preview',
      key: 'preview',
      render: (preview: string | null) => {
        return preview ? <Text code>{preview}</Text> : '--';
      },
    },
  ];

  return (
    <Box>
      <Box mb={4}>
        <Title level={4}>Editable settings</Title>

        <Paragraph>
          <Text>
            These settings are stored in the database and take effect without a
            restart. Settings without a database override fall back to the
            server environment.
          </Text>
        </Paragraph>

        <Table
          dataSource={settings.editable.map((setting) => {
            return {...setting, key: setting.key};
          })}
          columns={editableColumns}
          pagination={false}
        />

        <Flex mt={3} sx={{justifyContent: 'flex-end'}}>
          <Button
            type="primary"
            loading={isSaving}
            disabled={!hasChanges || resettingKey !== null}
            onClick={handleSave}
          >
            Save
          </Button>
        </Flex>
      </Box>

      <Divider />

      <Box mb={4}>
        <Title level={4}>Environment-only settings</Title>

        <Paragraph>
          <Text>
            These settings are read-only here. Changing them requires updating
            the environment variables on the server and restarting it.
          </Text>
        </Paragraph>

        <Table
          dataSource={settings.env_only.map((setting) => {
            return {...setting, key: setting.key};
          })}
          columns={envOnlyColumns}
          pagination={false}
        />
      </Box>
    </Box>
  );
};

export default InstanceSettingsSection;
