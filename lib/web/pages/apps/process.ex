defmodule Observer.Web.Apps.Process do
  @moduledoc false

  use Observer.Web, :html
  use Phoenix.Component

  alias Observer.Web.Components.Attention

  attr :info, :map, required: true
  attr :id, :map, required: true

  def content(assigns) do
    info = assigns.info

    map_phx_lv_socket = fn
      nil ->
        nil

      phx_lv_socket ->
        [
          %{name: "Id", value: "#{phx_lv_socket.id}"},
          %{name: "Endpoint", value: "#{inspect(phx_lv_socket.endpoint)}"},
          %{name: "View", value: "#{inspect(phx_lv_socket.view)}"},
          %{name: "Router", value: "#{inspect(phx_lv_socket.router)}"},
          %{name: "Connected?", value: "#{inspect(phx_lv_socket.transport_pid)}"},
          %{name: "redirected", value: "#{inspect(phx_lv_socket.redirected)}"}
        ]
    end

    map_phx_lv_socket_uri = fn
      nil ->
        nil

      phx_lv_socket ->
        [
          %{name: "Scheme", value: "#{phx_lv_socket.host_uri.scheme}"},
          %{name: "User Info", value: "#{inspect(phx_lv_socket.host_uri.userinfo)}"},
          %{name: "Host", value: "#{phx_lv_socket.host_uri.host}"},
          %{name: "Port", value: "#{inspect(phx_lv_socket.host_uri.port)}"},
          %{name: "Path", value: "#{phx_lv_socket.host_uri.path}"},
          %{name: "Query", value: "#{inspect(phx_lv_socket.host_uri.query)}"},
          %{name: "Fragment", value: "#{inspect(phx_lv_socket.host_uri.fragment)}"}
        ]
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
              <.relations title="State" value={"#{inspect(@info.state)}"} />
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
              title_bg_color="MediumSeaGreen"
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
              id="phx-socket-socket-uri-table"
              title="Phoenix.LiveView.Socket - URI"
              title_bg_color="MediumSeaGreen"
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
              title_bg_color="MediumSeaGreen"
              value={to_string(:io_lib.format("~tp", [@info.phx_lv_socket.assigns]))}
            />
          </div>
      <% end %>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :title_bg_color, :string, default: "LightGray"

  defp relations(assigns) do
    ~H"""
    <div class=" text-sm text-center block rounded-lg bg-white border border-solid border-blueGray-100 shadow-secondary-1 text-surface">
      <div
        class="font-mono font-semibold border-b-2 border-neutral-100 px-6 py-1"
        style={"background-color: #{@title_bg_color};"}
      >
        {@title}
      </div>
      <div class="p-2" style="max-height: 200px; overflow-y: auto;">
        <span class="text-xs font-mono leading-tight">
          {@value}
        </span>
      </div>
    </div>
    """
  end
end
