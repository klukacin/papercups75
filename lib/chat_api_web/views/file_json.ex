defmodule ChatApiWeb.FileJSON do
  import ChatApiWeb.JSONHelpers

  def show(%{file: file}) do
    %{data: maybe(file, &file/1)}
  end

  def file(file) do
    %{
      id: file.id,
      object: "file",
      file_url: file.file_url,
      content_type: file.content_type,
      filename: file.filename
    }
  end
end
