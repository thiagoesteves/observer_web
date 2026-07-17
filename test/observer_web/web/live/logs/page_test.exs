defmodule Observer.Web.Logs.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "GET /logs hints when no file-backed logger handlers exist", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/logs")

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "No file-backed logger handlers found"
    assert html =~ "logger_std_h"
  end

  test "GET /logs tails the first file handler by default", %{conn: conn} do
    path = stub_file_handler!("first line\nsecond line\nlast line\n")
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/logs")

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "File size:"
    assert html =~ "first line"
    assert html =~ "last line"
    refute html =~ "No file-backed logger handlers found"

    assert html =~ Phoenix.HTML.html_escape(path) |> Phoenix.HTML.safe_to_string()
  end

  test "REFRESH re-reads the tail", %{conn: conn} do
    path = stub_file_handler!("before refresh\n")
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/logs")

    :timer.sleep(50)

    File.write!(path, "after refresh\n")

    index_live
    |> element("#logs-refresh", "REFRESH")
    |> render_click()

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "after refresh"
    refute html =~ "before refresh"
  end

  test "form updates change the tail size and re-read", %{conn: conn} do
    content = Enum.map_join(1..2_000, "", &"log line number #{&1}\n")
    path = stub_file_handler!(content)
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/logs")

    :timer.sleep(50)

    index_live
    |> form("#logs-update-form", %{
      "service" => to_string(Node.self()),
      "file" => path,
      "max_bytes" => "16384"
    })
    |> render_change()

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Showing the last 16.0 KB"
    assert html =~ "log line number 2000"
    refute html =~ "log line number 1\n"
  end

  test "switching services while no file handlers exist does not crash", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/logs")

    :timer.sleep(50)

    assert render(index_live) =~ "No file-backed logger handlers found"

    # With no file handlers the file select renders empty, so a service change submits a
    # payload without any "file" key - this used to KeyError in handle_info(:logs_refresh, ...).
    index_live
    |> element("#logs-update-form")
    |> render_change(%{"service" => to_string(Node.self()), "max_bytes" => "65536"})

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "No file-backed logger handlers found"
    refute html =~ "File size:"
  end

  test "read failures are reported instead of crashing", %{conn: conn} do
    path = stub_file_handler!("data\n")
    TelemetryStubber.defaults()

    File.rm!(path)

    {:ok, index_live, _html} = live(conn, "/observer/logs")

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Could not read"
    assert html =~ "enoent"
  end

  defp stub_file_handler!(content) do
    dir = Path.join(System.tmp_dir!(), "observer_web_logs_page_test")
    File.mkdir_p!(dir)

    path = Path.join(dir, "#{System.unique_integer([:positive])}_page.log")
    File.write!(path, content)

    on_exit(fn -> File.rm(path) end)

    ObserverWeb.RpcMock
    |> stub(:call, fn
      _node, :logger, :get_handler_config, [], _timeout ->
        [%{id: :file_handler, module: :logger_std_h, config: %{file: to_charlist(path)}}]

      node, module, function, args, timeout ->
        :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    path
  end
end
