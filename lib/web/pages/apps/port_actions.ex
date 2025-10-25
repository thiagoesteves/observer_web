defmodule Observer.Web.Apps.PortActions do
  @moduledoc """
  Component for managing port actions like closing, etc.
  """

  use Observer.Web, :html
  use Phoenix.Component

  attr :id, :string, required: true
  attr :on_action, :any, required: true
  attr :memory_monitor, :boolean, required: true
  attr :node, :atom, required: true

  def content(assigns) do
    ~H"""
    <div class="text-sm text-center block rounded bg-white dark:bg-gray-800 border border-solid border-blueGray-100 shadow-secondary-1 text-surface">
      <div class="font-mono font-semibold border-b-1 rounded-t border-neutral-100 px-6 py-1 bg-zinc-200 dark:bg-zinc-500">
        Port Actions
      </div>

      <div class="space-y-3 p-1">
        <div class="grid grid-cols-2 gap-3">
          <button
            id="port-close-button"
            phx-click={@on_action}
            phx-value-action="kill"
            class="flex items-center justify-center gap-2 px-4 py-2 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 text-sm font-semibold rounded-lg border border-gray-300 dark:border-gray-600 shadow-sm hover:shadow transition-all duration-200 active:scale-95 tooltip"
            title="Close the selected port"
          >
            <span>⛔</span>
            <span>Close</span>
          </button>
        </div>
      </div>

      <label class="flex me-5 p-1 cursor-pointer">
        <input
          type="checkbox"
          phx-click={@on_action}
          phx-value-type="toggle-memory"
          name="port-toggle-memory-monitoring-checkbox"
          value=""
          class="sr-only peer"
          checked={@memory_monitor}
        />
        <div class="relative w-11 h-6 bg-gray-200 rounded-full peer dark:bg-gray-700 peer-focus:ring-4 peer-focus:ring-teal-300 dark:peer-focus:ring-teal-800 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-0.5 after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all dark:border-gray-600 peer-checked:bg-teal-600 dark:peer-checked:bg-teal-600">
        </div>
        <span class="ms-3 text-sm font-medium text-gray-900 dark:text-gray-300">Memory Monitor</span>
      </label>

      <div>
        <p class="text-xs text-gray-500 dark:text-gray-400 mt-3 italic">
          Node: <span class="font-mono text-gray-700 dark:text-gray-200">{@node}</span>
        </p>
        <p class="text-xs text-gray-500 dark:text-gray-400 p-1 italic">
          Port ID:
          <span class="font-mono text-gray-600 dark:text-gray-300">{port_info(@node, @id)}</span>
        </p>
      </div>
    </div>
    """
  end

  defp port_info(node, id) do
    if node == node(), do: "#{id} (local)", else: "#{id} (remote)"
  end
end
