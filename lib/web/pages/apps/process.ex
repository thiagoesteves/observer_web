defmodule Observer.Web.Apps.Process do
  @moduledoc false

  use Observer.Web, :html
  use Phoenix.Component

  alias Observer.Web.Apps.ProcessActions
  alias Observer.Web.Components.Attention
  alias Observer.Web.Components.CopyToClipboard

  attr :info, :map, required: true
  attr :id, :map, required: true
  attr :form, :map, required: true
  attr :process_memory_monitor, :boolean, required: true

  def content(assigns) do
    info = assigns.info

    map_phx_lv_socket = fn
      %Phoenix.LiveView.Socket{} = phx_lv_socket ->
        [
          %{name: "Id", value: "#{phx_lv_socket.id}"},
          %{name: "Endpoint", value: "#{inspect(phx_lv_socket.endpoint)}"},
          %{name: "View", value: "#{inspect(phx_lv_socket.view)}"},
          %{name: "Router", value: "#{inspect(phx_lv_socket.router)}"},
          %{name: "Connected?", value: "#{inspect(phx_lv_socket.transport_pid)}"},
          %{name: "redirected", value: "#{inspect(phx_lv_socket.redirected)}"}
        ]

      _socket ->
        nil
    end

    map_phx_lv_socket_uri = fn
      %Phoenix.LiveView.Socket{host_uri: %URI{} = host_uri} ->
        [
          %{name: "Scheme", value: "#{host_uri.scheme}"},
          %{name: "User Info", value: "#{inspect(host_uri.userinfo)}"},
          %{name: "Host", value: "#{host_uri.host}"},
          %{name: "Port", value: "#{inspect(host_uri.port)}"},
          %{name: "Path", value: "#{host_uri.path}"},
          %{name: "Query", value: "#{inspect(host_uri.query)}"},
          %{name: "Fragment", value: "#{inspect(host_uri.fragment)}"}
        ]

      _socket ->
        nil
    end

    process_mappings =
      if is_map(info) do
        %{
          overview: [
            %{name: "Id", value: "#{inspect(info.pid)}"},
            %{name: "Registered name", value: "#{info.registered_name}"},
            %{name: "Status", value: "#{info.meta.status}"},
            %{name: "Class", value: "#{info.meta.class}"},
            %{name: "Message Queue Length", value: "#{info.message_queue_len}"},
            %{name: "Group Leader", value: "#{inspect(info.relations.group_leader)}"},
            %{name: "Trap exit", value: "#{info.trap_exit}"}
          ],
          memory: [
            %{name: "Total", value: "#{info.memory.total}"},
            %{name: "Heap Size", value: "#{info.memory.heap_size}"},
            %{name: "Stack Size", value: "#{info.memory.stack_size}"},
            %{name: "GC Min Heap Size", value: "#{info.memory.gc_min_heap_size}"},
            %{name: "GC FullSweep After", value: "#{info.memory.gc_full_sweep_after}"}
          ],
          phx_lv_socket: map_phx_lv_socket.(info.phx_lv_socket),
          phx_lv_socket_uri: map_phx_lv_socket_uri.(info.phx_lv_socket)
        }
      else
        nil
      end

    assigns =
      assigns
      |> assign(process_mappings: process_mappings)

    ~H"""
    <div class="max-w-full rounded overflow-hidden shadow-lg">
      <%= cond do %>
        <% @info == nil -> %>
        <% @info == :undefined -> %>
          <Attention.content
            id="apps-process-alert"
            title="Warning"
            class="border-red-400 text-red-500"
            message={"Process #{@id} is either dead or protected and therefore can not be shown."}
          />
        <% true -> %>
          <div id="process-information">
            <div class="flex grid grid-cols-3 gap-1 items-top">
              <ProcessActions.content
                id={@id}
                pid={@info.pid}
                form={@form}
                process_memory_monitor={@process_memory_monitor}
                on_action="request_process_action"
              />

              <Core.table_process
                id="process-overview-table"
                title="Overview"
                rows={@process_mappings.overview}
              >
                <:col :let={item}>
                  <span>{item.name}</span>
                </:col>
                <:col :let={item}>
                  {item.value}
                </:col>
              </Core.table_process>

              <Core.table_process
                id="process-memory-table"
                title="Memory"
                rows={@process_mappings.memory}
              >
                <:col :let={item}>
                  <span>{item.name}</span>
                </:col>
                <:col :let={item}>
                  {item.value}
                </:col>
              </Core.table_process>
            </div>

            <div class="flex grid grid-cols-2 mt-1 gap-1 items-top">
              <.relations
                title="State"
                value={"#{inspect(@info.state)}"}
                copy_id={"process-state-#{@id}"}
              />
              <.relations
                title="Dictionary"
                value={"#{inspect(@info.dictionary)}"}
                copy_id={"process-dictionary-#{@id}"}
              />
            </div>

            <div class="flex grid grid-cols-4 mt-1 gap-1 items-top">
              <.relations title="Links" value={"#{inspect(@info.relations.links)}"} />
              <.relations title="Ancestors" value={"#{inspect(@info.relations.ancestors)}" } />
              <.relations title="Monitors" value={"#{inspect(@info.relations.monitors)}"} />
              <.relations title="Monitored by" value={"#{inspect(@info.relations.monitored_by)}"} />
            </div>
          </div>
          <div
            :if={@process_mappings.phx_lv_socket}
            class="flex grid grid-cols-3 mt-1 gap-1 items-top"
            id="phx-socket-socket-information"
          >
            <Core.table_process
              id="phx-socket-socket-overview-table"
              title="Phoenix.LiveView.Socket"
              title_bg_color="liveview"
              rows={@process_mappings.phx_lv_socket}
            >
              <:col :let={item}>
                <span>{item.name}</span>
              </:col>
              <:col :let={item}>
                {item.value}
              </:col>
            </Core.table_process>

            <Core.table_process
              :if={@process_mappings.phx_lv_socket_uri}
              id="phx-socket-socket-uri-table"
              title="Phoenix.LiveView.Socket - URI"
              title_bg_color="liveview"
              rows={@process_mappings.phx_lv_socket_uri}
            >
              <:col :let={item}>
                <span>{item.name}</span>
              </:col>
              <:col :let={item}>
                {item.value}
              </:col>
            </Core.table_process>
            <.relations
              title="Phoenix.LiveView.Socket - Assigns"
              title_bg_color="liveview"
              value={to_string(:io_lib.format("~tp", [@info.phx_lv_socket.assigns]))}
              copy_id={"lv-assigns-#{@id}"}
            />
          </div>
      <% end %>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :copy_id, :string, default: nil
  attr :title_bg_color, :string, default: "standard"

  defp relations(assigns) do
    ~H"""
    <div class=" text-sm text-center block rounded bg-white dark:bg-gray-800 border border-solid border-blueGray-100 shadow-secondary-1 text-surface">
      <div class={[
        "font-mono font-semibold border-b-1 rounded-t border-neutral-100 px-6 py-1",
        title_bg_color(@title_bg_color)
      ]}>
        <%= if @copy_id do %>
          <div class="flex items-center justify-between  w-full">
            {@title}
            <CopyToClipboard.content :if={@copy_id} id={@copy_id} message={@value} />
          </div>
        <% else %>
          {@title}
        <% end %>
      </div>
      <div class="p-2" style="max-height: 200px; overflow-y: auto;">
        <span class="text-xs font-mono leading-tight">
          {@value}
        </span>
      </div>
    </div>
    """
  end

  defp title_bg_color("liveview"), do: "bg-green-200 dark:bg-green-900"
  defp title_bg_color(_any), do: "bg-zinc-200 dark:bg-zinc-500"
end
