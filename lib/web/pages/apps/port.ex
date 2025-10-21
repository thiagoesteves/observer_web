defmodule Observer.Web.Apps.Port do
  @moduledoc false

  use Observer.Web, :html
  use Phoenix.Component

  alias Observer.Web.Apps.PortActions
  alias Observer.Web.Components.Attention

  attr :info, :map, required: true
  attr :id, :string, required: true

  def content(assigns) do
    info = assigns.info

    port_overview =
      if is_map(info) do
        [
          %{name: "Id", value: "#{info.id}"},
          %{name: "Name", value: "#{info.name}"},
          %{name: "Os Pid", value: "#{info.os_pid}"},
          %{name: "Connected", value: "#{inspect(info.connected)}"}
        ]
      else
        nil
      end

    assigns =
      assigns
      |> assign(port_overview: port_overview)

    ~H"""
    <div class="max-w-full rounded overflow-hidden shadow-lg">
      <%= cond do %>
        <% @info == nil -> %>
        <% @info == :undefined -> %>
          <Attention.content
            id="observer-port"
            title="Warning"
            class="border-red-400 text-red-500"
            message={"Port #{@id} is either dead or protected and therefore can not be shown."}
          />
        <% true -> %>
          <div id="port_information">
            <div class="flex grid grid-cols-3  gap-1 items-top">
              <PortActions.content id={@id} on_action="request_port_action" />
              <Core.table_process id="port-overview-table" title="Overview" rows={@port_overview}>
                <:col :let={item}>
                  <span>{item.name}</span>
                </:col>
                <:col :let={item}>
                  {item.value}
                </:col>
              </Core.table_process>
            </div>
          </div>
      <% end %>
    </div>
    """
  end
end
