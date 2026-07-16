defmodule Observer.Web.IndexLive do
  @moduledoc """
  This module provides Observer context

  ## References:
   * https://github.com/oban-bg/oban_web/blob/main/lib/oban/web/dashboard_live.ex
  """

  use Observer.Web, :live_view

  alias Observer.Web.Apps.Page, as: AppsPage
  alias Observer.Web.Crashdump.Page, as: CrashdumpPage
  alias Observer.Web.Ets.Page, as: EtsPage
  alias Observer.Web.Logs.Page, as: LogsPage
  alias Observer.Web.Metrics.Page, as: MetricsPage
  alias Observer.Web.Network.Page, as: NetworkPage
  alias Observer.Web.Processes.Page, as: ProcessesPage
  alias Observer.Web.Profiling.Page, as: ProfilingPage
  alias Observer.Web.System.Page, as: SystemPage
  alias Observer.Web.Tracing.Page, as: TracingPage
  alias ObserverWeb.Version

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    %{"prefix" => prefix, "resolver" => resolver} = session
    %{"live_path" => live_path, "live_transport" => live_transport} = session
    %{"user" => user, "access" => access, "csp_nonces" => csp_nonces} = session
    %{"logo_path" => logo_path} = session

    custom_pages = Map.get(session, "pages") || []

    page = resolve_page(params, custom_pages)
    theme = restore_state(socket, "theme", "system")
    version = Version.status()

    Process.put(:routing, {socket, prefix})

    socket =
      socket
      |> assign(params: params, page: page, custom_pages: custom_pages)
      |> assign(live_path: live_path, live_transport: live_transport, logo_path: logo_path)
      |> assign(access: access, csp_nonces: csp_nonces, resolver: resolver, user: user)
      |> assign(theme: theme, version: version)
      |> page.comp.handle_mount()

    {:ok, socket}
  end

  defp init_state(socket) do
    case get_connect_params(socket) do
      %{"init_state" => state} -> state
      _ -> %{}
    end
  end

  defp restore_state(socket, key, default) do
    socket
    |> init_state()
    |> Map.get("observer:" <> key, default)
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    assigns =
      assigns
      |> Map.put(:id, "page")
      |> Map.drop(~w(csp_nonces flash live_path live_transport socket)a)

    ~H"""
    <.live_component id="page" module={@page.comp} {assigns} />
    """
  end

  @impl Phoenix.LiveView
  def handle_params(params, uri, socket) do
    socket.assigns.page.comp.handle_params(params, uri, socket)
  end

  @impl Phoenix.LiveView
  def handle_info({:update_theme, theme}, socket) do
    {:noreply,
     socket
     |> assign(theme: theme)
     |> push_event("update-theme", %{theme: theme})}
  end

  def handle_info(message, socket) do
    socket.assigns.page.comp.handle_info(message, socket)
  end

  @impl Phoenix.LiveView
  def handle_event("clear-flash", %{}, socket) do
    {:noreply, clear_flash(socket)}
  end

  def handle_event(message, value, socket) do
    socket.assigns.page.comp.handle_parent_event(message, value, socket)
  end

  ## Render Helpers

  defp resolve_page(%{"page" => "applications"}, _pages),
    do: %{name: :applications, comp: AppsPage}

  defp resolve_page(%{"page" => "crashdump"}, _pages),
    do: %{name: :crashdump, comp: CrashdumpPage}

  defp resolve_page(%{"page" => "ets"}, _pages), do: %{name: :ets, comp: EtsPage}
  defp resolve_page(%{"page" => "logs"}, _pages), do: %{name: :logs, comp: LogsPage}
  defp resolve_page(%{"page" => "metrics"}, _pages), do: %{name: :metrics, comp: MetricsPage}
  defp resolve_page(%{"page" => "network"}, _pages), do: %{name: :network, comp: NetworkPage}

  defp resolve_page(%{"page" => "processes"}, _pages),
    do: %{name: :processes, comp: ProcessesPage}

  defp resolve_page(%{"page" => "profiling"}, _pages),
    do: %{name: :profiling, comp: ProfilingPage}

  defp resolve_page(%{"page" => "system"}, _pages), do: %{name: :system, comp: SystemPage}
  defp resolve_page(%{"page" => "tracing"}, _pages), do: %{name: :tracing, comp: TracingPage}

  defp resolve_page(%{"page" => name}, custom_pages) do
    resolve_custom_page(name, custom_pages) || %{name: :system, comp: SystemPage}
  end

  defp resolve_page(_params, _custom_pages), do: %{name: :system, comp: SystemPage}

  defp resolve_custom_page(name, custom_pages) do
    Enum.find_value(custom_pages, fn {page_name, comp} ->
      if Atom.to_string(page_name) == name, do: %{name: page_name, comp: comp}
    end)
  end
end
