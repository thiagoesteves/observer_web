defmodule Observer.Web.Apps.ProcessActions do
  @moduledoc """
  Component for managing process actions like killing, garbage collecting, sending messages, and monitoring.
  """

  use Observer.Web, :html
  use Phoenix.Component

  attr :id, :map, required: true
  attr :pid, :any, required: true
  attr :on_action, :any, required: true
  attr :form, :map, required: true
  attr :process_memory_monitor, :boolean, required: true

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

          <span class="flex items-center justify-start"> Call garbage collect for the process </span>

          <button
            phx-click={@on_action}
            phx-value-action="kill"
            class="flex items-center justify-center gap-2 px-4 py-2.5 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 text-sm font-semibold rounded-lg border border-gray-300 dark:border-gray-600 shadow-sm hover:shadow transition-all duration-200 active:scale-95"
            title="Terminate this process"
          >
            <span>⛔</span>
            <span>Kill</span>
          </button>
          <span class="flex items-center justify-start"> Kill the process </span>
        </div>
      </div>

      <div class="p-1">
        <.form
          for={@form}
          phx-submit={@on_action}
          id="test"
          phx-change="process-message-form-update"
          class="space-y-2"
        >
          <div class="flex gap-2 w-full">
            <Core.input
              name="process-send-message"
              type="text"
              value=""
              field={@form[:message]}
              placeholder="Type a valid elixir message"
              required
            />
            <button
              type="submit"
              phx-disable-with="Sending..."
              class={[
                "flex items-center justify-center px-2 text-sm font-semibold rounded-lg border shadow-sm hover:shadow transition-all duration-200 active:scale-95",
                if(@form.errors == [],
                  do:
                    "bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 border-gray-300 dark:border-gray-600",
                  else:
                    "bg-gray-50 dark:bg-gray-800 text-gray-400 dark:text-gray-500 border-gray-200 dark:border-gray-700 cursor-not-allowed"
                )
              ]}
              title="Send a message to this process"
              disabled={@form.errors != [] or @form.params["message"] == ""}
            >
              <span>Send</span>
            </button>
          </div>
        </.form>
      </div>

      <label class="flex me-5 p-1 cursor-pointer">
        <input
          type="checkbox"
          phx-click={@on_action}
          name="process-toggle-memory-monitoring-checkbox"
          value=""
          class="sr-only peer"
          checked={@process_memory_monitor}
        />
        <div class="relative w-11 h-6 bg-gray-200 rounded-full peer dark:bg-gray-700 peer-focus:ring-4 peer-focus:ring-teal-300 dark:peer-focus:ring-teal-800 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-0.5 after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all dark:border-gray-600 peer-checked:bg-teal-600 dark:peer-checked:bg-teal-600">
        </div>
        <span class="ms-3 text-sm font-medium text-gray-900 dark:text-gray-300">Memory Monitor</span>
      </label>

      <p class="text-xs text-gray-500 dark:text-gray-400 mt-3 italic">
        Process ID: <span class="font-mono text-gray-600 dark:text-gray-300">{inspect(@pid)}</span>
      </p>
    </div>
    """
  end
end
