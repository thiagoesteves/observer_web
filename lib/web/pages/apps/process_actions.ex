defmodule Observer.Web.Apps.ProcessActions do
  @moduledoc """
  Component for managing process actions like killing, garbage collecting, sending messages, and monitoring.
  """

  use Observer.Web, :html
  use Phoenix.Component

  attr :id, :map, required: true
  attr :pid, :any, required: true
  attr :on_action, :any, required: true

  def content(assigns) do
    ~H"""
    <div class="text-sm text-center block rounded bg-white dark:bg-gray-800 border border-solid border-blueGray-100 shadow-secondary-1 text-surface">
      <div class="font-mono font-semibold border-b-1 rounded-t border-neutral-100 px-6 py-1 bg-zinc-200 dark:bg-zinc-500">
        Process Actions
      </div>

      <div class="space-y-3 p-1">
        <div class="grid grid-cols-2 gap-3">
          <button
            phx-click={@on_action}
            phx-value-action="garbage_collect"
            class="flex items-center justify-center gap-2 px-4 py-2.5 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 text-sm font-semibold rounded-lg border border-gray-300 dark:border-gray-600 shadow-sm hover:shadow transition-all duration-200 active:scale-95"
            title="Run garbage collection on this process"
          >
            <span>🧹</span>
            <span>Clean Memory</span>
          </button>

          <span class="flex items-center"> Clean Memory </span>

          <button
            phx-click={@on_action}
            phx-value-action="send_message"
            class="flex items-center justify-center gap-2 px-4 py-2.5 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 text-sm font-semibold rounded-lg border border-gray-300 dark:border-gray-600 shadow-sm hover:shadow transition-all duration-200 active:scale-95"
            title="Send a message to this process"
          >
            <span>✉️</span>
            <span>Send Message</span>
          </button>
          <span class="flex items-center"> Clean Memory </span>

          <button
            phx-click={@on_action}
            phx-value-action="toggle_monitor"
            class="flex items-center justify-center gap-2 px-4 py-2.5 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 text-sm font-semibold rounded-lg border border-gray-300 dark:border-gray-600 shadow-sm hover:shadow transition-all duration-200 active:scale-95"
            title="Toggle monitoring of this process"
          >
            <span>👁️</span>
            <span>Monitor</span>
          </button>
          <span class="flex items-center"> Clean Memory </span>

          <button
            phx-click={@on_action}
            phx-value-action="kill"
            class="flex items-center justify-center gap-2 px-4 py-2.5 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 text-sm font-semibold rounded-lg border border-gray-300 dark:border-gray-600 shadow-sm hover:shadow transition-all duration-200 active:scale-95"
            title="Terminate this process"
          >
            <span>⛔</span>
            <span>Kill</span>
          </button>
          <span class="flex items-center"> Clean Memory </span>
        </div>
      </div>

      <p class="text-xs text-gray-500 dark:text-gray-400 mt-3 italic">
        Process ID: <span class="font-mono text-gray-600 dark:text-gray-300">{inspect(@pid)}</span>
      </p>
    </div>
    """
  end
end
