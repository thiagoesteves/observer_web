defmodule Observer.Web.Layouts do
  @moduledoc """
  This module provides layouts

  ## References:
   * https://github.com/oban-bg/oban_web/blob/main/lib/oban/web/components/layouts.ex
  """
  use Observer.Web, :html

  embed_templates "layouts/*"

  alias Observer.Web.Assets
  alias Observer.Web.Components.Icons

  defp asset_path(conn, asset) when asset in [:css, :js] do
    hash = Assets.current_hash(asset)

    # prefix = conn.private.phoenix_router.__live_dashboard_prefix__()
    prefix = "/observer"

    Phoenix.VerifiedRoutes.unverified_path(
      conn,
      conn.private.phoenix_router,
      "#{prefix}/#{asset}-#{hash}"
    )
  end

  def logo(assigns) do
    ~H"""
    <a href={observer_path(:tracing, @params)} class="flex" title="Observer Web">
      <div>
        <Icons.content name={:logo} />
      </div>
      <h3 class="class ml-2 items-center tracking-tight ">
        <span class="block text-4xl text-gray-900 dark:text-white">
          Observer
          <span class="text-transparent text-4xl font-bold bg-clip-text bg-gradient-to-tr to-cyan-500 from-blue-600">
            WEB
          </span>
        </span>
      </h3>
    </a>
    """
  end

  def nav(assigns) do
    ~H"""
    <nav class="flex space-x-1">
      <.link
        :for={page <- list_pages_by_params(@params)}
        class={link_class(@page, page)}
        data-shortcut={JS.navigate(observer_path(page, @params))}
        id={"nav-#{page}"}
        navigate={observer_path(page, @params)}
        title={"Navigate to #{String.capitalize(to_string(page))}"}
      >
        <Icons.content name={page} />
        {String.upcase(to_string(page))}
      </.link>
    </nav>
    """
  end

  def footer(assigns) do
    assigns =
      assign(assigns,
        oss_version: Application.spec(:observer_web, :vsn)
      )

    ~H"""
    <footer class="flex flex-col px-3 py-6 text-sm justify-center items-center md:flex-row">
      <.version name="Observer Web" version={@oss_version} />

      <span class="text-gray-800 dark:text-gray-200 font-semibold">
        Made by
        <a
          href="https://www.linkedin.com/in/thiago-cesar-calori-esteves-972368115/"
          class="font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline"
        >
          Thiago Esteves
        </a>
      </span>
    </footer>
    """
  end

  attr :name, :string
  attr :version, :string

  defp version(assigns) do
    ~H"""
    <span class="text-gray-600 dark:text-gray-400 tabular mr-0 mb-1 md:mr-3 md:mb-0">
      {@name} {if @version, do: "v#{@version}", else: "–"}
    </span>
    """
  end

  defp link_class(curr, page) do
    base =
      "flex items-center px-4 py-2.5 text-sm font-bold transition-all duration-200 text-gray-900 dark:text-white rounded-lg group"

    if curr == page do
      base <> " bg-gray-100 dark:bg-gray-700"
    else
      base <> " hover:text-black dark:hover:text-white hover:bg-cyan-500 dark:hover:bg-cyan-800"
    end
  end

  defp list_pages_by_params(%{"iframe" => "true"}), do: [:tracing, :applications, :metrics]
  defp list_pages_by_params(_params), do: [:root, :tracing, :applications, :metrics]

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook="AutoDismissFlash"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label="close">
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end
end
