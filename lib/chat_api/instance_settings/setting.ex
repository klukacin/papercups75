defmodule ChatApi.InstanceSettings.Setting do
  @moduledoc """
  A single instance-setting override. The row's presence is what makes it an
  override: readers fall back to the env var (then to defaults) when no row
  exists for a key, so clearing a setting means deleting its row.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          key: String.t(),
          value: String.t() | nil,
          # Timestamps
          inserted_at: any(),
          updated_at: any()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "instance_settings" do
    field(:key, :string)
    field(:value, :string)

    timestamps()
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
