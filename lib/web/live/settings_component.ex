defmodule Observer.Web.SettingsComponent do
  @moduledoc """
  This module provides User component
  """
  use Observer.Web, :live_component

  alias Observer.Web.Components.Core
  alias Observer.Web.Components.Icons

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="inline-flex rounded-md shadow-sm" role="group">
      <button
        type="button"
        class="inline-flex items-center px-4 py-2 text-sm font-medium text-gray-900 bg-white border border-gray-200 rounded-s-lg hover:bg-gray-100 hover:text-blue-700 dark:bg-gray-700 dark:border-gray-600 dark:text-white dark:hover:text-white dark:hover:bg-gray-600"
      >
        <div class="relative w-5 h-5 overflow-hidden bg-gray-100 rounded-full dark:bg-gray-600">
          <svg
            class="absolute w-7 h-7 text-gray-400 -left-1"
            fill="currentColor"
            viewBox="0 0 20 20"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              fill-rule="evenodd"
              d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z"
              clip-rule="evenodd"
            >
            </path>
          </svg>
        </div>
        <div class="ml-3">
          {if @user == nil,
            do: "admin",
            else: Map.get(@user, :username) || Map.get(@user, :email) || "not defined"}
        </div>
      </button>

      <Core.tooltip
        :if={@version.status == :warning}
        label={
    "Version mismatch across nodes:\n" <>
    Enum.map_join(@version.nodes, "\n", fn {node, ver} -> "#{node}: v#{ver}" end)}
      >
        <button
          id="version-info"
          type="button"
          class="inline-flex items-center px-4 text-sm font-medium text-gray-900 bg-white border-t border-b border-gray-200 hover:bg-gray-100 hover:text-blue-700 dark:bg-gray-700 dark:border-gray-600 dark:text-white dark:hover:text-white dark:hover:bg-gray-600"
        >
          <Icons.exclamation_circle class="w-6 h-6 text-red-300 dark:text-red-200" />
          <div class="ml-2">
            Version
          </div>
        </button>
      </Core.tooltip>

      <div
        class="relative"
        id="theme-selector"
        data-shortcut={JS.push("cycle-theme", target: "#theme-selector")}
        phx-hook="Themer"
      >
        <button
          aria-expanded="true"
          aria-haspopup="listbox"
          class="inline-flex items-center px-4 py-2 text-sm font-medium text-gray-900 bg-white border border-gray-200 rounded-e-lg hover:bg-gray-100 hover:text-blue-700 dark:bg-gray-700 dark:border-gray-600 dark:text-white dark:hover:text-white dark:hover:bg-gray-600"
          data-title="Change theme"
          id="theme-menu-toggle"
          phx-click={JS.toggle(to: "#theme-menu")}
          type="button"
        >
          <.theme_icon theme={@theme} />
        </button>

        <ul
          class="hidden absolute z-50 top-full right-0 mt-2 w-32 overflow-hidden rounded-md shadow-lg text-sm font-semibold bg-white dark:bg-gray-800"
          id="theme-menu"
          role="listbox"
          tabindex="-1"
        >
          <.option
            :for={theme <- ~w(light dark system)}
            myself={@myself}
            theme={@theme}
            value={theme}
          />
        </ul>
      </div>
    </div>
    """
  end

  attr :myself, :any, required: true
  attr :theme, :string, required: true
  attr :value, :string, required: true

  defp option(assigns) do
    class =
      if assigns.theme == assigns.value do
        "text-blue-500 dark:text-blue-400"
      else
        "text-gray-500 dark:text-gray-400 "
      end

    assigns = assign(assigns, :class, class)

    ~H"""
    <li
      class={"block w-full py-1 px-2 flex items-center cursor-pointer space-x-2 hover:bg-gray-50 hover:dark:bg-gray-600/30 #{@class}"}
      id={"select-theme-#{@value}"}
      phx-click-away={JS.hide(to: "#theme-menu")}
      phx-click="update-theme"
      phx-target={@myself}
      phx-value-theme={@value}
      role="option"
    >
      <.theme_icon theme={@value} />
      <span class="capitalize text-gray-800 dark:text-gray-200">{@value}</span>
    </li>
    """
  end

  attr :theme, :string, required: true

  defp theme_icon(assigns) do
    ~H"""
    <%= case @theme do %>
      <% "light" -> %>
        <Icons.sun />
      <% "dark" -> %>
        <Icons.moon />
      <% "system" -> %>
        <Icons.computer_desktop />
    <% end %>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("update-theme", %{"theme" => theme}, socket) do
    send(self(), {:update_theme, theme})

    {:noreply, socket}
  end

  def handle_event("cycle-theme", _params, socket) do
    theme =
      case socket.assigns.theme do
        "light" -> "dark"
        "dark" -> "system"
        "system" -> "light"
      end

    send(self(), {:update_theme, theme})

    {:noreply, socket}
  end
end
