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
            <span>Clean Memory (Garbage collect)</span>
          </button>

          <span class="flex items-center justify-start"> Clean Memory </span>
          <.form
            for={@form}
            phx-submit={@on_action}
            id="test"
            phx-change="process-message-form-update"
            class="space-y-2"
          >
            <div class="flex gap-2">
              <Core.input
                name="process-send-message"
                type="text"
                value=""
                field={@form[:message]}
                placeholder="Message to send"
                required
              />
              <button
                type="submit"
                phx-disable-with="Sending..."
                class={[
                  "flex items-center justify-center gap-2 px-4 py-2.5 text-sm font-semibold rounded-lg border shadow-sm hover:shadow transition-all duration-200 active:scale-95",
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
                <span>✉️</span>
                <span>Send</span>
              </button>
            </div>
          </.form>
          <span class="flex items-center justify-start"> Send a message to the process </span>

          <button
            phx-click={@on_action}
            phx-value-action="toggle_monitor"
            class="flex items-center justify-center gap-2 px-4 py-2.5 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 text-sm font-semibold rounded-lg border border-gray-300 dark:border-gray-600 shadow-sm hover:shadow transition-all duration-200 active:scale-95"
            title="Toggle monitoring of this process"
          >
            <span>👁️</span>
            <span>Monitor</span>
          </button>
          <span class="flex items-center justify-start"> Memory monitoring for the process </span>

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

      <p class="text-xs text-gray-500 dark:text-gray-400 mt-3 italic">
        Process ID: <span class="font-mono text-gray-600 dark:text-gray-300">{inspect(@pid)}</span>
      </p>
    </div>
    """
  end
end
