defmodule ChatApiWeb.PageControllerTest do
  use ChatApiWeb.ConnCase, async: true

  alias ChatApi.InstanceSettings

  # window.__ENV__ is injected as compact JSON, so an override must show up as
  # an exact `"KEY":"value"` pair in the rendered HTML.

  test "GET / renders the app shell with window.__ENV__ injected", %{conn: conn} do
    body = conn |> get("/") |> html_response(200)

    assert body =~ "window.__ENV__"
    refute body =~ "__SERVER_ENV_DATA__"
  end

  test "GET / reflects a DB override in window.__ENV__", %{conn: conn} do
    {:ok, _} = InstanceSettings.set("REACT_APP_GITHUB_APP_NAME", "papercups-fork-test")

    body = conn |> get("/") |> html_response(200)

    assert body =~ ~s("REACT_APP_GITHUB_APP_NAME":"papercups-fork-test")
  end

  test "GET / maps the USER_INVITATION_EMAIL_ENABLED override into the REACT_APP_ key",
       %{conn: conn} do
    {:ok, _} = InstanceSettings.set("USER_INVITATION_EMAIL_ENABLED", true)

    body = conn |> get("/") |> html_response(200)

    assert body =~ ~s("REACT_APP_USER_INVITATION_EMAIL_ENABLED":"true")
  end

  test "GET / keeps the hardcoded default when neither DB nor env provides a value",
       %{conn: conn} do
    original = System.get_env("REACT_APP_GITHUB_APP_NAME")
    System.delete_env("REACT_APP_GITHUB_APP_NAME")

    on_exit(fn ->
      if original, do: System.put_env("REACT_APP_GITHUB_APP_NAME", original)
    end)

    body = conn |> get("/") |> html_response(200)

    assert body =~ ~s("REACT_APP_GITHUB_APP_NAME":"papercups-io")
  end

  test "catch-all routes render the same app shell with overrides", %{conn: conn} do
    {:ok, _} = InstanceSettings.set("REACT_APP_GITHUB_APP_NAME", "papercups-fork-test")

    body = conn |> get("/conversations/all") |> html_response(200)

    assert body =~ ~s("REACT_APP_GITHUB_APP_NAME":"papercups-fork-test")
  end
end
