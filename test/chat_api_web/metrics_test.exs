defmodule ChatApiWeb.MetricsTest do
  use ChatApiWeb.ConnCase, async: true

  test "GET /metrics exposes Prometheus-formatted metrics", %{conn: conn} do
    conn = get(conn, "/metrics")

    assert response = response(conn, 200)
    # PromEx/Prometheus exposition format uses HELP/TYPE comment lines.
    assert response =~ "# TYPE" or response =~ "# HELP"
  end
end
