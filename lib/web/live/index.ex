defmodule Observer.Web.IndexLive do
  @moduledoc """
  This module provides Observer context

  ## References:
   * https://github.com/thiagoesteves/deployex/blob/main/lib/deployex_web/live/tracing/index.ex
   * https://github.com/oban-bg/oban_web/blob/main/lib/oban/web/dashboard_live.ex
  """

  use Observer.Web, :live_view

  alias Observer.Web.Apps.Page, as: AppsPage
  alias Observer.Web.Metrics.Page, as: MetricsPage
  alias Observer.Web.Tracing.Page, as: TracingPage

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    %{"prefix" => prefix, "resolver" => resolver} = session
    %{"live_path" => live_path, "live_transport" => live_transport} = session
    %{"user" => user, "access" => access, "csp_nonces" => csp_nonces} = session

    page = resolve_page(params)

    Process.put(:routing, {socket, prefix})

    socket =
      socket
      |> assign(params: params, page: page)
      |> assign(live_path: live_path, live_transport: live_transport)
      |> assign(access: access, csp_nonces: csp_nonces, resolver: resolver, user: user)
      |> assign(timer: nil)
      |> init_schedule_refresh()
      |> page.comp.handle_mount()

    {:ok, socket}
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
  def terminate(_reason, %{assigns: %{timer: timer}}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl Phoenix.LiveView
  def handle_params(params, uri, socket) do
    socket.assigns.page.comp.handle_params(params, uri, socket)
  end

  @impl Phoenix.LiveView
  def handle_info(:refresh, socket) do
    socket =
      socket
      |> socket.assigns.page.comp.handle_refresh()
      |> schedule_refresh()

    {:noreply, socket}
  end

  def handle_info(message, socket) do
    socket.assigns.page.comp.handle_info(message, socket)
  end

  @impl Phoenix.LiveView
  def handle_event(message, value, socket) do
    socket.assigns.page.comp.handle_parent_event(message, value, socket)
  end

  ## Render Helpers

  defp resolve_page(%{"page" => "applications"}),
    do: %{name: :applications, comp: AppsPage, refresh: 3}

  defp resolve_page(%{"page" => "metrics"}), do: %{name: :metrics, comp: MetricsPage, refresh: 0}
  defp resolve_page(_params), do: %{name: :tracing, comp: TracingPage, refresh: 0}

  ## Refresh Helpers

  defp init_schedule_refresh(socket) do
    if connected?(socket) do
      schedule_refresh(socket)
    else
      assign(socket, timer: nil)
    end
  end

  defp schedule_refresh(socket) do
    if is_reference(socket.assigns.timer), do: Process.cancel_timer(socket.assigns.timer)

    if socket.assigns.page.refresh > 0 do
      interval = :timer.seconds(socket.assigns.page.refresh) - 50

      assign(socket, timer: Process.send_after(self(), :refresh, interval))
    else
      assign(socket, timer: nil)
    end
  end
end
